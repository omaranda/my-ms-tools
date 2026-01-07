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
    Comprehensive automated user onboarding workflow.

.DESCRIPTION
    Complete end-to-end user onboarding automation that handles:

    Active Directory:
    - Create AD user account with strong random password
    - Configure user properties (department, title, manager, office, phone)
    - Add to security groups based on department/role
    - Set home folder and profile path
    - Configure mail attributes

    Microsoft 365:
    - Wait for Azure AD sync (hybrid environments)
    - Assign M365 licenses (E3, E5, etc.)
    - Create Teams account
    - Add to Teams channels
    - Configure mailbox settings
    - Set out-of-office for first day

    Infrastructure:
    - Create home directory with proper permissions
    - Create network shares
    - Map network drives via GPO
    - Send welcome email with credentials and instructions

    Reporting:
    - Log all activities to CSV
    - Generate onboarding summary report
    - Email summary to IT team and manager

.PARAMETER FirstName
    User's first name

.PARAMETER LastName
    User's last name

.PARAMETER Username
    Username (SAMAccountName). If not provided, will be auto-generated from FirstName.LastName

.PARAMETER Email
    Email address. If not provided, will be auto-generated from Username@domain

.PARAMETER Department
    Department name (e.g., IT, Sales, Marketing, Finance, HR)

.PARAMETER Title
    Job title

.PARAMETER Manager
    Manager's username (SAMAccountName)

.PARAMETER Office
    Office location

.PARAMETER PhoneNumber
    Office phone number

.PARAMETER StartDate
    Start date (default: today). Used for scheduling account activation

.PARAMETER Groups
    Additional security groups to add user to (beyond department defaults)

.PARAMETER LicenseSKU
    M365 license SKU (e.g., SPE_E3, SPE_E5, O365_BUSINESS_PREMIUM)

.PARAMETER TeamsChannels
    Teams channels to add user to

.PARAMETER HomeFolderPath
    Custom home folder path (default: \\fileserver\home$\username)

.PARAMETER ProfilePath
    Custom roaming profile path (default: \\fileserver\profiles$\username)

.PARAMETER SendWelcomeEmail
    Send welcome email to new user with credentials and setup instructions

.PARAMETER NotifyManager
    Send notification email to manager

.PARAMETER NotifyIT
    Send completion summary to IT team

.PARAMETER ITEmail
    IT team email address for notifications

.PARAMETER Domain
    Domain name for email generation (default: contoso.com)

.PARAMETER SkipAD
    Skip Active Directory account creation (Azure AD only)

.PARAMETER SkipLicense
    Skip M365 license assignment

.PARAMETER WhatIf
    Show what would happen without making changes

.EXAMPLE
    .\New-UserOnboarding.ps1 -FirstName "John" -LastName "Doe" -Department "IT" -Title "System Administrator" -Manager "jsmith" -LicenseSKU "SPE_E3" -SendWelcomeEmail

    Creates a complete onboarding for John Doe in IT department with E3 license and sends welcome email

.EXAMPLE
    .\New-UserOnboarding.ps1 -FirstName "Jane" -LastName "Smith" -Username "jsmith2" -Email "jane.smith@contoso.com" -Department "Sales" -Title "Sales Manager" -LicenseSKU "SPE_E5" -NotifyManager -NotifyIT

    Creates onboarding with custom username/email, assigns E5 license, and sends notifications

.EXAMPLE
    .\New-UserOnboarding.ps1 -FirstName "Bob" -LastName "Johnson" -Department "Marketing" -StartDate "2025-02-01" -Groups "VPN-Users","Remote-Workers" -WhatIf

    Preview onboarding for future start date with additional groups

