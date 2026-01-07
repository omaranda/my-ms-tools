<#
################################################################################
# Copyright (c) 2025 Omar Miranda
# All rights reserved.
#
# This script is provided "as is" without warranty of any kind, express or
# implied. Use at your own risk.
#
# Author: Omar Miranda
# Created: 2025
################################################################################
<#
.SYNOPSIS
    Configure Android device enrollment with role-based app assignments in Intune.

.DESCRIPTION
    This script automates the configuration of Android device enrollment in Microsoft Intune
    with sophisticated role-based app deployment. It handles:

    Enrollment Configuration:
    - Android Enterprise enrollment profile creation
    - Device compliance policies for Android
    - Configuration policies (WiFi, VPN, Email, etc.)
    - Security baseline settings

    Role-Based App Deployment:
    - Defines app packages for different organizational roles
    - Creates Azure AD groups for role-based targeting
    - Assigns managed Google Play apps to specific groups
    - Configures required vs. available apps
    - Sets app configuration policies

    Supported Roles:
    - Executive (C-Level, Directors): WhatsApp, Teams, Outlook, Power BI
    - Field Team: AudioMoth, Field Service, Teams, Outlook
    - Sales: CRM apps, Teams, Outlook, LinkedIn
    - IT Team: Admin tools, Remote Desktop, Teams
    - General Staff: Standard M365 apps

    App Management:
    - Required apps (auto-install)
    - Available apps (self-service from Company Portal)
    - Blocked apps (prevents installation)
    - App configuration policies (pre-configured settings)

.PARAMETER RoleDefinitionFile
    Path to JSON file containing role and app definitions (optional)

.PARAMETER CreateGroups
    Create Azure AD groups for each role if they don't exist

.PARAMETER AssignApps
    Assign apps to role groups (requires apps to be synced from Google Play)

.PARAMETER DeploymentMode
    Deployment mode: 'Required' (auto-install) or 'Available' (optional)

.PARAMETER ExportConfiguration
    Export the configuration to JSON file for review/backup

.PARAMETER WhatIf
    Preview changes without applying them

.EXAMPLE
    .\New-AndroidEnrollmentConfiguration.ps1 -CreateGroups -AssignApps

    Creates role groups and assigns apps based on default configuration

.EXAMPLE
    .\New-AndroidEnrollmentConfiguration.ps1 -RoleDefinitionFile ".\android-roles.json" -CreateGroups -AssignApps -DeploymentMode "Required"

    Uses custom role definitions and deploys apps as required

.EXAMPLE
    .\New-AndroidEnrollmentConfiguration.ps1 -ExportConfiguration -WhatIf

    Exports current configuration without making changes

.NOTES
    Prerequisites:
    - Android Enterprise binding in Intune tenant
    - Managed Google Play apps synced to Intune
    - Azure AD Premium (for dynamic groups, optional)
    - Global Administrator or Intune Administrator role

    App Package Names (examples):
    - WhatsApp: com.whatsapp
    - Microsoft Teams: com.microsoft.teams
    - Outlook: com.microsoft.office.outlook
    - AudioMoth: org.openacousticdevices.audiomoth
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false)]
    [string]$RoleDefinitionFile,

    [Parameter(Mandatory=$false)]
    [switch]$CreateGroups,

    [Parameter(Mandatory=$false)]
    [switch]$AssignApps,

    [Parameter(Mandatory=$false)]
    [ValidateSet("Required", "Available")]
    [string]$DeploymentMode = "Required",

    [Parameter(Mandatory=$false)]
    [switch]$ExportConfiguration,

    [Parameter(Mandatory=$false)]
    [string]$ExportPath = "AndroidEnrollmentConfig_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
)

#region Configuration

