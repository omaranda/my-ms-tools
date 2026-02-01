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
#>
<#
.SYNOPSIS
    Reactivate Microsoft 365 user accounts with full license, group, and service restoration.

.DESCRIPTION
    This script reverses the offboarding/removal process by restoring user accounts
    to a fully functional state. It handles two scenarios:

    1. Blocked accounts (disabled but still exist):
       - Re-enables sign-in
       - Reassigns licenses
       - Re-adds to groups
       - Verifies service provisioning

    2. Soft-deleted accounts (in Azure AD recycle bin, up to 30 days):
       - Restores from recycle bin
       - Re-enables sign-in
       - Reassigns licenses
       - Re-adds to groups
       - Verifies service provisioning

    After license assignment, M365 automatically provisions:
       - Exchange Online mailbox
       - OneDrive storage
       - Teams access
       - SharePoint access
       - All services included in the assigned license

    Use cases:
    - Rehiring a former employee
    - Reversing an accidental offboarding
    - Reactivating accounts after a leave of absence
    - Restoring accounts from the Azure AD recycle bin

.PARAMETER UserEmail
    Email address or UPN of the user to reactivate

.PARAMETER UserEmails
    Array of email addresses to reactivate multiple users

.PARAMETER FromCSV
    Path to CSV file with users to reactivate (columns: Email, LicenseSKU, Groups)

.PARAMETER LicenseSKU
    License SKU to assign (e.g., SPE_E3, SPE_E5, O365_BUSINESS_PREMIUM).
    If omitted, shows interactive license picker.

.PARAMETER Groups
    Array of group display names or IDs to add the user to

.PARAMETER Department
    Auto-assign department-based groups using standard mapping

.PARAMETER ResetPassword
    Generate and set a new temporary password (user must change on first login)

.PARAMETER RestoreFromRecycleBin
    Search for and restore user from Azure AD recycle bin before reactivation

.PARAMETER ListDeletedUsers
    List all soft-deleted users available for restoration (read-only)

.PARAMETER ExportPath
    Export reactivation results to CSV file

.PARAMETER Force
    Skip confirmation prompts

.PARAMETER WhatIf
    Preview changes without applying

.EXAMPLE
    .\Restore-M365User.ps1 -ListDeletedUsers

    List all soft-deleted users in the Azure AD recycle bin

.EXAMPLE
    .\Restore-M365User.ps1 -UserEmail "john@contoso.com" -LicenseSKU "SPE_E3"

    Reactivate a disabled account and assign an E3 license

.EXAMPLE
    .\Restore-M365User.ps1 -UserEmail "john@contoso.com" -RestoreFromRecycleBin -LicenseSKU "SPE_E3"

    Restore a deleted user from the recycle bin and assign an E3 license

.EXAMPLE
    .\Restore-M365User.ps1 -UserEmail "john@contoso.com" -LicenseSKU "SPE_E3" -Department "IT"

    Reactivate user, assign E3 license, and add to IT department groups

.EXAMPLE
    .\Restore-M365User.ps1 -UserEmail "john@contoso.com" -LicenseSKU "SPE_E3" -Groups "Sales-Team","VPN-Users"

    Reactivate user, assign E3 license, and add to specific groups

.EXAMPLE
    .\Restore-M365User.ps1 -UserEmail "john@contoso.com" -LicenseSKU "SPE_E3" -ResetPassword

    Reactivate user with a new temporary password

.EXAMPLE
    .\Restore-M365User.ps1 -FromCSV "users-to-restore.csv"

    Bulk reactivate users from CSV file

.EXAMPLE
    .\Restore-M365User.ps1 -UserEmail "john@contoso.com" -LicenseSKU "SPE_E3" -WhatIf

    Preview what would happen without making changes
#>

[CmdletBinding(SupportsShouldProcess=$true, DefaultParameterSetName='Single')]
param(
    [Parameter(ParameterSetName='Single', Mandatory=$true)]
    [string]$UserEmail,

    [Parameter(ParameterSetName='Multiple', Mandatory=$true)]
    [string[]]$UserEmails,

    [Parameter(ParameterSetName='CSV', Mandatory=$true)]
    [string]$FromCSV,

    [Parameter(ParameterSetName='ListDeleted')]
    [switch]$ListDeletedUsers,

    [Parameter(Mandatory=$false)]
    [string]$LicenseSKU,

    [Parameter(Mandatory=$false)]
    [string[]]$Groups,

    [Parameter(Mandatory=$false)]
    [string]$Department,

    [Parameter(Mandatory=$false)]
    [switch]$ResetPassword,

    [Parameter(Mandatory=$false)]
    [switch]$RestoreFromRecycleBin,

    [Parameter(Mandatory=$false)]
    [string]$ExportPath,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

#region Helper Functions

function Write-RestoreLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error", "Action", "Step")]
        [string]$Level = "Info"
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error"   { "Red" }
        "Action"  { "Magenta" }
        "Step"    { "White" }
        default   { "Cyan" }
    }

    $icon = switch ($Level) {
        "Success" { [char]0x2713 }
        "Warning" { [char]0x26A0 }
        "Error"   { [char]0x2717 }
        "Action"  { [char]0x2192 }
        "Step"    { [char]0x25CB }
        default   { [char]0x2139 }
    }

    Write-Host "[$timestamp] $icon $Message" -ForegroundColor $color
}

