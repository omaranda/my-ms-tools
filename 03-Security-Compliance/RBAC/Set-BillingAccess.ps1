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
    Assigns the Billing Administrator role to a user in Microsoft Entra ID.

.DESCRIPTION
    Grants a user access to the Microsoft 365 Billing section by assigning
    the Billing Administrator directory role via Microsoft Graph API.

    The Billing Administrator role allows users to:
    - Make purchases and manage subscriptions
    - Manage support tickets
    - Monitor service health
    - View billing accounts, invoices, and payment methods

    After assignment, the user can access billing at:
    https://admin.microsoft.com/Adminportal/Home#/BillingAccounts

.PARAMETER UserPrincipalName
    The UPN of the user to grant billing access (e.g., user@contoso.com)

.PARAMETER Remove
    Remove the Billing Administrator role instead of assigning it

.PARAMETER WhatIf
    Preview the operation without making changes

.EXAMPLE
    .\Set-BillingAccess.ps1 -UserPrincipalName "jsmith@contoso.com"

.EXAMPLE
    .\Set-BillingAccess.ps1 -UserPrincipalName "jsmith@contoso.com" -Remove

.EXAMPLE
    .\Set-BillingAccess.ps1 -UserPrincipalName "jsmith@contoso.com" -WhatIf
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory=$false)]
    [switch]$Remove
)

# Import required modules
Import-Module Microsoft.Graph.Identity.Governance
Import-Module Microsoft.Graph.Users

# Connect to Microsoft Graph
$requiredScopes = @("RoleManagement.ReadWrite.Directory", "User.Read.All")
Connect-MgGraph -Scopes $requiredScopes

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "  Microsoft 365 Billing Access Management" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan

# Billing Administrator role template ID (fixed across all tenants)
$billingAdminRoleId = "b0f54661-2d74-4c50-afa3-1ec803f12efe"

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

# Get the Billing Administrator role definition
$billingRole = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $billingAdminRoleId
Write-Host "  Role: $($billingRole.DisplayName)" -ForegroundColor White

# Check current assignment
$existingAssignment = Get-MgRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$($user.Id)' and roleDefinitionId eq '$billingAdminRoleId'"

if ($Remove) {
    # Remove the role assignment
    if (-not $existingAssignment) {
        Write-Host "`n  User does not have the Billing Administrator role." -ForegroundColor Yellow
        Disconnect-MgGraph
        exit 0
    }

    if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Remove Billing Administrator role")) {
        try {
            Remove-MgRoleManagementDirectoryRoleAssignment -UnifiedRoleAssignmentId $existingAssignment.Id
            Write-Host "`n  Billing Administrator role removed from $($user.DisplayName)" -ForegroundColor Green
        } catch {
            Write-Host "`n  Failed to remove role: $($_.Exception.Message)" -ForegroundColor Red
            Disconnect-MgGraph
            exit 1
        }
    }
} else {
    # Assign the role
    if ($existingAssignment) {
        Write-Host "`n  User already has the Billing Administrator role." -ForegroundColor Yellow
        Write-Host "`n  Billing Portal URL:" -ForegroundColor Cyan
        Write-Host "  https://admin.microsoft.com/Adminportal/Home#/BillingAccounts" -ForegroundColor White
        Disconnect-MgGraph
        exit 0
    }

    if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Assign Billing Administrator role")) {
        try {
            $params = @{
                PrincipalId      = $user.Id
                RoleDefinitionId = $billingAdminRoleId
                DirectoryScopeId = "/"
            }
            New-MgRoleManagementDirectoryRoleAssignment -BodyParameter $params

            Write-Host "`n  Billing Administrator role assigned to $($user.DisplayName)" -ForegroundColor Green
        } catch {
            Write-Host "`n  Failed to assign role: $($_.Exception.Message)" -ForegroundColor Red
            Disconnect-MgGraph
            exit 1
        }
    }
}

# Display access details
Write-Host "`n" + "=" * 80 -ForegroundColor Cyan
Write-Host "  Billing Portal Access" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "`n  User:  $($user.DisplayName) ($($user.UserPrincipalName))" -ForegroundColor White
Write-Host "  Role:  Billing Administrator" -ForegroundColor White
Write-Host "`n  URL:   https://admin.microsoft.com/Adminportal/Home#/BillingAccounts" -ForegroundColor Green
Write-Host "`n  The user can now sign in and access billing at the URL above." -ForegroundColor White
Write-Host ""

Disconnect-MgGraph