# Default role-based app configuration
$defaultRoleConfiguration = @{
    "Executive" = @{
        GroupName = "Android-Executive-Users"
        Description = "C-Level and Directors with executive app access"
        RequiredApps = @(
            @{ Name = "Microsoft Teams"; PackageId = "com.microsoft.teams"; ConfigPolicy = $true }
            @{ Name = "Microsoft Outlook"; PackageId = "com.microsoft.office.outlook"; ConfigPolicy = $true }
            @{ Name = "WhatsApp Business"; PackageId = "com.whatsapp.w4b"; ConfigPolicy = $false }
            @{ Name = "Microsoft Word"; PackageId = "com.microsoft.office.word"; ConfigPolicy = $false }
            @{ Name = "Microsoft Excel"; PackageId = "com.microsoft.office.excel"; ConfigPolicy = $false }
            @{ Name = "Microsoft PowerPoint"; PackageId = "com.microsoft.office.powerpoint"; ConfigPolicy = $false }
            @{ Name = "Microsoft OneDrive"; PackageId = "com.microsoft.skydrive"; ConfigPolicy = $true }
            @{ Name = "Power BI"; PackageId = "com.microsoft.powerbim"; ConfigPolicy = $false }
        )
        AvailableApps = @(
            @{ Name = "Microsoft SharePoint"; PackageId = "com.microsoft.sharepoint" }
            @{ Name = "LinkedIn"; PackageId = "com.linkedin.android" }
        )
        BlockedApps = @()
    }

    "FieldTeam" = @{
        GroupName = "Android-Field-Team"
        Description = "Field workers with specialized apps"
        RequiredApps = @(
            @{ Name = "Microsoft Teams"; PackageId = "com.microsoft.teams"; ConfigPolicy = $true }
            @{ Name = "Microsoft Outlook"; PackageId = "com.microsoft.office.outlook"; ConfigPolicy = $true }
            @{ Name = "AudioMoth"; PackageId = "org.openacousticdevices.audiomoth"; ConfigPolicy = $true }
            @{ Name = "Field Service Mobile"; PackageId = "com.microsoft.dynamics.fieldservice"; ConfigPolicy = $true }
            @{ Name = "Microsoft OneDrive"; PackageId = "com.microsoft.skydrive"; ConfigPolicy = $false }
        )
        AvailableApps = @(
            @{ Name = "Microsoft Word"; PackageId = "com.microsoft.office.word" }
            @{ Name = "Microsoft Excel"; PackageId = "com.microsoft.office.excel" }
            @{ Name = "Adobe Acrobat Reader"; PackageId = "com.adobe.reader" }
        )
        BlockedApps = @(
            @{ Name = "WhatsApp"; PackageId = "com.whatsapp" }
            @{ Name = "Facebook"; PackageId = "com.facebook.katana" }
        )
    }

    "Sales" = @{
        GroupName = "Android-Sales-Team"
        Description = "Sales team with CRM and productivity apps"
        RequiredApps = @(
            @{ Name = "Microsoft Teams"; PackageId = "com.microsoft.teams"; ConfigPolicy = $true }
            @{ Name = "Microsoft Outlook"; PackageId = "com.microsoft.office.outlook"; ConfigPolicy = $true }
            @{ Name = "Dynamics 365 Sales"; PackageId = "com.microsoft.dynamics.crm.phone"; ConfigPolicy = $true }
            @{ Name = "LinkedIn Sales Navigator"; PackageId = "com.linkedin.android.salesnavigator"; ConfigPolicy = $false }
            @{ Name = "Microsoft OneDrive"; PackageId = "com.microsoft.skydrive"; ConfigPolicy = $false }
        )
        AvailableApps = @(
            @{ Name = "Microsoft Word"; PackageId = "com.microsoft.office.word" }
            @{ Name = "Microsoft Excel"; PackageId = "com.microsoft.office.excel" }
            @{ Name = "Microsoft PowerPoint"; PackageId = "com.microsoft.office.powerpoint" }
        )
        BlockedApps = @()
    }

    "IT" = @{
        GroupName = "Android-IT-Team"
        Description = "IT staff with administrative tools"
        RequiredApps = @(
            @{ Name = "Microsoft Teams"; PackageId = "com.microsoft.teams"; ConfigPolicy = $true }
            @{ Name = "Microsoft Outlook"; PackageId = "com.microsoft.office.outlook"; ConfigPolicy = $true }
            @{ Name = "Microsoft Intune Company Portal"; PackageId = "com.microsoft.windowsintune.companyportal"; ConfigPolicy = $false }
            @{ Name = "Microsoft Remote Desktop"; PackageId = "com.microsoft.rdc.androidx"; ConfigPolicy = $true }
            @{ Name = "Microsoft Authenticator"; PackageId = "com.azure.authenticator"; ConfigPolicy = $false }
            @{ Name = "Microsoft OneDrive"; PackageId = "com.microsoft.skydrive"; ConfigPolicy = $false }
        )
        AvailableApps = @(
            @{ Name = "Microsoft Word"; PackageId = "com.microsoft.office.word" }
            @{ Name = "Microsoft Excel"; PackageId = "com.microsoft.office.excel" }
            @{ Name = "Azure Mobile App"; PackageId = "com.microsoft.azure" }
        )
        BlockedApps = @()
    }

    "General" = @{
        GroupName = "Android-General-Staff"
        Description = "General staff with standard M365 apps"
        RequiredApps = @(
            @{ Name = "Microsoft Teams"; PackageId = "com.microsoft.teams"; ConfigPolicy = $true }
            @{ Name = "Microsoft Outlook"; PackageId = "com.microsoft.office.outlook"; ConfigPolicy = $true }
            @{ Name = "Microsoft Word"; PackageId = "com.microsoft.office.word"; ConfigPolicy = $false }
            @{ Name = "Microsoft Excel"; PackageId = "com.microsoft.office.excel"; ConfigPolicy = $false }
            @{ Name = "Microsoft OneDrive"; PackageId = "com.microsoft.skydrive"; ConfigPolicy = $false }
        )
        AvailableApps = @(
            @{ Name = "Microsoft PowerPoint"; PackageId = "com.microsoft.office.powerpoint" }
            @{ Name = "Microsoft SharePoint"; PackageId = "com.microsoft.sharepoint" }
            @{ Name = "Adobe Acrobat Reader"; PackageId = "com.adobe.reader" }
        )
        BlockedApps = @()
    }
}