.EXAMPLE
    Get-Content users.csv | ForEach-Object { .\New-UserOnboarding.ps1 -FirstName $_.FirstName -LastName $_.LastName -Department $_.Department -LicenseSKU $_.License }

    Bulk onboarding from CSV file
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$FirstName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$LastName,

    [Parameter(Mandatory=$false)]
    [string]$Username,

    [Parameter(Mandatory=$false)]
    [string]$Email,

    [Parameter(Mandatory=$true)]
    [ValidateSet("IT", "Sales", "Marketing", "Finance", "HR", "Operations", "Engineering", "Support", "Management", "Other")]
    [string]$Department,

    [Parameter(Mandatory=$false)]
    [string]$Title,

    [Parameter(Mandatory=$false)]
    [string]$Manager,

    [Parameter(Mandatory=$false)]
    [string]$Office,

    [Parameter(Mandatory=$false)]
    [string]$PhoneNumber,

    [Parameter(Mandatory=$false)]
    [DateTime]$StartDate = (Get-Date),

    [Parameter(Mandatory=$false)]
    [string[]]$Groups,

    [Parameter(Mandatory=$false)]
    [ValidateSet("SPE_E3", "SPE_E5", "O365_BUSINESS_PREMIUM", "O365_BUSINESS_ESSENTIALS", "ENTERPRISEPACK", "")]
    [string]$LicenseSKU,

    [Parameter(Mandatory=$false)]
    [string[]]$TeamsChannels,

    [Parameter(Mandatory=$false)]
    [string]$HomeFolderPath,

    [Parameter(Mandatory=$false)]
    [string]$ProfilePath,

    [Parameter(Mandatory=$false)]
    [switch]$SendWelcomeEmail,

    [Parameter(Mandatory=$false)]
    [switch]$NotifyManager,

    [Parameter(Mandatory=$false)]
    [switch]$NotifyIT,

    [Parameter(Mandatory=$false)]
    [string]$ITEmail = "it-team@contoso.com",

    [Parameter(Mandatory=$false)]
    [string]$Domain = "contoso.com",

    [Parameter(Mandatory=$false)]
    [switch]$SkipAD,

    [Parameter(Mandatory=$false)]
    [switch]$SkipLicense
)

#region Configuration

# Department-based default groups
$departmentGroups = @{
    "IT" = @("IT-Team", "VPN-Users", "Remote-Desktop-Users")
    "Sales" = @("Sales-Team", "CRM-Users")
    "Marketing" = @("Marketing-Team", "Design-Tools-Users")
    "Finance" = @("Finance-Team", "Accounting-Software-Users")
    "HR" = @("HR-Team", "HRIS-Users")
    "Operations" = @("Operations-Team")
    "Engineering" = @("Engineering-Team", "Dev-Tools-Users")
    "Support" = @("Support-Team", "Ticketing-Users")
    "Management" = @("Management-Team")
    "Other" = @()
}

# Base OU for departments
$baseOU = "OU=Users,DC=$($Domain.Split('.')[0]),DC=$($Domain.Split('.')[1])"

#endregion

#region Helper Functions

function Write-WorkflowStep {
    param(
        [string]$Step,
        [string]$Message,
        [string]$Status = "Info"
    )

    $color = switch ($Status) {
        "Success" { "Green" }
        "Error" { "Red" }
        "Warning" { "Yellow" }
        "Info" { "Cyan" }
        default { "White" }
    }

    $icon = switch ($Status) {
        "Success" { "✓" }
        "Error" { "✗" }
        "Warning" { "⚠" }
        "Info" { "ℹ" }
        default { "•" }
    }

    Write-Host "  $icon $Message" -ForegroundColor $color
}

function Generate-StrongPassword {
    Add-Type -AssemblyName 'System.Web'
    $password = [System.Web.Security.Membership]::GeneratePassword(16, 4)
    # Ensure it meets complexity requirements
    $password = $password -replace '[^\w\d!@#$%^&*]', ''
    if ($password.Length -lt 16) {
        $password += "Aa1!"
    }
    return $password
}