function Get-LicenseFriendlyName {
    param([string]$SkuPartNumber)

    $friendlyNames = @{
        "O365_BUSINESS_PREMIUM"    = "Microsoft 365 Business Premium"
        "O365_BUSINESS_ESSENTIALS" = "Microsoft 365 Business Basic"
        "O365_BUSINESS"            = "Microsoft 365 Apps for Business"
        "SMB_BUSINESS_PREMIUM"     = "Microsoft 365 Business Premium"
        "SMB_BUSINESS_ESSENTIALS"  = "Microsoft 365 Business Basic"
        "SPE_E3"                   = "Microsoft 365 E3"
        "SPE_E5"                   = "Microsoft 365 E5"
        "ENTERPRISEPACK"           = "Office 365 E3"
        "ENTERPRISEPREMIUM"        = "Office 365 E5"
        "EXCHANGESTANDARD"         = "Exchange Online Plan 1"
        "EXCHANGEENTERPRISE"       = "Exchange Online Plan 2"
        "POWER_BI_PRO"             = "Power BI Pro"
        "POWER_BI_STANDARD"        = "Power BI Free"
        "PROJECTPROFESSIONAL"      = "Project Plan 3"
        "VISIOCLIENT"              = "Visio Plan 2"
        "FLOW_FREE"                = "Power Automate Free"
        "TEAMS_EXPLORATORY"        = "Teams Exploratory"
        "STREAM"                   = "Microsoft Stream"
        "AAD_PREMIUM"              = "Azure AD Premium P1"
        "AAD_PREMIUM_P2"           = "Azure AD Premium P2"
        "EMS"                      = "Enterprise Mobility + Security E3"
        "EMSPREMIUM"               = "Enterprise Mobility + Security E5"
        "INTUNE_A"                 = "Intune"
        "ATP_ENTERPRISE"           = "Microsoft Defender for Office 365 P1"
        "THREAT_INTELLIGENCE"      = "Microsoft Defender for Office 365 P2"
        "STANDARDPACK"             = "Office 365 E1"
    }

    if ($friendlyNames.ContainsKey($SkuPartNumber)) {
        return $friendlyNames[$SkuPartNumber]
    }
    return $SkuPartNumber
}

function Get-DepartmentGroups {
    param([string]$DepartmentName)

    $departmentGroups = @{
        "IT"          = @("IT-Team", "VPN-Users", "Remote-Desktop-Users")
        "Sales"       = @("Sales-Team", "CRM-Users")
        "Marketing"   = @("Marketing-Team", "Design-Tools-Users")
        "Finance"     = @("Finance-Team", "Accounting-Software-Users")
        "HR"          = @("HR-Team", "HRIS-Users")
        "Operations"  = @("Operations-Team")
        "Engineering" = @("Engineering-Team", "Dev-Tools-Users")
        "Support"     = @("Support-Team", "Ticketing-Users")
        "Management"  = @("Management-Team")
    }

    if ($departmentGroups.ContainsKey($DepartmentName)) {
        return $departmentGroups[$DepartmentName]
    }
    return @()
}

function New-TemporaryPassword {
    $upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    $lower = "abcdefghjkmnpqrstuvwxyz"
    $digits = "23456789"
    $special = "!@#$%&*?"

    $password = ""
    $password += $upper[(Get-Random -Maximum $upper.Length)]
    $password += $upper[(Get-Random -Maximum $upper.Length)]
    $password += $lower[(Get-Random -Maximum $lower.Length)]
    $password += $lower[(Get-Random -Maximum $lower.Length)]
    $password += $lower[(Get-Random -Maximum $lower.Length)]
    $password += $lower[(Get-Random -Maximum $lower.Length)]
    $password += $digits[(Get-Random -Maximum $digits.Length)]
    $password += $digits[(Get-Random -Maximum $digits.Length)]
    $password += $special[(Get-Random -Maximum $special.Length)]

    # Shuffle
    $chars = $password.ToCharArray()
    $shuffled = $chars | Get-Random -Count $chars.Length
    return -join $shuffled
}