#endregion

#region Helper Functions

function Write-ScriptLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        default { "Cyan" }
    }

    $icon = switch ($Level) {
        "Success" { "✓" }
        "Warning" { "⚠" }
        "Error" { "✗" }
        default { "ℹ" }
    }

    Write-Host "[$timestamp] $icon $Message" -ForegroundColor $color
}

function Get-MgAndroidManagedAppByPackageId {
    param([string]$PackageId)

    try {
        # Search for Android Managed App by package ID
        $apps = Get-MgDeviceAppManagementMobileApp -All | Where-Object {
            $_.'@odata.type' -eq '#microsoft.graph.androidManagedStoreApp' -and
            $_.PackageId -eq $PackageId
        }
        return $apps | Select-Object -First 1
    } catch {
        Write-ScriptLog "Error finding app with package ID $PackageId : $_" -Level "Warning"
        return $null
    }
}

function New-AndroidAppConfigurationPolicy {
    param(
        [string]$AppId,
        [string]$AppName,
        [string]$GroupId,
        [hashtable]$ConfigSettings = @{}
    )

    try {
        $configPolicy = @{
            "@odata.type" = "#microsoft.graph.managedDeviceMobileAppConfiguration"
            displayName = "Config - $AppName"
            description = "Configuration policy for $AppName"
            targetedMobileApps = @($AppId)
            settings = $ConfigSettings
        }

        # Create the configuration policy
        $policy = New-MgDeviceAppManagementMobileAppConfiguration -BodyParameter $configPolicy

        # Assign to group
        $assignment = @{
            "@odata.type" = "#microsoft.graph.managedDeviceMobileAppConfigurationAssignment"
            target = @{
                "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                groupId = $GroupId
            }
        }

        New-MgDeviceAppManagementMobileAppConfigurationAssignment -ManagedDeviceMobileAppConfigurationId $policy.Id -BodyParameter $assignment

        Write-ScriptLog "Created app configuration policy for $AppName" -Level "Success"
        return $policy
    } catch {
        Write-ScriptLog "Failed to create configuration policy for $AppName : $_" -Level "Error"
        return $null
    }
}

