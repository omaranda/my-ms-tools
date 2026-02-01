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
    List, search, and interactively remove Microsoft 365 users with automatic license cleanup.

.DESCRIPTION
    This script provides a complete user management workflow:

    - Lists ALL users in the tenant (not just licensed ones)
    - Filters by department, status, license state, inactivity, or name
    - Interactive selection to choose which users to delete
    - Automatically removes licenses before deletion (reclaims them)
    - Full cleanup: block sign-in, revoke sessions, remove groups, remove licenses, delete
    - Audit logging with timestamped CSV

    Use cases:
    - Browse all tenant users and selectively remove them
    - Find and clean up disabled accounts
    - Remove inactive users and reclaim their licenses
    - Bulk user deletion with license recovery
    - Search for specific users by name or email

.PARAMETER ListOnly
    Show user list without enabling deletion (default mode)

.PARAMETER Interactive
    Interactive mode: list users with numbered menu for selection and deletion

.PARAMETER Department
    Filter users by department (e.g., "Sales", "IT")

.PARAMETER OnlyDisabled
    Show only disabled accounts

.PARAMETER OnlyLicensed
    Show only users that have licenses assigned

.PARAMETER OnlyUnlicensed
    Show only users without any licenses

.PARAMETER InactiveDays
    Filter users who haven't signed in for the specified number of days

.PARAMETER SearchName
    Search users by display name or email (case-insensitive, partial match)

.PARAMETER UserType
    Filter by user type: Member or Guest (default: Member)

.PARAMETER PageSize
    Number of users to display per page in interactive mode (default: 25)

.PARAMETER ExportPath
    Export user list to CSV file

.PARAMETER BackupBeforeDelete
    Export user data to backup CSV before deletion

.PARAMETER SkipGroupRemoval
    Skip removing users from groups before deletion

.PARAMETER SkipTokenRevocation
    Skip revoking active sessions before deletion

.PARAMETER BlockOnly
    Only block sign-in and remove licenses, don't delete the user account

.PARAMETER Force
    Skip confirmation prompts

.PARAMETER WhatIf
    Preview changes without applying

.EXAMPLE
    .\Remove-M365Users.ps1 -ListOnly

    Lists all member users in the tenant

.EXAMPLE
    .\Remove-M365Users.ps1 -ListOnly -Department "Sales"

    Lists all users in the Sales department

.EXAMPLE
    .\Remove-M365Users.ps1 -ListOnly -OnlyDisabled -OnlyLicensed

    Lists disabled accounts that still have licenses (waste)

.EXAMPLE
    .\Remove-M365Users.ps1 -Interactive -InactiveDays 180

    Interactive mode showing users inactive for 180+ days, select and delete

.EXAMPLE
    .\Remove-M365Users.ps1 -Interactive -SearchName "john"

    Interactive mode showing users matching "john" in name or email

.EXAMPLE
    .\Remove-M365Users.ps1 -Interactive -OnlyDisabled -BackupBeforeDelete

    Interactive mode for disabled accounts, backup data before deletion

.EXAMPLE
    .\Remove-M365Users.ps1 -Interactive -BlockOnly

    Interactive mode: block sign-in and remove licenses without deleting accounts

.EXAMPLE
    .\Remove-M365Users.ps1 -ListOnly -ExportPath "./all-users.csv"

    Export all users to CSV for review
#>