function Show-LicensePicker {
    param([array]$Skus)

    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host "  Available Licenses" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""

    $availableSkus = $Skus | Where-Object {
        ($_.PrepaidUnits.Enabled - $_.ConsumedUnits) -gt 0
    } | Sort-Object SkuPartNumber

    if ($availableSkus.Count -eq 0) {
        Write-RestoreLog "No licenses with available units found" -Level "Warning"
        return $null
    }

    $index = 1
    foreach ($sku in $availableSkus) {
        $available = $sku.PrepaidUnits.Enabled - $sku.ConsumedUnits
        $friendlyName = Get-LicenseFriendlyName -SkuPartNumber $sku.SkuPartNumber
        $color = if ($available -gt 5) { "Green" } elseif ($available -gt 0) { "Yellow" } else { "Red" }

        Write-Host ("  [{0,2}] {1,-40} Available: {2,3}/{3,-3}  ({4})" -f `
            $index, $friendlyName, $available, $sku.PrepaidUnits.Enabled, $sku.SkuPartNumber) -ForegroundColor $color
        $index++
    }

    Write-Host ""
    Write-Host "  Enter number to select license, or 'q' to skip:" -ForegroundColor DarkGray
    $selection = Read-Host "  Selection"

    if ($selection -eq 'q' -or $selection -eq 'Q') {
        return $null
    }

    $num = 0
    if ([int]::TryParse($selection, [ref]$num) -and $num -ge 1 -and $num -le $availableSkus.Count) {
        return $availableSkus[$num - 1]
    }

    Write-RestoreLog "Invalid selection" -Level "Warning"
    return $null
}

function Restore-UserAccount {
    param(
        [string]$Email,
        [string]$LicenseSkuPartNumber,
        [array]$Skus,
        [string[]]$GroupNames,
        [bool]$ShouldResetPassword,
        [bool]$ShouldRestoreFromBin,
        [bool]$IsBlockOnly,
        [bool]$IsWhatIf
    )

    $result = [PSCustomObject]@{
        Email           = $Email
        DisplayName     = ""
        Steps           = @()
        Success         = $true
        Error           = $null
        NewPassword     = $null
        LicenseAssigned = ""
        GroupsAdded     = @()
        RestoredFromBin = $false
    }

    Write-Host ""
    Write-Host ("  " + "-" * 70) -ForegroundColor Gray
    Write-Host "  Reactivating: $Email" -ForegroundColor Yellow
    Write-Host ("  " + "-" * 70) -ForegroundColor Gray

    $user = $null

    try {
        # Step 1: Find or restore the user
        if ($ShouldRestoreFromBin) {
            Write-RestoreLog "    Step 1: Searching recycle bin..." -Level "Step"

            if (-not $IsWhatIf) {
                $deletedUsers = Get-MgDirectoryDeletedItemAsUser -All `
                    -Property Id, DisplayName, UserPrincipalName, Mail, DeletedDateTime `
                    -ErrorAction SilentlyContinue

                $deletedUser = $deletedUsers | Where-Object {
                    $_.UserPrincipalName -eq $Email -or $_.Mail -eq $Email
                } | Select-Object -First 1

                if ($deletedUser) {
                    Write-RestoreLog "    Found in recycle bin: $($deletedUser.DisplayName) (deleted: $($deletedUser.DeletedDateTime.ToString('yyyy-MM-dd')))" -Level "Info"
                    Write-RestoreLog "    Restoring from recycle bin..." -Level "Action"

                    Restore-MgDirectoryDeletedItem -DirectoryObjectId $deletedUser.Id -ErrorAction Stop

                    $result.RestoredFromBin = $true
                    $result.Steps += "Restored from recycle bin"
                    Write-RestoreLog "    User restored from recycle bin" -Level "Success"

                    # Wait for restoration to propagate
                    Write-RestoreLog "    Waiting for restoration to propagate..." -Level "Info"
                    Start-Sleep -Seconds 5

                    # Fetch the restored user
                    $user = Get-MgUser -Filter "userPrincipalName eq '$Email'" `
                        -Property Id, DisplayName, UserPrincipalName, Mail, AccountEnabled, `
                                  AssignedLicenses, Department, JobTitle `
                        -ErrorAction Stop
                } else {
                    Write-RestoreLog "    User not found in recycle bin, searching active directory..." -Level "Warning"
                }
            } else {
                $result.Steps += "Would restore from recycle bin"
                Write-RestoreLog "    [WhatIf] Would search and restore from recycle bin" -Level "Success"
            }
        }

        # If not found in recycle bin (or not restoring from bin), search active users
        if (-not $user) {
            Write-RestoreLog "    Step 1: Finding user account..." -Level "Step"

            if (-not $IsWhatIf) {
                $user = Get-MgUser -Filter "userPrincipalName eq '$Email'" `
                    -Property Id, DisplayName, UserPrincipalName, Mail, AccountEnabled, `
                              AssignedLicenses, Department, JobTitle `
                    -ErrorAction Stop

                if (-not $user) {
                    # Try by mail
                    $user = Get-MgUser -Filter "mail eq '$Email'" `
                        -Property Id, DisplayName, UserPrincipalName, Mail, AccountEnabled, `
                                  AssignedLicenses, Department, JobTitle `
                        -ErrorAction Stop
                }

                if (-not $user) {
                    throw "User not found: $Email"
                }
            } else {
                $result.Steps += "Would find user"
                Write-RestoreLog "    [WhatIf] Would find user: $Email" -Level "Success"
            }
        }

        if ($user) {
            $result.DisplayName = $user.DisplayName
            Write-RestoreLog "    Found: $($user.DisplayName)" -Level "Success"
        }

        # Step 2: Re-enable account
        Write-RestoreLog "    Step 2: Enabling sign-in..." -Level "Step"
        if (-not $IsWhatIf) {
            if (-not $user.AccountEnabled) {
                Update-MgUser -UserId $user.Id -AccountEnabled:$true -ErrorAction Stop
                $result.Steps += "Sign-in enabled"
                Write-RestoreLog "    Sign-in enabled" -Level "Success"
            } else {
                Write-RestoreLog "    Account already enabled" -Level "Info"
                $result.Steps += "Account already enabled"
            }
        } else {
            $result.Steps += "Would enable sign-in"
            Write-RestoreLog "    [WhatIf] Would enable sign-in" -Level "Success"
        }

        # Step 3: Reset password if requested
        if ($ShouldResetPassword) {
            Write-RestoreLog "    Step 3: Resetting password..." -Level "Step"
            $newPassword = New-TemporaryPassword

            if (-not $IsWhatIf) {
                $passwordProfile = @{
                    Password                      = $newPassword
                    ForceChangePasswordNextSignIn  = $true
                }
                Update-MgUser -UserId $user.Id -PasswordProfile $passwordProfile -ErrorAction Stop
                $result.NewPassword = $newPassword
                $result.Steps += "Password reset (temp)"
                Write-RestoreLog "    Temporary password set (user must change on first login)" -Level "Success"
            } else {
                $result.Steps += "Would reset password"
                Write-RestoreLog "    [WhatIf] Would set temporary password" -Level "Success"
            }
        }

        # Step 4: Assign license
        Write-RestoreLog "    Step 4: License assignment..." -Level "Step"

        $targetSku = $null
        if ($LicenseSkuPartNumber) {
            $targetSku = $Skus | Where-Object { $_.SkuPartNumber -eq $LicenseSkuPartNumber }
            if (-not $targetSku) {
                Write-RestoreLog "    License SKU not found: $LicenseSkuPartNumber" -Level "Error"
                Write-RestoreLog "    Skipping license assignment" -Level "Warning"
            }
        }

        if ($targetSku) {
            $available = $targetSku.PrepaidUnits.Enabled - $targetSku.ConsumedUnits
            $friendlyName = Get-LicenseFriendlyName -SkuPartNumber $targetSku.SkuPartNumber

            if ($available -le 0) {
                Write-RestoreLog "    No available units for $friendlyName" -Level "Error"
                $result.Steps += "License unavailable: $friendlyName"
            } else {
                # Check if user already has this license
                $alreadyHas = $false
                if (-not $IsWhatIf -and $user.AssignedLicenses) {
                    $alreadyHas = $user.AssignedLicenses | Where-Object { $_.SkuId -eq $targetSku.SkuId }
                }

                if ($alreadyHas) {
                    Write-RestoreLog "    User already has $friendlyName" -Level "Info"
                    $result.Steps += "License already assigned: $friendlyName"
                    $result.LicenseAssigned = $friendlyName
                } else {
                    if (-not $IsWhatIf) {
                        Set-MgUserLicense -UserId $user.Id `
                            -AddLicenses @(@{SkuId = $targetSku.SkuId}) `
                            -RemoveLicenses @() `
                            -ErrorAction Stop
                        $result.Steps += "License assigned: $friendlyName"
                        $result.LicenseAssigned = $friendlyName
                        Write-RestoreLog "    Assigned: $friendlyName ($($targetSku.SkuPartNumber))" -Level "Success"
                    } else {
                        $result.Steps += "Would assign: $friendlyName"
                        $result.LicenseAssigned = $friendlyName
                        Write-RestoreLog "    [WhatIf] Would assign: $friendlyName" -Level "Success"
                    }
                }
            }
        } else {
            if (-not $LicenseSkuPartNumber) {
                Write-RestoreLog "    No license specified (use -LicenseSKU to assign)" -Level "Warning"
                $result.Steps += "No license specified"
            }
        }

        # Step 5: Add to groups
        Write-RestoreLog "    Step 5: Group membership..." -Level "Step"

        $groupsToAdd = @()
        if ($GroupNames -and $GroupNames.Count -gt 0) {
            $groupsToAdd += $GroupNames
        }

        # Add department-based groups
        $deptName = $Department
        if (-not $deptName -and $user -and $user.Department) {
            $deptName = $user.Department
        }
        if ($deptName) {
            $deptGroups = Get-DepartmentGroups -DepartmentName $deptName
            if ($deptGroups.Count -gt 0) {
                Write-RestoreLog "    Department '$deptName' groups: $($deptGroups -join ', ')" -Level "Info"
                $groupsToAdd += $deptGroups
            }
        }

        # Remove duplicates
        $groupsToAdd = $groupsToAdd | Select-Object -Unique

        if ($groupsToAdd.Count -eq 0) {
            Write-RestoreLog "    No groups to add (use -Groups or -Department)" -Level "Info"
            $result.Steps += "No groups specified"
        } else {
            $addedCount = 0
            $skippedCount = 0

            foreach ($groupName in $groupsToAdd) {
                if (-not $IsWhatIf) {
                    try {
                        # Find group by display name
                        $group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue | Select-Object -First 1

                        if (-not $group) {
                            Write-RestoreLog "    Group not found: $groupName" -Level "Warning"
                            $skippedCount++
                            continue
                        }

                        # Check if already a member
                        $members = Get-MgGroupMember -GroupId $group.Id -All
                        $isMember = $members | Where-Object { $_.Id -eq $user.Id }

                        if ($isMember) {
                            Write-RestoreLog "    Already member of: $groupName" -Level "Info"
                            $skippedCount++
                        } else {
                            $params = @{
                                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
                            }
                            New-MgGroupMemberByRef -GroupId $group.Id -BodyParameter $params -ErrorAction Stop
                            Write-RestoreLog "    Added to: $groupName" -Level "Success"
                            $result.GroupsAdded += $groupName
                            $addedCount++
                        }
                    } catch {
                        Write-RestoreLog "    Failed to add to $groupName : $($_.Exception.Message)" -Level "Warning"
                        $skippedCount++
                    }
                } else {
                    Write-RestoreLog "    [WhatIf] Would add to: $groupName" -Level "Success"
                    $result.GroupsAdded += $groupName
                    $addedCount++
                }
            }

            $result.Steps += "Groups added: $addedCount, skipped: $skippedCount"
        }

        # Step 6: Update department if specified
        if ($Department -and -not $IsWhatIf -and $user) {
            if ($user.Department -ne $Department) {
                Write-RestoreLog "    Step 6: Updating department to '$Department'..." -Level "Step"
                Update-MgUser -UserId $user.Id -Department $Department -ErrorAction SilentlyContinue
                $result.Steps += "Department set: $Department"
                Write-RestoreLog "    Department updated" -Level "Success"
            }
        }

        # Step 7: Verify services
        Write-RestoreLog "    Step 7: Service verification..." -Level "Step"

        if (-not $IsWhatIf -and $user) {
            # Re-fetch user to get updated state
            Start-Sleep -Seconds 2
            $updatedUser = Get-MgUser -UserId $user.Id `
                -Property Id, DisplayName, AccountEnabled, AssignedLicenses, `
                          AssignedPlans, ProvisionedPlans `
                -ErrorAction SilentlyContinue

            if ($updatedUser) {
                # Account status
                $accountStatus = if ($updatedUser.AccountEnabled) { "Enabled" } else { "Disabled" }
                $accountColor = if ($updatedUser.AccountEnabled) { "Green" } else { "Red" }
                Write-Host "      Account:  $accountStatus" -ForegroundColor $accountColor

                # License count
                $licCount = if ($updatedUser.AssignedLicenses) { $updatedUser.AssignedLicenses.Count } else { 0 }
                $licColor = if ($licCount -gt 0) { "Green" } else { "Yellow" }
                Write-Host "      Licenses: $licCount assigned" -ForegroundColor $licColor

                # Provisioned services
                if ($updatedUser.ProvisionedPlans -and $updatedUser.ProvisionedPlans.Count -gt 0) {
                    $services = $updatedUser.ProvisionedPlans |
                        Where-Object { $_.ProvisioningStatus -eq "Success" } |
                        Select-Object -ExpandProperty Service -Unique |
                        Sort-Object

                    if ($services.Count -gt 0) {
                        Write-Host "      Services provisioned:" -ForegroundColor Green
                        foreach ($svc in $services) {
                            $svcFriendly = switch -Wildcard ($svc) {
                                "exchange"           { "Exchange Online (Email)" }
                                "SharePoint"         { "SharePoint Online" }
                                "MicrosoftOffice"    { "Microsoft Office Apps" }
                                "microsoftcomm*"     { "Microsoft Teams" }
                                "Sway"               { "Sway" }
                                "YammerEnterprise"   { "Yammer" }
                                "MicrosoftStream"    { "Microsoft Stream" }
                                "PowerBI*"           { "Power BI" }
                                "To-Do"              { "Microsoft To-Do" }
                                "Deskless"           { "Microsoft StaffHub" }
                                "WindowsDefenderATP" { "Microsoft Defender" }
                                "AADPremiumService"  { "Azure AD Premium" }
                                "RMSOnline"          { "Azure Information Protection" }
                                "SCO"                { "Azure AD Premium" }
                                "OfficeForms"        { "Microsoft Forms" }
                                "ProjectWorkManagement" { "Microsoft Planner" }
                                default              { $svc }
                            }
                            Write-Host "        [char]0x2713 $svcFriendly" -ForegroundColor DarkGreen
                        }
                    }
                } else {
                    Write-Host "      Services: Provisioning in progress (may take a few minutes)" -ForegroundColor Yellow
                }

                $result.Steps += "Verification complete"
                Write-RestoreLog "    Verification complete" -Level "Success"
            }
        } else {
            $result.Steps += "Would verify services"
            Write-RestoreLog "    [WhatIf] Would verify service provisioning" -Level "Success"
        }

    } catch {
        $result.Success = $false
        $result.Error = $_.Exception.Message
        Write-RestoreLog "    Error: $_" -Level "Error"
    }

    return $result
}

#endregion

#region Main Script

Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Microsoft 365 User Reactivation Tool" -ForegroundColor Cyan
Write-Host "Restore accounts, licenses, groups, and services" -ForegroundColor Gray
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

# Check for required modules
$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.Identity.DirectoryManagement'
)