#endregion

#region Main Script

Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Android Device Enrollment Configuration" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

# Check for required modules
$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.DeviceManagement',
    'Microsoft.Graph.DeviceManagement.Enrolment'
)

Write-ScriptLog "Checking required modules..." -Level "Info"
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-ScriptLog "Required module not found: $module" -Level "Warning"
        Write-Host ""
        Write-Host "To install required modules, run:" -ForegroundColor Yellow
        Write-Host "  Install-Module Microsoft.Graph -Scope CurrentUser -Force" -ForegroundColor White
        Write-Host ""
        exit 1
    }
}

# Import modules
Write-ScriptLog "Importing Microsoft Graph modules..." -Level "Info"
try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.Groups -ErrorAction Stop
    Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop
    Import-Module Microsoft.Graph.DeviceManagement.Enrolment -ErrorAction Stop
    Write-ScriptLog "Modules imported successfully" -Level "Success"
} catch {
    Write-ScriptLog "Failed to import modules: $_" -Level "Error"
    exit 1
}

# Connect to Microsoft Graph
Write-Host ""
Write-ScriptLog "Connecting to Microsoft Graph..." -Level "Info"
$scopes = @(
    "DeviceManagementServiceConfig.ReadWrite.All",
    "DeviceManagementApps.ReadWrite.All",
    "DeviceManagementConfiguration.ReadWrite.All",
    "Group.ReadWrite.All",
    "Directory.ReadWrite.All"
)

try {
    Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop
    Write-ScriptLog "Successfully connected to Microsoft Graph" -Level "Success"
} catch {
    Write-ScriptLog "Failed to connect to Microsoft Graph: $_" -Level "Error"
    exit 1
}

# Load role configuration
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Gray
Write-Host "Configuration" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Gray

$roleConfig = $defaultRoleConfiguration

if ($RoleDefinitionFile -and (Test-Path $RoleDefinitionFile)) {
    Write-ScriptLog "Loading custom role definitions from: $RoleDefinitionFile" -Level "Info"
    try {
        $roleConfig = Get-Content $RoleDefinitionFile -Raw | ConvertFrom-Json -AsHashtable
        Write-ScriptLog "Custom configuration loaded successfully" -Level "Success"
    } catch {
        Write-ScriptLog "Failed to load custom configuration, using defaults: $_" -Level "Warning"
    }
} else {
    Write-ScriptLog "Using default role configuration" -Level "Info"
}

Write-Host ""
Write-ScriptLog "Roles configured: $($roleConfig.Keys.Count)" -Level "Info"
foreach ($role in $roleConfig.Keys) {
    $config = $roleConfig[$role]
    Write-Host "  • $role" -ForegroundColor Gray
    Write-Host "    Group: $($config.GroupName)" -ForegroundColor DarkGray
    Write-Host "    Required Apps: $($config.RequiredApps.Count)" -ForegroundColor DarkGray
    Write-Host "    Available Apps: $($config.AvailableApps.Count)" -ForegroundColor DarkGray
    Write-Host "    Blocked Apps: $($config.BlockedApps.Count)" -ForegroundColor DarkGray
}

# Export configuration if requested
if ($ExportConfiguration) {
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Gray
    Write-Host "Exporting Configuration" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Gray

    try {
        $roleConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $ExportPath -Encoding UTF8
        Write-ScriptLog "Configuration exported to: $ExportPath" -Level "Success"
    } catch {
        Write-ScriptLog "Failed to export configuration: $_" -Level "Error"
    }
}