[CmdletBinding(SupportsShouldProcess=$true, DefaultParameterSetName='List')]
param(
    [Parameter(ParameterSetName='List')]
    [switch]$ListOnly,

    [Parameter(ParameterSetName='Interactive')]
    [switch]$Interactive,

    [Parameter(Mandatory=$false)]
    [string]$Department,

    [Parameter(Mandatory=$false)]
    [switch]$OnlyDisabled,

    [Parameter(Mandatory=$false)]
    [switch]$OnlyLicensed,

    [Parameter(Mandatory=$false)]
    [switch]$OnlyUnlicensed,

    [Parameter(Mandatory=$false)]
    [int]$InactiveDays,

    [Parameter(Mandatory=$false)]
    [string]$SearchName,

    [Parameter(Mandatory=$false)]
    [ValidateSet("Member", "Guest")]
    [string]$UserType = "Member",

    [Parameter(Mandatory=$false)]
    [int]$PageSize = 25,

    [Parameter(Mandatory=$false)]
    [string]$ExportPath,

    [Parameter(Mandatory=$false)]
    [switch]$BackupBeforeDelete,

    [Parameter(Mandatory=$false)]
    [switch]$SkipGroupRemoval,

    [Parameter(Mandatory=$false)]
    [switch]$SkipTokenRevocation,

    [Parameter(Mandatory=$false)]
    [switch]$BlockOnly,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

#region Helper Functions

function Write-UserLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error", "Action")]
        [string]$Level = "Info"
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        "Action" { "Magenta" }
        default { "Cyan" }
    }

    $icon = switch ($Level) {
        "Success" { [char]0x2713 }
        "Warning" { [char]0x26A0 }
        "Error" { [char]0x2717 }
        "Action" { [char]0x2192 }
        default { [char]0x2139 }
    }

    Write-Host "[$timestamp] $icon $Message" -ForegroundColor $color
}

function Get-LicenseFriendlyName {
    param([string]$SkuPartNumber)

    $friendlyNames = @{
        "O365_BUSINESS_PREMIUM"    = "M365 Business Premium"
        "O365_BUSINESS_ESSENTIALS" = "M365 Business Basic"
        "O365_BUSINESS"            = "M365 Apps for Business"
        "SMB_BUSINESS_PREMIUM"     = "M365 Business Premium"
        "SMB_BUSINESS_ESSENTIALS"  = "M365 Business Basic"
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
        "EMS"                      = "EMS E3"
        "EMSPREMIUM"               = "EMS E5"
        "INTUNE_A"                 = "Intune"
        "ATP_ENTERPRISE"           = "Defender for O365 P1"
        "THREAT_INTELLIGENCE"      = "Defender for O365 P2"
        "STANDARDPACK"             = "Office 365 E1"
    }

    if ($friendlyNames.ContainsKey($SkuPartNumber)) {
        return $friendlyNames[$SkuPartNumber]
    }
    return $SkuPartNumber
}

function Get-UserLicenseNames {
    param($User, $Skus)

    if (-not $User.AssignedLicenses -or $User.AssignedLicenses.Count -eq 0) {
        return ""
    }

    $names = @()
    foreach ($license in $User.AssignedLicenses) {
        $sku = $Skus | Where-Object { $_.SkuId -eq $license.SkuId }
        if ($sku) {
            $names += Get-LicenseFriendlyName -SkuPartNumber $sku.SkuPartNumber
        }
    }
    return $names -join ", "
}

function Format-UserRow {
    param(
        [int]$Index,
        [object]$UserInfo,
        [switch]$Numbered
    )

    $status = if ($UserInfo.AccountEnabled) { "Active" } else { "Disabled" }
    $statusColor = if ($UserInfo.AccountEnabled) { "Green" } else { "Red" }

    $signIn = if ($UserInfo.LastSignIn) {
        $UserInfo.LastSignIn.ToString("yyyy-MM-dd")
    } else {
        "Never"
    }

    $nameDisplay = $UserInfo.DisplayName
    if ($nameDisplay.Length -gt 22) { $nameDisplay = $nameDisplay.Substring(0, 22) + "..." }

    $emailDisplay = $UserInfo.Email
    if ($emailDisplay.Length -gt 28) { $emailDisplay = $emailDisplay.Substring(0, 28) + "..." }

    $deptDisplay = if ($UserInfo.Department) { $UserInfo.Department } else { "-" }
    if ($deptDisplay.Length -gt 12) { $deptDisplay = $deptDisplay.Substring(0, 12) + "..." }

    $licenseDisplay = if ($UserInfo.Licenses) { $UserInfo.Licenses } else { "None" }
    if ($licenseDisplay.Length -gt 30) { $licenseDisplay = $licenseDisplay.Substring(0, 30) + "..." }

    if ($Numbered) {
        Write-Host ("[{0,3}] " -f $Index) -ForegroundColor White -NoNewline
    } else {
        Write-Host "  " -NoNewline
    }

    Write-Host ("{0,-25}" -f $nameDisplay) -ForegroundColor Gray -NoNewline
    Write-Host ("{0,-31}" -f $emailDisplay) -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-10}" -f $status) -ForegroundColor $statusColor -NoNewline
    Write-Host ("{0,-15}" -f $deptDisplay) -ForegroundColor DarkCyan -NoNewline
    Write-Host ("Last: {0,-12}" -f $signIn) -ForegroundColor DarkYellow -NoNewline
    Write-Host (" $licenseDisplay") -ForegroundColor Magenta
}