Write-RestoreLog "Checking required modules..." -Level "Info"
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-RestoreLog "Required module not found: $module" -Level "Warning"
        Write-Host ""
        Write-Host "To install required modules, run:" -ForegroundColor Yellow
        Write-Host "  Install-Module Microsoft.Graph -Scope CurrentUser -Force" -ForegroundColor White
        exit 1
    }
}

# Import modules
Write-RestoreLog "Importing Microsoft Graph modules..." -Level "Info"
try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.Users -ErrorAction Stop
    Import-Module Microsoft.Graph.Groups -ErrorAction Stop
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
    Write-RestoreLog "Modules imported successfully" -Level "Success"
} catch {
    Write-RestoreLog "Failed to import modules: $_" -Level "Error"
    exit 1
}

# Connect to Microsoft Graph
Write-Host ""
Write-RestoreLog "Connecting to Microsoft Graph..." -Level "Info"
$scopes = @(
    "User.ReadWrite.All",
    "Directory.ReadWrite.All",
    "Group.ReadWrite.All",
    "Organization.Read.All"
)

try {
    Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop
    Write-RestoreLog "Successfully connected to Microsoft Graph" -Level "Success"
} catch {
    Write-RestoreLog "Failed to connect to Microsoft Graph: $_" -Level "Error"
    exit 1
}