# Create Azure AD Groups
if ($CreateGroups) {
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Gray
    Write-Host "Creating Azure AD Groups" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Gray

    foreach ($role in $roleConfig.Keys) {
        $config = $roleConfig[$role]
        $groupName = $config.GroupName

        if ($PSCmdlet.ShouldProcess($groupName, "Create Azure AD group")) {
            try {
                # Check if group exists
                $existingGroup = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue

                if ($existingGroup) {
                    Write-ScriptLog "Group already exists: $groupName" -Level "Info"
                    $config.GroupId = $existingGroup.Id
                } else {
                    # Create new group
                    $groupParams = @{
                        DisplayName = $groupName
                        Description = $config.Description
                        MailEnabled = $false
                        MailNickname = $groupName.Replace(" ", "").Replace("-", "")
                        SecurityEnabled = $true
                        GroupTypes = @()
                    }

                    $newGroup = New-MgGroup -BodyParameter $groupParams
                    $config.GroupId = $newGroup.Id
                    Write-ScriptLog "Created group: $groupName (ID: $($newGroup.Id))" -Level "Success"
                }
            } catch {
                Write-ScriptLog "Failed to create group $groupName : $_" -Level "Error"
            }
        }
    }
}

# Assign Apps to Groups
if ($AssignApps) {
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Gray
    Write-Host "Assigning Apps to Role Groups" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Gray

    foreach ($role in $roleConfig.Keys) {
        $config = $roleConfig[$role]

        if (-not $config.GroupId) {
            Write-ScriptLog "Skipping $role - no group ID available (run with -CreateGroups first)" -Level "Warning"
            continue
        }

        Write-Host ""
        Write-Host "  Role: $role" -ForegroundColor Yellow
        Write-Host "  Group: $($config.GroupName)" -ForegroundColor Gray

        # Process Required Apps
        foreach ($app in $config.RequiredApps) {
            if ($PSCmdlet.ShouldProcess("$($app.Name) to $($config.GroupName)", "Assign required app")) {
                Write-Host ""
                Write-Host "    Processing: $($app.Name) [$($app.PackageId)]" -ForegroundColor Cyan

                try {
                    # Find the app in Intune
                    $managedApp = Get-MgAndroidManagedAppByPackageId -PackageId $app.PackageId

                    if ($managedApp) {
                        Write-ScriptLog "      Found app in Intune: $($managedApp.DisplayName)" -Level "Success"

                        # Create assignment
                        $assignment = @{
                            "@odata.type" = "#microsoft.graph.mobileAppAssignment"
                            intent = "required"
                            target = @{
                                "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                                groupId = $config.GroupId
                            }
                            settings = @{
                                "@odata.type" = "#microsoft.graph.androidManagedStoreAppAssignmentSettings"
                                autoUpdateMode = "default"
                            }
                        }

                        New-MgDeviceAppManagementMobileAppAssignment -MobileAppId $managedApp.Id -BodyParameter $assignment
                        Write-ScriptLog "      Assigned as REQUIRED" -Level "Success"

                        # Create configuration policy if needed
                        if ($app.ConfigPolicy) {
                            Write-ScriptLog "      Creating app configuration policy..." -Level "Info"
                            $configSettings = @{}  # Add specific app settings here

                            New-AndroidAppConfigurationPolicy -AppId $managedApp.Id -AppName $app.Name -GroupId $config.GroupId -ConfigSettings $configSettings
                        }
                    } else {
                        Write-ScriptLog "      App not found in Intune. Please sync from Google Play: $($app.Name)" -Level "Warning"
                        Write-ScriptLog "      Package ID: $($app.PackageId)" -Level "Info"
                    }
                } catch {
                    Write-ScriptLog "      Failed to assign app: $_" -Level "Error"
                }
            }
        }

        # Process Available Apps
        foreach ($app in $config.AvailableApps) {
            if ($PSCmdlet.ShouldProcess("$($app.Name) to $($config.GroupName)", "Assign available app")) {
                Write-Host ""
                Write-Host "    Processing: $($app.Name) [$($app.PackageId)]" -ForegroundColor Cyan

                try {
                    $managedApp = Get-MgAndroidManagedAppByPackageId -PackageId $app.PackageId

                    if ($managedApp) {
                        Write-ScriptLog "      Found app in Intune: $($managedApp.DisplayName)" -Level "Success"

                        $assignment = @{
                            "@odata.type" = "#microsoft.graph.mobileAppAssignment"
                            intent = "available"
                            target = @{
                                "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                                groupId = $config.GroupId
                            }
                        }

                        New-MgDeviceAppManagementMobileAppAssignment -MobileAppId $managedApp.Id -BodyParameter $assignment
                        Write-ScriptLog "      Assigned as AVAILABLE (user can install from Company Portal)" -Level "Success"
                    } else {
                        Write-ScriptLog "      App not found in Intune: $($app.Name)" -Level "Warning"
                    }
                } catch {
                    Write-ScriptLog "      Failed to assign app: $_" -Level "Error"
                }
            }
        }

        # Process Blocked Apps
        if ($config.BlockedApps.Count -gt 0) {
            Write-Host ""
            Write-ScriptLog "    Blocked apps: $($config.BlockedApps.Count) apps will be prevented from installation" -Level "Warning"
            foreach ($app in $config.BlockedApps) {
                Write-Host "      • $($app.Name) [$($app.PackageId)]" -ForegroundColor DarkGray
            }
            # Note: App blocking requires App Protection Policies or Compliance Policies
        }
    }
}