function Show-PagedUserMenu {
    param(
        [array]$Users,
        [int]$PageSize
    )

    $totalPages = [math]::Ceiling($Users.Count / $PageSize)
    $currentPage = 1
    $selectedIndices = @()

    while ($true) {
        $startIndex = ($currentPage - 1) * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize - 1, $Users.Count - 1)

        Write-Host ""
        Write-Host ("=" * 120) -ForegroundColor Cyan
        Write-Host ("  Users (Page $currentPage of $totalPages) - Total: $($Users.Count)") -ForegroundColor Cyan
        Write-Host ("=" * 120) -ForegroundColor Cyan
        Write-Host ""

        # Header
        Write-Host ("      {0,-25}{1,-31}{2,-10}{3,-15}{4,-18}{5}" -f "Name", "Email", "Status", "Department", "Last Sign-in", "Licenses") -ForegroundColor DarkGray
        Write-Host ("      " + ("-" * 114)) -ForegroundColor DarkGray

        for ($i = $startIndex; $i -le $endIndex; $i++) {
            Format-UserRow -Index ($i + 1) -UserInfo $Users[$i] -Numbered
        }

        Write-Host ""
        Write-Host ("-" * 120) -ForegroundColor Gray
        Write-Host ""

        if ($selectedIndices.Count -gt 0) {
            Write-Host "  Selected: $($selectedIndices.Count) user(s)" -ForegroundColor Yellow
        }

        Write-Host "  Commands:" -ForegroundColor DarkGray
        Write-Host "    Numbers (comma-separated) = Select users  |  all = Select all  |  clear = Clear selection" -ForegroundColor DarkGray
        if ($totalPages -gt 1) {
            Write-Host "    n = Next page  |  p = Previous page  |  g <num> = Go to page" -ForegroundColor DarkGray
        }
        Write-Host "    s <text> = Search within results  |  done = Proceed with selected  |  q = Quit" -ForegroundColor DarkGray
        Write-Host ""

        $input = Read-Host "  Command"
        $input = $input.Trim()

        if ($input -eq 'q' -or $input -eq 'Q') {
            return @()
        }

        if ($input -eq 'done') {
            if ($selectedIndices.Count -eq 0) {
                Write-Host "  No users selected. Select users first or press 'q' to quit." -ForegroundColor Yellow
                continue
            }
            $selectedUsers = @()
            foreach ($idx in ($selectedIndices | Sort-Object)) {
                $selectedUsers += $Users[$idx - 1]
            }
            return $selectedUsers
        }

        if ($input -eq 'all') {
            $selectedIndices = @(1..$Users.Count)
            Write-Host "  All $($Users.Count) users selected" -ForegroundColor Yellow
            continue
        }

        if ($input -eq 'clear') {
            $selectedIndices = @()
            Write-Host "  Selection cleared" -ForegroundColor Yellow
            continue
        }

        if ($input -eq 'n' -and $currentPage -lt $totalPages) {
            $currentPage++
            continue
        }

        if ($input -eq 'p' -and $currentPage -gt 1) {
            $currentPage--
            continue
        }

        if ($input -match '^g\s+(\d+)$') {
            $targetPage = [int]$Matches[1]
            if ($targetPage -ge 1 -and $targetPage -le $totalPages) {
                $currentPage = $targetPage
            } else {
                Write-Host "  Invalid page number (1-$totalPages)" -ForegroundColor Red
            }
            continue
        }

        if ($input -match '^s\s+(.+)$') {
            $searchTerm = $Matches[1].ToLower()
            Write-Host ""
            Write-Host "  Search results for '$searchTerm':" -ForegroundColor Cyan
            $found = $false
            for ($i = 0; $i -lt $Users.Count; $i++) {
                if ($Users[$i].DisplayName.ToLower().Contains($searchTerm) -or $Users[$i].Email.ToLower().Contains($searchTerm)) {
                    Format-UserRow -Index ($i + 1) -UserInfo $Users[$i] -Numbered
                    $found = $true
                }
            }
            if (-not $found) {
                Write-Host "  No matches found" -ForegroundColor Yellow
            }
            Write-Host ""
            Read-Host "  Press Enter to continue"
            continue
        }

        # Try to parse as numbers
        $numbers = $input -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
        if ($numbers.Count -gt 0) {
            foreach ($num in $numbers) {
                $n = [int]$num
                if ($n -ge 1 -and $n -le $Users.Count) {
                    if ($selectedIndices -notcontains $n) {
                        $selectedIndices += $n
                        Write-Host "  + $($Users[$n - 1].DisplayName) <$($Users[$n - 1].Email)>" -ForegroundColor Green
                    } else {
                        # Deselect if already selected
                        $selectedIndices = $selectedIndices | Where-Object { $_ -ne $n }
                        Write-Host "  - $($Users[$n - 1].DisplayName) (deselected)" -ForegroundColor DarkGray
                    }
                } else {
                    Write-Host "  Invalid number: $n (valid range: 1-$($Users.Count))" -ForegroundColor Red
                }
            }
            continue
        }

        Write-Host "  Unknown command. Type 'q' to quit or numbers to select users." -ForegroundColor Yellow
    }
}