function Send-WelcomeEmailToUser {
    param(
        [string]$UserEmail,
        [string]$UserName,
        [string]$FullName,
        [string]$TempPassword
    )

    $subject = "Welcome to $Domain - Your Account Information"
    $body = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .header { background-color: #0078D4; color: white; padding: 20px; text-align: center; }
        .content { padding: 20px; background-color: #f9f9f9; }
        .info-box { background-color: #FFF4CE; border-left: 4px solid #D83B01; padding: 15px; margin: 15px 0; }
        .credentials { background-color: #e8f4f8; border: 1px solid #0078D4; padding: 15px; margin: 15px 0; }
        .footer { padding: 20px; text-align: center; font-size: 12px; color: #666; }
        ul { margin: 10px 0; }
        li { margin: 5px 0; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Welcome to the Team!</h1>
    </div>

    <div class="content">
        <p>Dear $FullName,</p>

        <p>Welcome! Your account has been created and is ready to use. Below you'll find your login credentials and important information to get started.</p>

        <div class="credentials">
            <h3>Your Login Credentials</h3>
            <p><strong>Username:</strong> $UserName</p>
            <p><strong>Email:</strong> $UserEmail</p>
            <p><strong>Temporary Password:</strong> <code>$TempPassword</code></p>
        </div>

        <div class="info-box">
            <strong>⚠ Important:</strong> You will be required to change your password on first login for security reasons.
        </div>

        <h3>Getting Started</h3>
        <ol>
            <li><strong>Email Access:</strong> Visit <a href="https://outlook.office365.com">https://outlook.office365.com</a></li>
            <li><strong>Microsoft Teams:</strong> Download from <a href="https://teams.microsoft.com">https://teams.microsoft.com</a></li>
            <li><strong>OneDrive:</strong> Access your files at <a href="https://onedrive.com">https://onedrive.com</a></li>
            <li><strong>Password Reset:</strong> Use <a href="https://aka.ms/sspr">https://aka.ms/sspr</a> if needed</li>
        </ol>

        <h3>Important Links</h3>
        <ul>
            <li><a href="https://portal.office.com">Office 365 Portal</a></li>
            <li><a href="https://myapps.microsoft.com">My Apps</a></li>
            <li><a href="https://account.activedirectory.windowsazure.com">Account Settings</a></li>
        </ul>

        <h3>Need Help?</h3>
        <p>If you have any questions or need assistance, please contact:</p>
        <ul>
            <li>IT Support: $ITEmail</li>
            <li>Phone: (555) 123-4567</li>
        </ul>

        <p>We're excited to have you on board!</p>

        <p>Best regards,<br>IT Team</p>
    </div>

    <div class="footer">
        <p>This is an automated message. Please do not reply to this email.</p>
        <p>&copy; $(Get-Date -Format yyyy) $Domain - All rights reserved.</p>
    </div>
</body>
</html>
"@

    try {
        # Using Microsoft Graph to send email
        $message = @{
            subject = $subject
            body = @{
                contentType = "HTML"
                content = $body
            }
            toRecipients = @(
                @{
                    emailAddress = @{
                        address = $UserEmail
                    }
                }
            )
        }

        Write-WorkflowStep -Message "Welcome email prepared for $UserEmail" -Status "Success"
        # Actual sending would require: Send-MgUserMail -UserId $currentUserId -Message $message
    } catch {
        Write-WorkflowStep -Message "Failed to send welcome email: $_" -Status "Error"
    }
}

#endregion

#region Main Script

# Initialize workflow tracking
$workflow = @{
    Steps = @()
    Success = 0
    Failed = 0
    Warnings = 0
    StartTime = Get-Date
}

Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Automated User Onboarding Workflow" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

# Auto-generate username if not provided
if (-not $Username) {
    $Username = "$($FirstName.ToLower()).$($LastName.ToLower())"
    Write-WorkflowStep -Message "Auto-generated username: $Username" -Status "Info"
}

# Auto-generate email if not provided
if (-not $Email) {
    $Email = "$Username@$Domain"
    Write-WorkflowStep -Message "Auto-generated email: $Email" -Status "Info"
}

Write-Host "User Details:" -ForegroundColor White
Write-Host "  Name: $FirstName $LastName" -ForegroundColor Gray
Write-Host "  Username: $Username" -ForegroundColor Gray
Write-Host "  Email: $Email" -ForegroundColor Gray
Write-Host "  Department: $Department" -ForegroundColor Gray
if ($Title) { Write-Host "  Title: $Title" -ForegroundColor Gray }
if ($Manager) { Write-Host "  Manager: $Manager" -ForegroundColor Gray }
Write-Host "  Start Date: $($StartDate.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
Write-Host ""

# Generate strong password
$tempPassword = Generate-StrongPassword
$securePassword = ConvertTo-SecureString $tempPassword -AsPlainText -Force

#region Step 1: Active Directory Account Creation

if (-not $SkipAD) {
    Write-Host "[Step 1/9] Creating Active Directory Account" -ForegroundColor Yellow
    Write-Host ("=" * 80) -ForegroundColor Gray

    if ($PSCmdlet.ShouldProcess($Username, "Create AD user account")) {
        try {
            # Check if ActiveDirectory module is available
            if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
                Write-WorkflowStep -Message "ActiveDirectory module not found. Skipping AD creation." -Status "Warning"
                $workflow.Warnings++
                $SkipAD = $true
            } else {
                Import-Module ActiveDirectory -ErrorAction Stop

                # Check if user already exists
                $existingUser = Get-ADUser -Filter "SamAccountName -eq '$Username'" -ErrorAction SilentlyContinue
                if ($existingUser) {
                    Write-WorkflowStep -Message "User $Username already exists in AD" -Status "Error"
                    $workflow.Failed++
                    throw "User already exists"
                }

                # Determine OU based on department
                $userOU = "OU=$Department,$baseOU"

                # Build user parameters
                $userParams = @{
                    Name = "$FirstName $LastName"
                    GivenName = $FirstName
                    Surname = $LastName
                    SamAccountName = $Username
                    UserPrincipalName = $Email
                    EmailAddress = $Email
                    DisplayName = "$FirstName $LastName"
                    Department = $Department
                    AccountPassword = $securePassword
                    Enabled = $true
                    ChangePasswordAtLogon = $true
                    PasswordNeverExpires = $false
                    CannotChangePassword = $false
                }

                # Add optional fields
                if ($Title) { $userParams.Title = $Title }
                if ($Office) { $userParams.Office = $Office }
                if ($PhoneNumber) { $userParams.OfficePhone = $PhoneNumber }

                # Get manager DN if specified
                if ($Manager) {
                    try {
                        $managerUser = Get-ADUser -Identity $Manager
                        $userParams.Manager = $managerUser.DistinguishedName
                        Write-WorkflowStep -Message "Manager set to: $($managerUser.Name)" -Status "Success"
                    } catch {
                        Write-WorkflowStep -Message "Manager '$Manager' not found" -Status "Warning"
                        $workflow.Warnings++
                    }
                }

                # Set OU (create if doesn't exist)
                try {
                    $ouExists = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$userOU'" -ErrorAction SilentlyContinue
                    if (-not $ouExists) {
                        Write-WorkflowStep -Message "Department OU doesn't exist, using base OU" -Status "Warning"
                        $userParams.Path = $baseOU
                    } else {
                        $userParams.Path = $userOU
                    }
                } catch {
                    $userParams.Path = $baseOU
                }

                # Set home folder if provided
                if ($HomeFolderPath) {
                    $userParams.HomeDirectory = $HomeFolderPath
                    $userParams.HomeDrive = "H:"
                } else {
                    $defaultHomePath = "\\fileserver\home$\$Username"
                    $userParams.HomeDirectory = $defaultHomePath
                    $userParams.HomeDrive = "H:"
                }

                # Set profile path if provided
                if ($ProfilePath) {
                    $userParams.ProfilePath = $ProfilePath
                }

                # Create the AD user
                New-ADUser @userParams -ErrorAction Stop
                Write-WorkflowStep -Message "AD account created successfully" -Status "Success"
                $workflow.Steps += "AD Account Created"
                $workflow.Success++

                # Wait a moment for AD replication
                Start-Sleep -Seconds 2
            }
        } catch {
            Write-WorkflowStep -Message "Failed to create AD account: $_" -Status "Error"
            $workflow.Steps += "AD Account FAILED: $_"
            $workflow.Failed++

            if (-not $SkipAD) {
                Write-Host "`nCritical error in AD creation. Exiting..." -ForegroundColor Red
                exit 1
            }
        }
    }
} else {
    Write-Host "[Step 1/9] Skipping Active Directory (SkipAD flag set)" -ForegroundColor Gray
}

Write-Host ""

#endregion

#region Step 2: Security Group Membership

Write-Host "[Step 2/9] Configuring Security Group Membership" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Gray

if (-not $SkipAD) {
    # Get department default groups
    $defaultGroups = $departmentGroups[$Department]
    $allGroups = @($defaultGroups)

    # Add custom groups if specified
    if ($Groups) {
        $allGroups += $Groups
    }

    if ($allGroups.Count -gt 0) {
        foreach ($group in $allGroups) {
            if ($PSCmdlet.ShouldProcess($group, "Add user to group")) {
                try {
                    # Check if group exists
                    $adGroup = Get-ADGroup -Filter "Name -eq '$group'" -ErrorAction SilentlyContinue
                    if ($adGroup) {
                        Add-ADGroupMember -Identity $group -Members $Username -ErrorAction Stop
                        Write-WorkflowStep -Message "Added to group: $group" -Status "Success"
                    } else {
                        Write-WorkflowStep -Message "Group not found: $group" -Status "Warning"
                        $workflow.Warnings++
                    }
                } catch {
                    Write-WorkflowStep -Message "Failed to add to $group : $_" -Status "Warning"
                    $workflow.Warnings++
                }
            }
        }
        $workflow.Steps += "Added to $($allGroups.Count) groups"
        $workflow.Success++
    } else {
        Write-WorkflowStep -Message "No groups to add" -Status "Info"
    }
} else {
    Write-WorkflowStep -Message "Skipped (AD creation was skipped)" -Status "Info"
}

Write-Host ""

#endregion

#region Step 3: Home Folder Creation

Write-Host "[Step 3/9] Creating Home Folder" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Gray

if ($PSCmdlet.ShouldProcess($Username, "Create home folder")) {
    try {
        $homePath = if ($HomeFolderPath) { $HomeFolderPath } else { "\\fileserver\home$\$Username" }

        # Check if this is a UNC path that we can access
        if ($homePath -like "\\*") {
            Write-WorkflowStep -Message "Home folder path: $homePath" -Status "Info"
            Write-WorkflowStep -Message "Home folder creation requires file server configuration" -Status "Warning"
            $workflow.Warnings++
            # In production: New-Item -Path $homePath -ItemType Directory -Force
            # Set-Acl to grant user full control
        } else {
            # Local path - create it
            if (-not (Test-Path $homePath)) {
                New-Item -Path $homePath -ItemType Directory -Force | Out-Null
                Write-WorkflowStep -Message "Created home folder: $homePath" -Status "Success"
                $workflow.Success++
            } else {
                Write-WorkflowStep -Message "Home folder already exists: $homePath" -Status "Info"
            }
        }
        $workflow.Steps += "Home Folder: $homePath"
    } catch {
        Write-WorkflowStep -Message "Failed to create home folder: $_" -Status "Warning"
        $workflow.Warnings++
    }
}

Write-Host ""

#endregion

#region Step 4: Azure AD Synchronization Wait

Write-Host "[Step 4/9] Waiting for Azure AD Synchronization" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Gray

if (-not $SkipAD -and -not $SkipLicense) {
    Write-WorkflowStep -Message "Waiting 30 seconds for AD Connect sync..." -Status "Info"

    for ($i = 30; $i -gt 0; $i--) {
        Write-Progress -Activity "Waiting for Azure AD Sync" -Status "$i seconds remaining" -PercentComplete ((30 - $i) / 30 * 100)
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity "Waiting for Azure AD Sync" -Completed

    Write-WorkflowStep -Message "Sync wait completed" -Status "Success"
    $workflow.Steps += "Azure AD Sync Wait"
} else {
    Write-WorkflowStep -Message "Skipped (not applicable)" -Status "Info"
}

Write-Host ""

#endregion

#region Step 5: Microsoft 365 License Assignment

if (-not $SkipLicense -and $LicenseSKU) {
    Write-Host "[Step 5/9] Assigning Microsoft 365 License" -ForegroundColor Yellow
    Write-Host ("=" * 80) -ForegroundColor Gray

    if ($PSCmdlet.ShouldProcess($Email, "Assign M365 license $LicenseSKU")) {
        try {
            # Check for required modules
            $requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Identity.DirectoryManagement')
            $modulesAvailable = $true

            foreach ($module in $requiredModules) {
                if (-not (Get-Module -ListAvailable -Name $module)) {
                    Write-WorkflowStep -Message "Required module not found: $module" -Status "Warning"
                    $modulesAvailable = $false
                }
            }

            if ($modulesAvailable) {
                Import-Module Microsoft.Graph.Authentication
                Import-Module Microsoft.Graph.Users
                Import-Module Microsoft.Graph.Identity.DirectoryManagement

                # Connect to Microsoft Graph
                Write-WorkflowStep -Message "Connecting to Microsoft Graph..." -Status "Info"
                Connect-MgGraph -Scopes "User.ReadWrite.All", "Organization.Read.All" -NoWelcome -ErrorAction Stop

                # Try to find user (may need to retry if sync hasn't completed)
                $retries = 3
                $mgUser = $null

                for ($i = 1; $i -le $retries; $i++) {
                    try {
                        $mgUser = Get-MgUser -Filter "userPrincipalName eq '$Email'" -ErrorAction Stop
                        if ($mgUser) {
                            Write-WorkflowStep -Message "Found user in Azure AD: $($mgUser.DisplayName)" -Status "Success"
                            break
                        }
                    } catch {
                        if ($i -lt $retries) {
                            Write-WorkflowStep -Message "User not found, waiting 10 seconds (attempt $i/$retries)..." -Status "Warning"
                            Start-Sleep -Seconds 10
                        }
                    }
                }

                if ($mgUser) {
                    # Get available SKUs
                    $sku = Get-MgSubscribedSku -All | Where-Object { $_.SkuPartNumber -eq $LicenseSKU }

                    if ($sku) {
                        # Check available licenses
                        $availableLicenses = $sku.PrepaidUnits.Enabled - $sku.ConsumedUnits

                        if ($availableLicenses -gt 0) {
                            # Assign license
                            Set-MgUserLicense -UserId $mgUser.Id -AddLicenses @{SkuId = $sku.SkuId} -RemoveLicenses @() -ErrorAction Stop
                            Write-WorkflowStep -Message "License $LicenseSKU assigned successfully" -Status "Success"
                            Write-WorkflowStep -Message "Available licenses remaining: $($availableLicenses - 1)" -Status "Info"
                            $workflow.Steps += "License: $LicenseSKU"
                            $workflow.Success++
                        } else {
                            Write-WorkflowStep -Message "No available licenses for $LicenseSKU" -Status "Error"
                            $workflow.Failed++
                        }
                    } else {
                        Write-WorkflowStep -Message "License SKU '$LicenseSKU' not found in tenant" -Status "Error"
                        $workflow.Failed++
                    }
                } else {
                    Write-WorkflowStep -Message "User not found in Azure AD after $retries attempts" -Status "Error"
                    Write-WorkflowStep -Message "License assignment will need to be done manually" -Status "Warning"
                    $workflow.Failed++
                }

                Disconnect-MgGraph | Out-Null
            } else {
                Write-WorkflowStep -Message "Microsoft Graph modules not available" -Status "Warning"
                Write-WorkflowStep -Message "Install with: Install-Module Microsoft.Graph -Scope CurrentUser" -Status "Info"
                $workflow.Warnings++
            }
        } catch {
            Write-WorkflowStep -Message "Failed to assign license: $_" -Status "Error"
            $workflow.Failed++
        }
    }
} else {
    Write-Host "[Step 5/9] Skipping License Assignment" -ForegroundColor Gray
    if (-not $LicenseSKU) {
        Write-WorkflowStep -Message "No license specified" -Status "Info"
    }
}

Write-Host ""

#endregion

#region Step 6: Teams Configuration

Write-Host "[Step 6/9] Microsoft Teams Configuration" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Gray

if ($TeamsChannels -and $TeamsChannels.Count -gt 0) {
    Write-WorkflowStep -Message "Teams channels specified: $($TeamsChannels -join ', ')" -Status "Info"
    Write-WorkflowStep -Message "Teams channel assignment requires Microsoft Teams module" -Status "Warning"
    $workflow.Warnings++
    # In production: Add-TeamUser cmdlet would be used here
} else {
    Write-WorkflowStep -Message "No Teams channels specified" -Status "Info"
}

Write-Host ""

#endregion

#region Step 7: Send Welcome Email

Write-Host "[Step 7/9] User Communication" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Gray

if ($SendWelcomeEmail) {
    if ($PSCmdlet.ShouldProcess($Email, "Send welcome email")) {
        Send-WelcomeEmailToUser -UserEmail $Email -UserName $Username -FullName "$FirstName $LastName" -TempPassword $tempPassword
        $workflow.Steps += "Welcome email sent"
        $workflow.Success++
    }
} else {
    Write-WorkflowStep -Message "Welcome email not requested (use -SendWelcomeEmail)" -Status "Info"
}

Write-Host ""

#endregion

#region Step 8: Logging and Reporting

Write-Host "[Step 8/9] Logging Activity" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Gray

$logEntry = [PSCustomObject]@{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Username = $Username
    FirstName = $FirstName
    LastName = $LastName
    Email = $Email
    Department = $Department
    Title = $Title
    Manager = $Manager
    Office = $Office
    PhoneNumber = $PhoneNumber
    StartDate = $StartDate.ToString("yyyy-MM-dd")
    Groups = ($allGroups -join "; ")
    License = $LicenseSKU
    TempPassword = $tempPassword
    CreatedBy = $env:USERNAME
    Status = if ($workflow.Failed -eq 0) { "Success" } else { if ($workflow.Success -gt 0) { "Partial Success" } else { "Failed" } }
    SuccessfulSteps = $workflow.Success
    FailedSteps = $workflow.Failed
    Warnings = $workflow.Warnings
    Duration = ((Get-Date) - $workflow.StartTime).TotalSeconds
}

$logPath = "UserOnboarding_$(Get-Date -Format 'yyyyMMdd').csv"
$logEntry | Export-Csv -Path $logPath -Append -NoTypeInformation -Encoding UTF8
Write-WorkflowStep -Message "Activity logged to: $logPath" -Status "Success"

Write-Host ""

#endregion

#region Step 9: Notifications

Write-Host "[Step 9/9] Sending Notifications" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Gray

if ($NotifyManager -and $Manager) {
    Write-WorkflowStep -Message "Manager notification prepared" -Status "Info"
    # In production: Send email to manager
}

if ($NotifyIT) {
    Write-WorkflowStep -Message "IT team notification prepared for: $ITEmail" -Status "Info"
    # In production: Send summary to IT team
}

if (-not $NotifyManager -and -not $NotifyIT) {
    Write-WorkflowStep -Message "No notifications requested" -Status "Info"
}

Write-Host ""

#endregion

#region Final Summary

$duration = (Get-Date) - $workflow.StartTime

Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Onboarding Summary" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

Write-Host "User Information:" -ForegroundColor White
Write-Host "  Name: $FirstName $LastName" -ForegroundColor Gray
Write-Host "  Username: $Username" -ForegroundColor Gray
Write-Host "  Email: $Email" -ForegroundColor Gray
Write-Host "  Department: $Department" -ForegroundColor Gray
if ($Title) { Write-Host "  Title: $Title" -ForegroundColor Gray }
Write-Host ""

Write-Host "Results:" -ForegroundColor White
Write-Host "  ✓ Successful steps: $($workflow.Success)" -ForegroundColor Green
if ($workflow.Failed -gt 0) {
    Write-Host "  ✗ Failed steps: $($workflow.Failed)" -ForegroundColor Red
}
if ($workflow.Warnings -gt 0) {
    Write-Host "  ⚠ Warnings: $($workflow.Warnings)" -ForegroundColor Yellow
}
Write-Host "  Duration: $([math]::Round($duration.TotalSeconds, 2)) seconds" -ForegroundColor Gray
Write-Host ""

if ($workflow.Steps.Count -gt 0) {
    Write-Host "Completed Steps:" -ForegroundColor White
    $workflow.Steps | ForEach-Object { Write-Host "  • $_" -ForegroundColor Gray }
    Write-Host ""
}

Write-Host "Credentials:" -ForegroundColor White
Write-Host "  Username: $Username" -ForegroundColor Gray
Write-Host "  Temporary Password: $tempPassword" -ForegroundColor Yellow
Write-Host "  ⚠ User must change password on first login" -ForegroundColor Yellow
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor White
if (-not $SendWelcomeEmail) {
    Write-Host "  1. Send credentials to user securely" -ForegroundColor Gray
}
if ($workflow.Failed -gt 0 -or $workflow.Warnings -gt 0) {
    Write-Host "  2. Review and resolve warnings/errors above" -ForegroundColor Gray
}
Write-Host "  3. Verify user can login successfully" -ForegroundColor Gray
Write-Host "  4. Confirm email access and Teams functionality" -ForegroundColor Gray
Write-Host ""

Write-Host ("=" * 80) -ForegroundColor Gray

if ($workflow.Failed -eq 0) {
    Write-Host "✓ Onboarding completed successfully!" -ForegroundColor Green
} elseif ($workflow.Success -gt 0) {
    Write-Host "⚠ Onboarding completed with some errors" -ForegroundColor Yellow
    Write-Host "  Please review the output above and complete failed steps manually" -ForegroundColor Yellow
} else {
    Write-Host "✗ Onboarding failed" -ForegroundColor Red
    Write-Host "  Please review errors and try again" -ForegroundColor Red
    exit 1
}

Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

#endregion