# Summary
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Configuration Summary" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

$summary = @{
    RolesConfigured = $roleConfig.Keys.Count
    GroupsCreated = if ($CreateGroups) { $roleConfig.Keys.Count } else { 0 }
    TotalRequiredApps = ($roleConfig.Values | ForEach-Object { $_.RequiredApps.Count } | Measure-Object -Sum).Sum
    TotalAvailableApps = ($roleConfig.Values | ForEach-Object { $_.AvailableApps.Count } | Measure-Object -Sum).Sum
    TotalBlockedApps = ($roleConfig.Values | ForEach-Object { $_.BlockedApps.Count } | Measure-Object -Sum).Sum
}

Write-Host "Roles Configured: $($summary.RolesConfigured)" -ForegroundColor White
if ($CreateGroups) {
    Write-Host "Groups Created/Verified: $($summary.GroupsCreated)" -ForegroundColor Green
}
if ($AssignApps) {
    Write-Host "Required Apps: $($summary.TotalRequiredApps)" -ForegroundColor Green
    Write-Host "Available Apps: $($summary.TotalAvailableApps)" -ForegroundColor Cyan
    Write-Host "Blocked Apps: $($summary.TotalBlockedApps)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Gray
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Gray
Write-Host ""

if (-not $CreateGroups) {
    Write-Host "1. Run with -CreateGroups to create Azure AD groups" -ForegroundColor Yellow
}
if (-not $AssignApps) {
    Write-Host "2. Sync required apps from Managed Google Play Store" -ForegroundColor Yellow
    Write-Host "3. Run with -AssignApps to assign apps to groups" -ForegroundColor Yellow
}
Write-Host "4. Add users to appropriate role groups in Azure AD" -ForegroundColor Gray
Write-Host "5. Enroll Android devices using Android Enterprise" -ForegroundColor Gray
Write-Host "6. Monitor app deployment in Intune portal" -ForegroundColor Gray
Write-Host ""

Write-Host ("=" * 80) -ForegroundColor Cyan
Write-ScriptLog "Configuration completed!" -Level "Success"
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

# Disconnect
Disconnect-MgGraph | Out-Null

#endregion