# Get license information
Write-RestoreLog "Retrieving license information..." -Level "Info"
try {
    $subscribedSkus = Get-MgSubscribedSku -All
    Write-RestoreLog "Found $($subscribedSkus.Count) license types" -Level "Success"
} catch {
    Write-RestoreLog "Failed to retrieve licenses: $_" -Level "Error"
    Disconnect-MgGraph | Out-Null
    exit 1
}

# Handle ListDeletedUsers mode
if ($ListDeletedUsers) {
    Write-Host ""
    Write-Host ("=" * 100) -ForegroundColor Cyan
    Write-Host "  Soft-Deleted Users (Azure AD Recycle Bin)" -ForegroundColor Cyan
    Write-Host ("=" * 100) -ForegroundColor Cyan
    Write-Host ""

    try {
        $deletedUsers = Get-MgDirectoryDeletedItemAsUser -All `
            -Property Id, DisplayName, UserPrincipalName, Mail, DeletedDateTime, `
                      Department, JobTitle `
            -ErrorAction Stop

        if ($deletedUsers.Count -eq 0) {
            Write-RestoreLog "No deleted users found in recycle bin" -Level "Info"
        } else {
            Write-Host ("  {0,-30}{1,-35}{2,-15}{3,-20}" -f "Name", "Email", "Department", "Deleted On") -ForegroundColor DarkGray
            Write-Host ("  " + "-" * 96) -ForegroundColor DarkGray

            foreach ($du in ($deletedUsers | Sort-Object DeletedDateTime -Descending)) {
                $deletedDate = if ($du.DeletedDateTime) { $du.DeletedDateTime.ToString("yyyy-MM-dd HH:mm") } else { "Unknown" }
                $deptDisplay = if ($du.Department) { $du.Department } else { "-" }
                $nameDisplay = $du.DisplayName
                if ($nameDisplay.Length -gt 28) { $nameDisplay = $nameDisplay.Substring(0, 28) + ".." }
                $emailDisplay = if ($du.Mail) { $du.Mail } else { $du.UserPrincipalName }
                if ($emailDisplay.Length -gt 33) { $emailDisplay = $emailDisplay.Substring(0, 33) + ".." }

                Write-Host ("  {0,-30}{1,-35}{2,-15}{3,-20}" -f $nameDisplay, $emailDisplay, $deptDisplay, $deletedDate) -ForegroundColor Gray
            }

            Write-Host ""
            Write-RestoreLog "$($deletedUsers.Count) deleted user(s) found (recoverable within 30 days)" -Level "Info"
        }

        if ($ExportPath) {
            $deletedUsers | Select-Object DisplayName, UserPrincipalName, Mail, Department, JobTitle, DeletedDateTime |
                Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
            Write-RestoreLog "Exported to $ExportPath" -Level "Success"
        }

    } catch {
        Write-RestoreLog "Failed to retrieve deleted users: $_" -Level "Error"
    }

    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host "  Tip: Use -RestoreFromRecycleBin -UserEmail 'user@domain.com' to restore" -ForegroundColor DarkGray
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""

    Disconnect-MgGraph | Out-Null
    exit 0
}

# Build list of users to process
$usersToRestore = @()
$csvLicenseMap = @{}
$csvGroupMap = @{}

switch ($PSCmdlet.ParameterSetName) {
    'Single' {
        $usersToRestore = @($UserEmail)
    }
    'Multiple' {
        $usersToRestore = $UserEmails
    }
    'CSV' {
        if (-not (Test-Path $FromCSV)) {
            Write-RestoreLog "CSV file not found: $FromCSV" -Level "Error"
            Disconnect-MgGraph | Out-Null
            exit 1
        }

        $csvData = Import-Csv $FromCSV
        foreach ($row in $csvData) {
            $email = $row.Email
            if (-not $email) { $email = $row.UserPrincipalName }
            if (-not $email) { $email = $row.email }
            if (-not $email) { $email = $row.UPN }

            if ($email) {
                $usersToRestore += $email

                # Per-user license from CSV
                $csvLic = $row.LicenseSKU
                if (-not $csvLic) { $csvLic = $row.License }
                if ($csvLic) { $csvLicenseMap[$email] = $csvLic }

                # Per-user groups from CSV
                $csvGrp = $row.Groups
                if ($csvGrp) {
                    $csvGroupMap[$email] = ($csvGrp -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                }
            }
        }

        Write-RestoreLog "Found $($usersToRestore.Count) users in CSV" -Level "Info"
    }
}

if ($usersToRestore.Count -eq 0) {
    Write-RestoreLog "No users specified" -Level "Error"
    Disconnect-MgGraph | Out-Null
    exit 1
}

# If no license specified and not from CSV, show interactive picker
$selectedLicenseSKU = $LicenseSKU
if (-not $selectedLicenseSKU -and -not $FromCSV) {
    Write-Host ""
    Write-RestoreLog "No license specified. Select a license to assign:" -Level "Info"
    $pickedSku = Show-LicensePicker -Skus $subscribedSkus
    if ($pickedSku) {
        $selectedLicenseSKU = $pickedSku.SkuPartNumber
        Write-RestoreLog "Selected: $(Get-LicenseFriendlyName -SkuPartNumber $selectedLicenseSKU)" -Level "Success"
    } else {
        Write-RestoreLog "No license selected. Accounts will be reactivated without a license." -Level "Warning"
    }
}

# Show plan
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Gray
Write-Host "  Reactivation Plan" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Gray
Write-Host ""
Write-Host "  Users to reactivate: $($usersToRestore.Count)" -ForegroundColor White

foreach ($email in $usersToRestore) {
    $userLic = if ($csvLicenseMap.ContainsKey($email)) { $csvLicenseMap[$email] } else { $selectedLicenseSKU }
    $userGrp = if ($csvGroupMap.ContainsKey($email)) { $csvGroupMap[$email] -join ", " } elseif ($Groups) { $Groups -join ", " } else { "" }
    $licDisplay = if ($userLic) { Get-LicenseFriendlyName -SkuPartNumber $userLic } else { "(none)" }
    $grpDisplay = if ($userGrp) { $userGrp } else { "(none)" }

    Write-Host "    $([char]0x2022) $email" -ForegroundColor Yellow
    Write-Host "      License: $licDisplay  |  Groups: $grpDisplay" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Actions:" -ForegroundColor White
if ($RestoreFromRecycleBin) { Write-Host "    1. Restore from recycle bin (if deleted)" -ForegroundColor Gray }
Write-Host "    $(if ($RestoreFromRecycleBin) {'2'} else {'1'}). Enable sign-in" -ForegroundColor Gray
if ($ResetPassword) { Write-Host "    $(if ($RestoreFromRecycleBin) {'3'} else {'2'}). Reset password (temporary)" -ForegroundColor Gray }
Write-Host "    $(if ($RestoreFromRecycleBin) {'4'} else {'3'}). Assign license" -ForegroundColor Gray
Write-Host "    $(if ($RestoreFromRecycleBin) {'5'} else {'4'}). Add to groups" -ForegroundColor Gray
Write-Host "    $(if ($RestoreFromRecycleBin) {'6'} else {'5'}). Verify service provisioning" -ForegroundColor Gray
Write-Host ""

# Confirm
if (-not $Force -and -not $WhatIfPreference) {
    Write-Host "  This will REACTIVATE $($usersToRestore.Count) user account(s)" -ForegroundColor Green
    Write-Host ""
    $confirmation = Read-Host "  Type 'YES' to confirm"

    if ($confirmation -ne "YES") {
        Write-RestoreLog "Operation cancelled" -Level "Info"
        Disconnect-MgGraph | Out-Null
        exit 0
    }
}

# Process each user
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host "  Processing Users" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Green

$results = @()
$successCount = 0
$failCount = 0

foreach ($email in $usersToRestore) {
    # Determine license for this user
    $userLicSku = if ($csvLicenseMap.ContainsKey($email)) { $csvLicenseMap[$email] } else { $selectedLicenseSKU }

    # Determine groups for this user
    $userGroups = @()
    if ($csvGroupMap.ContainsKey($email)) {
        $userGroups = $csvGroupMap[$email]
    } elseif ($Groups) {
        $userGroups = $Groups
    }

    $result = Restore-UserAccount `
        -Email $email `
        -LicenseSkuPartNumber $userLicSku `
        -Skus $subscribedSkus `
        -GroupNames $userGroups `
        -ShouldResetPassword $ResetPassword `
        -ShouldRestoreFromBin $RestoreFromRecycleBin `
        -IsWhatIf $WhatIfPreference

    $results += $result

    if ($result.Success) {
        $successCount++
    } else {
        $failCount++
    }
}

# Save log
$logPath = "UserReactivation_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$logEntries = @()

foreach ($result in $results) {
    $logEntries += [PSCustomObject]@{
        Timestamp       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Email           = $result.Email
        DisplayName     = $result.DisplayName
        RestoredFromBin = $result.RestoredFromBin
        LicenseAssigned = $result.LicenseAssigned
        GroupsAdded     = ($result.GroupsAdded -join "; ")
        Steps           = ($result.Steps -join "; ")
        Success         = $result.Success
        Error           = $result.Error
        ReactivatedBy   = (Get-MgContext).Account
    }
}

$logEntries | Export-Csv -Path $logPath -NoTypeInformation -Encoding UTF8

# Final summary
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

if ($WhatIfPreference) {
    Write-Host "  [WHATIF MODE] No changes were made" -ForegroundColor Yellow
    Write-Host "  Would have processed: $($usersToRestore.Count) user(s)" -ForegroundColor Gray
} else {
    Write-Host "  Successfully reactivated: $successCount" -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host "  Failed: $failCount" -ForegroundColor Red
    }
}

