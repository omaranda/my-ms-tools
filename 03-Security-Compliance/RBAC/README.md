# RBAC (Role-Based Access Control)

Scripts for managing Microsoft Entra ID directory role assignments, including auditing existing roles and assigning administrative access to users.

## Prerequisites

- **PowerShell 7+**
- **Microsoft Graph PowerShell SDK** modules:
  - `Microsoft.Graph.Identity.Governance`
  - `Microsoft.Graph.Users`
  - `Az.Resources` (for Azure RBAC reporting)

Install all dependencies at once:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
Install-Module Az -Scope CurrentUser -Force
```

Or run the project's dependency installer from the repo root:

```powershell
./Install-M365Dependencies.ps1
```

## Scripts

### Get-RoleAssignments.ps1

Reports on Azure RBAC role assignments across subscriptions, resource groups, or individual resources. Identifies privileged and custom roles.

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Scope` | string | all | Scope to analyze (subscription, resource group, or resource path) |
| `IncludeCustomRoles` | switch | | Include custom role definitions in the report |
| `ExportPath` | string | `RBACAssignments_yyyyMMdd_HHmmss.csv` | CSV export path |

#### Usage

```powershell
# Report all role assignments in the current subscription
.\Get-RoleAssignments.ps1

# Report assignments for a specific subscription and include custom roles
.\Get-RoleAssignments.ps1 -Scope "/subscriptions/xxxxx" -IncludeCustomRoles

# Export to a specific file
.\Get-RoleAssignments.ps1 -ExportPath "./rbac-report.csv"
```

#### Output

- Summary of assignments grouped by role name
- Highlighted privileged role assignments (Owner, Contributor, User Access Administrator, Global Administrator)
- Custom role definitions (with `-IncludeCustomRoles`)
- CSV export with full assignment details

---

### Set-BillingAccess.ps1

Assigns or removes the **Billing Administrator** role in Microsoft Entra ID, granting a user access to the Microsoft 365 billing section.

#### Billing Administrator Permissions

- Make purchases and manage subscriptions
- Manage support tickets
- Monitor service health
- View billing accounts, invoices, and payment methods

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `UserPrincipalName` | string | **(Required)** UPN of the target user (e.g., `user@contoso.com`) |
| `Remove` | switch | Remove the role instead of assigning it |
| `WhatIf` | switch | Preview the operation without making changes |

#### Usage

```powershell
# Grant billing access
.\Set-BillingAccess.ps1 -UserPrincipalName "jsmith@contoso.com"

# Preview without making changes
.\Set-BillingAccess.ps1 -UserPrincipalName "jsmith@contoso.com" -WhatIf

# Remove billing access
.\Set-BillingAccess.ps1 -UserPrincipalName "jsmith@contoso.com" -Remove
```

#### Billing Portal URL

After assignment, the user can access billing at:

```
https://admin.microsoft.com/Adminportal/Home#/BillingAccounts
```

---

### Set-GlobalAdmin.ps1

Assigns or removes the **Global Administrator** role in Microsoft Entra ID, granting a user full administrative rights across all Microsoft 365 and Azure services.

> **Warning:** Global Administrator is the highest privileged role. The script requires manual confirmation (`Type 'CONFIRM'`) before making changes.

#### Global Administrator Permissions

- Unrestricted access to all Microsoft 365 services (Exchange, SharePoint, Teams, Intune, etc.)
- Azure Active Directory / Entra ID management
- Billing and subscriptions
- Security and compliance settings
- Management of all other admin roles

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `UserPrincipalName` | string | **(Required)** UPN of the target user (e.g., `user@contoso.com`) |
| `Remove` | switch | Remove the role instead of assigning it |
| `Force` | switch | Skip the confirmation prompt |
| `WhatIf` | switch | Preview the operation without making changes |

#### Usage

```powershell
# Assign Global Administrator (will prompt for confirmation)
.\Set-GlobalAdmin.ps1 -UserPrincipalName "jsmith@contoso.com"

# Preview without making changes
.\Set-GlobalAdmin.ps1 -UserPrincipalName "jsmith@contoso.com" -WhatIf

# Skip confirmation prompt
.\Set-GlobalAdmin.ps1 -UserPrincipalName "jsmith@contoso.com" -Force

# Remove Global Administrator role
.\Set-GlobalAdmin.ps1 -UserPrincipalName "jsmith@contoso.com" -Remove
```

#### Admin Portal URLs

After assignment, the user can access all admin portals:

| Portal | URL |
|--------|-----|
| Admin Center | https://admin.microsoft.com |
| Entra ID | https://entra.microsoft.com |
| Azure Portal | https://portal.azure.com |
| Security Center | https://security.microsoft.com |
| Compliance | https://compliance.microsoft.com |

## Required Graph API Permissions

| Permission | Used By |
|------------|---------|
| `RoleManagement.ReadWrite.Directory` | Set-BillingAccess, Set-GlobalAdmin |
| `User.Read.All` | Set-BillingAccess, Set-GlobalAdmin |

## Entra ID Built-in Role Reference

| Role | Template ID |
|------|-------------|
| Global Administrator | `62e90394-69f5-4237-9190-012177145e10` |
| Billing Administrator | `b0f54661-2d74-4c50-afa3-1ec803f12efe` |
| User Administrator | `fe930be7-5e62-47db-91af-98c3a49a38b1` |
| Exchange Administrator | `29232cdf-9323-42fd-ade2-1d097af3e4de` |
| SharePoint Administrator | `f28a1f50-f6e7-4571-818b-6a12f2af6b6c` |
| Teams Administrator | `69091246-20e8-4a56-aa4d-066075b2a7a8` |
| Security Administrator | `194ae4cb-b126-40b2-bd5b-6091b380977d` |
| Compliance Administrator | `17315797-102d-40b4-93e0-432062caca18` |
| Intune Administrator | `3a2c62db-5318-420d-8d74-23affee5d9d5` |
| Helpdesk Administrator | `729827e3-9c14-49f7-bb1b-9608f156bbb8` |

These template IDs are consistent across all Microsoft 365 tenants and can be used to extend the scripts for additional role assignments.
