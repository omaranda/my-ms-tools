# License Management

Scripts for managing Microsoft 365 license assignment, auditing, and cleanup across your tenant.

## Prerequisites

- **PowerShell 7+**
- **Microsoft Graph PowerShell SDK** modules:
  - `Microsoft.Graph.Authentication`
  - `Microsoft.Graph.Users`
  - `Microsoft.Graph.Identity.DirectoryManagement`

Install all dependencies at once:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

Or run the project's dependency installer from the repo root:

```powershell
./Install-M365Dependencies.ps1
```

## Scripts

### Set-M365Licenses.ps1

Automates Microsoft 365 license assignment and management. Supports bulk operations via CSV import or department-based assignment.

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `CSVPath` | string | Path to CSV file with columns: `UserPrincipalName`, `LicenseSKU`, `Action` (Add/Remove) |
| `LicenseSKU` | string | License SKU to assign (e.g., `SPE_E3`, `SPE_E5`, `O365_BUSINESS_PREMIUM`) |
| `Department` | string | Assign the specified license to all users in this department |

#### Usage

```powershell
# Bulk assign/remove licenses from a CSV file
.\Set-M365Licenses.ps1 -CSVPath "licenses.csv"

# Assign E3 licenses to everyone in the IT department
.\Set-M365Licenses.ps1 -LicenseSKU "SPE_E3" -Department "IT"
```

#### CSV Format

```csv
UserPrincipalName,LicenseSKU,Action
john@contoso.com,SPE_E3,Add
jane@contoso.com,O365_BUSINESS_PREMIUM,Remove
```

#### Output

- Displays available licenses with quantities before processing
- Color-coded results (green = success, red = error)
- Exports results to `LicenseAssignment_yyyyMMdd_HHmmss.csv`

---

### Remove-UnusedLicenses.ps1

Identifies and reclaims unused Microsoft 365 licenses by finding disabled accounts, inactive users, and users who never signed in.

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ListOnly` | switch | default mode | Show license usage report without making changes |
| `ShowInactiveUsers` | switch | | Display inactive user details |
| `InactiveDays` | int | 90 | Number of days without sign-in to consider a user inactive |
| `RemoveFromInactive` | switch | | Remove licenses from inactive users |
| `RemoveFromDisabled` | switch | | Remove licenses from disabled accounts |
| `SkuPartNumber` | string | | Filter by specific license SKU (e.g., `O365_BUSINESS_PREMIUM`) |
| `ExportPath` | string | | Export the full user report to CSV |
| `Interactive` | switch | | Interactive mode with numbered menu to select users |
| `WhatIf` | switch | | Preview what would happen without making changes |
| `Force` | switch | | Skip confirmation prompts |

#### Usage

```powershell
# View license usage summary (safe, read-only)
.\Remove-UnusedLicenses.ps1 -ListOnly

# Show users who haven't signed in for 90+ days
.\Remove-UnusedLicenses.ps1 -ShowInactiveUsers -InactiveDays 90

# Preview removing licenses from disabled accounts (no changes applied)
.\Remove-UnusedLicenses.ps1 -RemoveFromDisabled -WhatIf

# Remove Business Premium licenses from users inactive for 180+ days
.\Remove-UnusedLicenses.ps1 -RemoveFromInactive -InactiveDays 180 -SkuPartNumber "O365_BUSINESS_PREMIUM"

# Interactive mode: manually pick which users to clean up
.\Remove-UnusedLicenses.ps1 -Interactive

# Export full license report to CSV for review
.\Remove-UnusedLicenses.ps1 -ListOnly -ExportPath "./license-report.csv"
```

#### What It Detects

| Category | Description |
|----------|-------------|
| Disabled accounts | Accounts that are disabled but still have licenses assigned |
| Inactive users | Users who haven't signed in for the specified number of days |
| Never signed in | Users who were created but have never logged in |

#### Output

- On-screen license summary with assigned vs. available counts per SKU
- Potential license recovery count
- Removal log exported to `LicenseRemoval_yyyyMMdd_HHmmss.csv` with timestamp, user, action, and status

## Supported License SKUs

Both scripts recognize the following SKU identifiers with friendly names:

| SKU Part Number | Friendly Name |
|-----------------|---------------|
| `O365_BUSINESS_PREMIUM` | Microsoft 365 Business Premium |
| `O365_BUSINESS_ESSENTIALS` | Microsoft 365 Business Basic |
| `O365_BUSINESS` | Microsoft 365 Apps for Business |
| `SPE_E3` | Microsoft 365 E3 |
| `SPE_E5` | Microsoft 365 E5 |
| `ENTERPRISEPACK` | Office 365 E3 |
| `ENTERPRISEPREMIUM` | Office 365 E5 |
| `STANDARDPACK` | Office 365 E1 |
| `EXCHANGESTANDARD` | Exchange Online Plan 1 |
| `EXCHANGEENTERPRISE` | Exchange Online Plan 2 |
| `POWER_BI_PRO` | Power BI Pro |
| `PROJECTPROFESSIONAL` | Project Plan 3 |
| `VISIOCLIENT` | Visio Plan 2 |
| `AAD_PREMIUM` | Azure AD Premium P1 |
| `AAD_PREMIUM_P2` | Azure AD Premium P2 |
| `EMS` | Enterprise Mobility + Security E3 |
| `EMSPREMIUM` | Enterprise Mobility + Security E5 |
| `INTUNE_A` | Intune |
| `ATP_ENTERPRISE` | Microsoft Defender for Office 365 P1 |
| `THREAT_INTELLIGENCE` | Microsoft Defender for Office 365 P2 |

## Required Graph API Permissions

| Permission | Used By |
|------------|---------|
| `User.ReadWrite.All` | Both scripts (read users, modify licenses) |
| `Organization.Read.All` | Both scripts (read subscribed SKUs) |
| `Directory.ReadWrite.All` | Remove-UnusedLicenses (directory operations) |
| `AuditLog.Read.All` | Remove-UnusedLicenses (sign-in activity data) |

## Typical Workflow

1. **Audit** - Run `Remove-UnusedLicenses.ps1 -ListOnly` to see current license usage
2. **Identify waste** - Use `-ShowInactiveUsers -InactiveDays 90` to find candidates
3. **Export** - Save the report with `-ExportPath "./report.csv"` for review
4. **Preview** - Use `-RemoveFromDisabled -WhatIf` to see what would change
5. **Clean up** - Run without `-WhatIf` to reclaim licenses
6. **Reassign** - Use `Set-M365Licenses.ps1` to assign reclaimed licenses to new users