# Show passwords if generated
$withPasswords = $results | Where-Object { $_.NewPassword }
if ($withPasswords.Count -gt 0) {
    Write-Host ""
    Write-Host "  Temporary Passwords (user must change on first login):" -ForegroundColor Yellow
    Write-Host "  " + ("-" * 60) -ForegroundColor Gray
    foreach ($r in $withPasswords) {
        Write-Host "    $($r.Email): $($r.NewPassword)" -ForegroundColor White
    }
    Write-Host "  " + ("-" * 60) -ForegroundColor Gray
    Write-Host "  IMPORTANT: Share these passwords securely and delete this output" -ForegroundColor Red
}

Write-Host ""
Write-Host "  Reactivation log: $logPath" -ForegroundColor Gray

if ($ExportPath) {
    $logEntries | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Host "  Export saved to: $ExportPath" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  Note: Email, Teams, OneDrive, and SharePoint access are provisioned" -ForegroundColor DarkGray
Write-Host "  automatically by Microsoft 365 after license assignment." -ForegroundColor DarkGray
Write-Host "  Full provisioning may take up to 24 hours." -ForegroundColor DarkGray
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-RestoreLog "Operation completed" -Level "Success"
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

# Disconnect
Disconnect-MgGraph | Out-Null

#endregion
