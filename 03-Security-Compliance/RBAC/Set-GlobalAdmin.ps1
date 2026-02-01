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
    Assigns the Global Administrator role to a user in Microsoft Entra ID.

.DESCRIPTION
    Grants a user full administrative rights across Microsoft 365 and Azure
    by assigning the Global Administrator directory role via Microsoft Graph API.

    WARNING: Global Administrator is the highest privileged role. The assigned
    user will have unrestricted access to all administration features including:
    - All Microsoft 365 services (Exchange, SharePoint, Teams, Intune, etc.)
    - Azure Active Directory / Entra ID management
    - Billing and subscriptions
    - Security and compliance settings
    - All other admin roles management

    This operation requires explicit confirmation due to its security impact.

    After assignment, the user can access the admin center at:
    https://admin.microsoft.com

.PARAMETER UserPrincipalName
    The UPN of the user to grant Global Administrator rights (e.g., user@contoso.com)

.PARAMETER Remove
    Remove the Global Administrator role instead of assigning it

.PARAMETER Force
    Skip the confirmation prompt (use with caution)

.PARAMETER WhatIf
    Preview the operation without making changes

.EXAMPLE
    .\Set-GlobalAdmin.ps1 -UserPrincipalName "jsmith@contoso.com"

.EXAMPLE
    .\Set-GlobalAdmin.ps1 -UserPrincipalName "jsmith@contoso.com" -Remove

.EXAMPLE
    .\Set-GlobalAdmin.ps1 -UserPrincipalName "jsmith@contoso.com" -WhatIf

.EXAMPLE
    .\Set-GlobalAdmin.ps1 -UserPrincipalName "jsmith@contoso.com" -Force
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory=$false)]
    [switch]$Remove,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Import required modules
Import-Module Microsoft.Graph.Identity.Governance
Import-Module Microsoft.Graph.Users

# Connect to Microsoft Graph
$requiredScopes = @("RoleManagement.ReadWrite.Directory", "User.Read.All")
Connect-MgGraph -Scopes $requiredScopes

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "  Microsoft 365 Global Administrator Management" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan

# Global Administrator role template ID (fixed across all tenants)
$globalAdminRoleId = "62e90394-69f5-4237-9190-012177145e10"

# Verify the user exists
Write-Host "`nLooking up user: $UserPrincipalName" -ForegroundColor White
try {
    $user = Get-MgUser -UserId $UserPrincipalName -ErrorAction Stop
    Write-Host "  Found: $($user.DisplayName) ($($user.UserPrincipalName))" -ForegroundColor Green
} catch {
    Write-Host "  User not found: $UserPrincipalName" -ForegroundColor Red
    Disconnect-MgGraph
    exit 1
}

# Get the Global Administrator role definition
$globalRole = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $globalAdminRoleId
Write-Host "  Role: $($globalRole.DisplayName)" -ForegroundColor White

# Check current assignment
$existingAssignment = Get-MgRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$($user.Id)' and roleDefinitionId eq '$globalAdminRoleId'"

if ($Remove) {
    # Remove the role assignment
    if (-not $existingAssignment) {
        Write-Host "`n  User does not have the Global Administrator role." -ForegroundColor Yellow
        Disconnect-MgGraph
        exit 0
    }

    Write-Host ""
    Write-Host "  WARNING: You are about to REMOVE Global Administrator rights from:" -ForegroundColor Red
    Write-Host "  $($user.DisplayName) ($($user.UserPrincipalName))" -ForegroundColor White
    Write-Host ""

    if (-not $Force) {
        $confirm = Read-Host "  Type 'CONFIRM' to proceed"
        if ($confirm -ne "CONFIRM") {
            Write-Host "`n  Operation cancelled." -ForegroundColor Yellow
            Disconnect-MgGraph
            exit 0
        }
    }

    if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Remove Global Administrator role")) {
        try {
            Remove-MgRoleManagementDirectoryRoleAssignment -UnifiedRoleAssignmentId $existingAssignment.Id
            Write-Host "`n  Global Administrator role removed from $($user.DisplayName)" -ForegroundColor Green
        } catch {
            Write-Host "`n  Failed to remove role: $($_.Exception.Message)" -ForegroundColor Red
            Disconnect-MgGraph
            exit 1
        }
    }
} else {
    # Assign the role
    if ($existingAssignment) {
        Write-Host "`n  User already has the Global Administrator role." -ForegroundColor Yellow
        Write-Host "`n  Admin Center URL:" -ForegroundColor Cyan
        Write-Host "  https://admin.microsoft.com" -ForegroundColor White
        Disconnect-MgGraph
        exit 0
    }

    Write-Host ""
    Write-Host "  " + "!" * 70 -ForegroundColor Red
    Write-Host "  WARNING: Global Administrator is the HIGHEST privileged role." -ForegroundColor Red
    Write-Host "  The user will have UNRESTRICTED access to ALL admin features." -ForegroundColor Red
    Write-Host "  " + "!" * 70 -ForegroundColor Red
    Write-Host ""
    Write-Host "  User: $($user.DisplayName) ($($user.UserPrincipalName))" -ForegroundColor White
    Write-Host ""

    if (-not $Force) {
        $confirm = Read-Host "  Type 'CONFIRM' to proceed with Global Administrator assignment"
        if ($confirm -ne "CONFIRM") {
            Write-Host "`n  Operation cancelled." -ForegroundColor Yellow
            Disconnect-MgGraph
            exit 0
        }
    }

    if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Assign Global Administrator role")) {
        try {
            $params = @{
                PrincipalId      = $user.Id
                RoleDefinitionId = $globalAdminRoleId
                DirectoryScopeId = "/"
            }
            New-MgRoleManagementDirectoryRoleAssignment -BodyParameter $params

            Write-Host "`n  Global Administrator role assigned to $($user.DisplayName)" -ForegroundColor Green
        } catch {
            Write-Host "`n  Failed to assign role: $($_.Exception.Message)" -ForegroundColor Red
            Disconnect-MgGraph
            exit 1
        }
    }
}

# Display access details
Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "  Admin Access Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""
Write-Host "  User:  $($user.DisplayName) ($($user.UserPrincipalName))" -ForegroundColor White
Write-Host "  Role:  Global Administrator" -ForegroundColor White
Write-Host ""
Write-Host "  Admin Center:     https://admin.microsoft.com" -ForegroundColor Green
Write-Host "  Entra ID:         https://entra.microsoft.com" -ForegroundColor Green
Write-Host "  Azure Portal:     https://portal.azure.com" -ForegroundColor Green
Write-Host "  Security Center:  https://security.microsoft.com" -ForegroundColor Green
Write-Host "  Compliance:       https://compliance.microsoft.com" -ForegroundColor Green
Write-Host ""

Disconnect-MgGraph