function Remove-UserWithCleanup {
    param(
        [object]$UserInfo,
        [array]$Skus,
        [bool]$SkipGroups,
        [bool]$SkipTokens,
        [bool]$BlockOnly,
        [bool]$IsWhatIf
    )

    $result = [PSCustomObject]@{
        Email       = $UserInfo.Email
        DisplayName = $UserInfo.DisplayName
        Actions     = @()
        Success     = $true
        Error       = $null
    }

    Write-Host ""
    Write-Host "  Processing: $($UserInfo.DisplayName) <$($UserInfo.Email)>" -ForegroundColor Yellow

    try {
        # Step 1: Block sign-in
        Write-UserLog "    Blocking sign-in..." -Level "Action"
        if (-not $IsWhatIf) {
            Update-MgUser -UserId $UserInfo.Id -AccountEnabled:$false -ErrorAction Stop
        }
        $result.Actions += "Sign-in blocked"
        Write-UserLog "    Sign-in blocked" -Level "Success"

        # Step 2: Revoke tokens
        if (-not $SkipTokens) {
            Write-UserLog "    Revoking all sessions..." -Level "Action"
            if (-not $IsWhatIf) {
                Revoke-MgUserSignInSession -UserId $UserInfo.Id -ErrorAction Stop
            }
            $result.Actions += "Sessions revoked"
            Write-UserLog "    All sessions revoked" -Level "Success"
        }

        # Step 3: Remove from groups
        if (-not $SkipGroups) {
            Write-UserLog "    Removing from groups..." -Level "Action"
            if (-not $IsWhatIf) {
                $memberOf = Get-MgUserMemberOf -UserId $UserInfo.Id -All
                $groupCount = 0
                foreach ($group in $memberOf) {
                    if ($group.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group') {
                        try {
                            Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $UserInfo.Id -ErrorAction SilentlyContinue
                            $groupCount++
                        } catch {
                            # Some groups may not allow removal (dynamic, etc.)
                        }
                    }
                }
                $result.Actions += "Removed from $groupCount groups"
                Write-UserLog "    Removed from $groupCount groups" -Level "Success"
            } else {
                $result.Actions += "Would remove from groups"
                Write-UserLog "    Would remove from groups" -Level "Success"
            }
        }

        # Step 4: Remove licenses
        if ($UserInfo.LicenseSkuIds -and $UserInfo.LicenseSkuIds.Count -gt 0) {
            Write-UserLog "    Removing licenses: $($UserInfo.Licenses)..." -Level "Action"
            if (-not $IsWhatIf) {
                Set-MgUserLicense -UserId $UserInfo.Id `
                    -AddLicenses @() `
                    -RemoveLicenses $UserInfo.LicenseSkuIds `
                    -ErrorAction Stop
            }
            $result.Actions += "Licenses removed: $($UserInfo.Licenses)"
            Write-UserLog "    Licenses removed" -Level "Success"
        } else {
            Write-UserLog "    No licenses to remove" -Level "Info"
        }

        # Step 5: Delete user (unless BlockOnly)
        if (-not $BlockOnly) {
            Write-UserLog "    Deleting user account..." -Level "Action"
            if (-not $IsWhatIf) {
                Remove-MgUser -UserId $UserInfo.Id -ErrorAction Stop
            }
            $result.Actions += "User deleted"
            Write-UserLog "    User account deleted" -Level "Success"
        } else {
            Write-UserLog "    User blocked but NOT deleted (BlockOnly mode)" -Level "Warning"
            $result.Actions += "User blocked (not deleted)"
        }
    } catch {
        $result.Success = $false
        $result.Error = $_.Exception.Message
        Write-UserLog "    Error: $_" -Level "Error"
    }

    return $result
}

#endregion

#region Main Script

Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Microsoft 365 User Management & Cleanup Tool" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

# Check for required modules
$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.Identity.DirectoryManagement'
)

Write-UserLog "Checking required modules..." -Level "Info"
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-UserLog "Required module not found: $module" -Level "Warning"
        Write-Host ""
        Write-Host "To install required modules, run:" -ForegroundColor Yellow
        Write-Host "  Install-Module Microsoft.Graph -Scope CurrentUser -Force" -ForegroundColor White
        exit 1
    }
}

# Import modules
Write-UserLog "Importing Microsoft Graph modules..." -Level "Info"
try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.Users -ErrorAction Stop
    Import-Module Microsoft.Graph.Groups -ErrorAction Stop
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
    Write-UserLog "Modules imported successfully" -Level "Success"
} catch {
    Write-UserLog "Failed to import modules: $_" -Level "Error"
    exit 1
}

# Connect to Microsoft Graph
Write-Host ""
Write-UserLog "Connecting to Microsoft Graph..." -Level "Info"
$scopes = @(
    "User.ReadWrite.All",
    "Directory.ReadWrite.All",
    "Group.ReadWrite.All",
    "Organization.Read.All",
    "AuditLog.Read.All"
)

try {
    Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop
    Write-UserLog "Successfully connected to Microsoft Graph" -Level "Success"
} catch {
    Write-UserLog "Failed to connect to Microsoft Graph: $_" -Level "Error"
    exit 1
}

# Get license information
Write-UserLog "Retrieving license information..." -Level "Info"
try {
    $subscribedSkus = Get-MgSubscribedSku -All
    Write-UserLog "Found $($subscribedSkus.Count) license types" -Level "Success"
} catch {
    Write-UserLog "Failed to retrieve licenses: $_" -Level "Error"
    Disconnect-MgGraph | Out-Null
    exit 1
}

# Build Graph filter
$graphFilter = "userType eq '$UserType'"
if ($Department) {
    $graphFilter += " and department eq '$Department'"
}

# Retrieve users
Write-Host ""
Write-UserLog "Retrieving users (filter: $graphFilter)..." -Level "Info"

try {
    $allUsers = Get-MgUser -Filter $graphFilter -All `
        -Property Id, DisplayName, UserPrincipalName, Mail, AccountEnabled, `
                  AssignedLicenses, SignInActivity, CreatedDateTime, Department, `
                  JobTitle, UserType `
        -ConsistencyLevel eventual -CountVariable totalCount `
        -ErrorAction Stop

    Write-UserLog "Retrieved $($allUsers.Count) users" -Level "Success"
} catch {
    Write-UserLog "Failed to retrieve users: $_" -Level "Error"
    Disconnect-MgGraph | Out-Null
    exit 1
}

# Process users into structured objects
Write-UserLog "Processing user data..." -Level "Info"
$userList = @()

foreach ($user in $allUsers) {
    $licenseNames = Get-UserLicenseNames -User $user -Skus $subscribedSkus
    $licenseSkuIds = @()
    if ($user.AssignedLicenses) {
        $licenseSkuIds = $user.AssignedLicenses | ForEach-Object { $_.SkuId }
    }

    $lastSignIn = $null
    $daysSinceSignIn = $null
    if ($user.SignInActivity -and $user.SignInActivity.LastSignInDateTime) {
        $lastSignIn = $user.SignInActivity.LastSignInDateTime
        $daysSinceSignIn = [math]::Round(((Get-Date) - $lastSignIn).TotalDays)
    }

    $userList += [PSCustomObject]@{
        Id              = $user.Id
        DisplayName     = $user.DisplayName
        Email           = if ($user.Mail) { $user.Mail } else { $user.UserPrincipalName }
        UPN             = $user.UserPrincipalName
        AccountEnabled  = $user.AccountEnabled
        Department      = $user.Department
        JobTitle        = $user.JobTitle
        LastSignIn      = $lastSignIn
        DaysSinceSignIn = $daysSinceSignIn
        Licenses        = $licenseNames
        LicenseSkuIds   = $licenseSkuIds
        LicenseCount    = if ($user.AssignedLicenses) { $user.AssignedLicenses.Count } else { 0 }
        CreatedDateTime = $user.CreatedDateTime
        UserType        = $user.UserType
    }
}

# Apply client-side filters
$filteredUsers = $userList

if ($OnlyDisabled) {
    $filteredUsers = $filteredUsers | Where-Object { -not $_.AccountEnabled }
}

if ($OnlyLicensed) {
    $filteredUsers = $filteredUsers | Where-Object { $_.LicenseCount -gt 0 }
}

if ($OnlyUnlicensed) {
    $filteredUsers = $filteredUsers | Where-Object { $_.LicenseCount -eq 0 }
}

if ($InactiveDays -gt 0) {
    $filteredUsers = $filteredUsers | Where-Object {
        ($_.DaysSinceSignIn -ne $null -and $_.DaysSinceSignIn -ge $InactiveDays) -or
        ($_.DaysSinceSignIn -eq $null -and $_.LastSignIn -eq $null)
    }
}

if ($SearchName) {
    $search = $SearchName.ToLower()
    $filteredUsers = $filteredUsers | Where-Object {
        $_.DisplayName.ToLower().Contains($search) -or
        $_.Email.ToLower().Contains($search)
    }
}

# Sort by DisplayName
$filteredUsers = @($filteredUsers | Sort-Object DisplayName)

# Show filter summary
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Gray
Write-Host "Filter Summary" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Gray
Write-Host ""
Write-Host "  Total users in tenant:   $($userList.Count)" -ForegroundColor White
Write-Host "  After filters:           $($filteredUsers.Count)" -ForegroundColor $(if ($filteredUsers.Count -gt 0) { "Green" } else { "Yellow" })

$activeCount = ($filteredUsers | Where-Object { $_.AccountEnabled }).Count
$disabledCount = ($filteredUsers | Where-Object { -not $_.AccountEnabled }).Count
$licensedCount = ($filteredUsers | Where-Object { $_.LicenseCount -gt 0 }).Count
$unlicensedCount = ($filteredUsers | Where-Object { $_.LicenseCount -eq 0 }).Count

Write-Host "    Active:    $activeCount  |  Disabled: $disabledCount" -ForegroundColor DarkGray
Write-Host "    Licensed:  $licensedCount  |  Unlicensed: $unlicensedCount" -ForegroundColor DarkGray

if ($Department) { Write-Host "  Department filter:       $Department" -ForegroundColor DarkGray }
if ($OnlyDisabled) { Write-Host "  Showing:                 Disabled only" -ForegroundColor DarkGray }
if ($OnlyLicensed) { Write-Host "  Showing:                 Licensed only" -ForegroundColor DarkGray }
if ($OnlyUnlicensed) { Write-Host "  Showing:                 Unlicensed only" -ForegroundColor DarkGray }
if ($InactiveDays -gt 0) { Write-Host "  Inactive threshold:      $InactiveDays days" -ForegroundColor DarkGray }
if ($SearchName) { Write-Host "  Search:                  '$SearchName'" -ForegroundColor DarkGray }

if ($filteredUsers.Count -eq 0) {
    Write-Host ""
    Write-UserLog "No users match the specified filters" -Level "Warning"
    Disconnect-MgGraph | Out-Null
    exit 0
}

# Export if requested
if ($ExportPath) {
    Write-Host ""
    Write-UserLog "Exporting to CSV: $ExportPath" -Level "Info"
    try {
        $filteredUsers | Select-Object DisplayName, Email, UPN, AccountEnabled, Department, `
            JobTitle, LastSignIn, DaysSinceSignIn, Licenses, LicenseCount, CreatedDateTime, UserType |
            Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
        Write-UserLog "Exported $($filteredUsers.Count) users to $ExportPath" -Level "Success"
    } catch {
        Write-UserLog "Failed to export: $_" -Level "Error"
    }
}

# ListOnly mode: display and exit
if ($PSCmdlet.ParameterSetName -eq 'List' -or (-not $Interactive)) {
    Write-Host ""
    Write-Host ("=" * 120) -ForegroundColor Gray
    Write-Host "User List" -ForegroundColor Cyan
    Write-Host ("=" * 120) -ForegroundColor Gray
    Write-Host ""

    # Header
    Write-Host ("  {0,-25}{1,-31}{2,-10}{3,-15}{4,-18}{5}" -f "Name", "Email", "Status", "Department", "Last Sign-in", "Licenses") -ForegroundColor DarkGray
    Write-Host ("  " + ("-" * 114)) -ForegroundColor DarkGray

    foreach ($u in $filteredUsers) {
        Format-UserRow -Index 0 -UserInfo $u
    }

    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-UserLog "Listed $($filteredUsers.Count) users" -Level "Success"
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Tip: Use -Interactive to select and remove users" -ForegroundColor DarkGray
    Write-Host ""

    Disconnect-MgGraph | Out-Null
    exit 0
}

# Interactive mode
$selectedUsers = Show-PagedUserMenu -Users $filteredUsers -PageSize $PageSize

if ($selectedUsers.Count -eq 0) {
    Write-UserLog "No users selected. Operation cancelled." -Level "Info"
    Disconnect-MgGraph | Out-Null
    exit 0
}

# Show selected users and planned actions
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Red
Write-Host "Selected Users for Removal" -ForegroundColor Red
Write-Host ("=" * 80) -ForegroundColor Red
Write-Host ""

foreach ($u in $selectedUsers) {
    $status = if ($u.AccountEnabled) { "Active" } else { "Disabled" }
    $statusColor = if ($u.AccountEnabled) { "Green" } else { "Red" }
    $licenseInfo = if ($u.Licenses) { $u.Licenses } else { "None" }

    Write-Host ("  {0} {1,-30} [{2}]  Licenses: {3}" -f [char]0x2022, $u.DisplayName, $status, $licenseInfo) -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Actions to perform:" -ForegroundColor White
Write-Host "    1. Block sign-in" -ForegroundColor Gray
if (-not $SkipTokenRevocation) { Write-Host "    2. Revoke all sessions" -ForegroundColor Gray }
if (-not $SkipGroupRemoval) { Write-Host "    3. Remove from all groups" -ForegroundColor Gray }
Write-Host "    4. Remove all licenses (reclaim)" -ForegroundColor Gray
if ($BlockOnly) {
    Write-Host "    5. User will NOT be deleted (BlockOnly)" -ForegroundColor Yellow
} else {
    Write-Host "    5. Delete user account permanently" -ForegroundColor Red
}

# Backup before delete
if ($BackupBeforeDelete) {
    $backupPath = "UserBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    Write-Host ""
    Write-UserLog "Backing up user data to: $backupPath" -Level "Info"
    try {
        $selectedUsers | Select-Object DisplayName, Email, UPN, AccountEnabled, Department, `
            JobTitle, LastSignIn, DaysSinceSignIn, Licenses, LicenseCount, CreatedDateTime |
            Export-Csv -Path $backupPath -NoTypeInformation -Encoding UTF8
        Write-UserLog "Backup saved" -Level "Success"
    } catch {
        Write-UserLog "Failed to save backup: $_" -Level "Error"
    }
}

# Confirm
if (-not $Force -and -not $WhatIfPreference) {
    Write-Host ""
    Write-Host "  WARNING: This will " -ForegroundColor Red -NoNewline
    if ($BlockOnly) {
        Write-Host "BLOCK and REMOVE LICENSES from" -ForegroundColor Yellow -NoNewline
    } else {
        Write-Host "PERMANENTLY DELETE" -ForegroundColor Red -NoNewline
    }
    Write-Host " $($selectedUsers.Count) user(s)" -ForegroundColor Red
    Write-Host ""
    $confirmation = Read-Host "  Type 'YES' to confirm"

    if ($confirmation -ne "YES") {
        Write-UserLog "Operation cancelled" -Level "Info"
        Disconnect-MgGraph | Out-Null
        exit 0
    }
}

# Process removals
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Red
Write-Host "Processing Users" -ForegroundColor Red
Write-Host ("=" * 80) -ForegroundColor Red

$results = @()
$successCount = 0
$failCount = 0
$licensesReclaimed = 0

foreach ($u in $selectedUsers) {
    $result = Remove-UserWithCleanup `
        -UserInfo $u `
        -Skus $subscribedSkus `
        -SkipGroups $SkipGroupRemoval `
        -SkipTokens $SkipTokenRevocation `
        -BlockOnly $BlockOnly `
        -IsWhatIf $WhatIfPreference

    $results += $result

    if ($result.Success) {
        $successCount++
        if ($u.LicenseCount -gt 0) {
            $licensesReclaimed += $u.LicenseCount
        }
    } else {
        $failCount++
    }
}

# Save removal log
$logPath = "UserRemoval_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$logEntries = @()

foreach ($result in $results) {
    $logEntries += [PSCustomObject]@{
        Timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Email       = $result.Email
        DisplayName = $result.DisplayName
        Actions     = ($result.Actions -join "; ")
        Success     = $result.Success
        Error       = $result.Error
        RemovedBy   = (Get-MgContext).Account
    }
}

$logEntries | Export-Csv -Path $logPath -NoTypeInformation -Encoding UTF8

# Final summary
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

if ($WhatIfPreference) {
    Write-Host "  [WHATIF MODE] No changes were made" -ForegroundColor Yellow
    Write-Host "  Would have processed: $($selectedUsers.Count) user(s)" -ForegroundColor Gray
} else {
    Write-Host "  Successfully processed: $successCount" -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host "  Failed: $failCount" -ForegroundColor Red
    }
    Write-Host "  Licenses reclaimed:     $licensesReclaimed" -ForegroundColor Magenta
}

Write-Host ""
Write-Host "  Removal log: $logPath" -ForegroundColor Gray
if ($BackupBeforeDelete) {
    Write-Host "  Backup file: $backupPath" -ForegroundColor Gray
}

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-UserLog "Operation completed" -Level "Success"
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

# Disconnect
Disconnect-MgGraph | Out-Null

#endregion
