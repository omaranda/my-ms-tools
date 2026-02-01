# 🔐 Microsoft 365 Persistent Authentication

## 📖 Overview

This directory contains scripts and documentation for establishing **persistent, non-interactive authentication** to Microsoft 365 services. These tools eliminate the need for repeated browser-based authentication when running PowerShell automation scripts, making them suitable for scheduled tasks, CI/CD pipelines, and long-running automation workflows.

## ⚡ Key Benefits

- **Certificate-Based Authentication** - Fully automated, non-interactive authentication using Azure AD service principals
- **Token Caching** - Interactive mode with intelligent token reuse (authenticate once, reuse for days)
- **Multi-Service Support** - Single authentication script for Microsoft Graph, Exchange Online, Azure, and SharePoint
- **Connection Reuse** - Automatically detects existing connections to prevent unnecessary re-authentication
- **Configuration Management** - Centralized configuration file for easy credential management
- **Cross-Platform** - Works on Windows, macOS, and Linux with PowerShell 7+

## 📋 Authentication Methods

### Method 1: Certificate-Based (Recommended for Automation)

**Best for:**
- Scheduled tasks and automation workflows
- CI/CD pipelines
- Unattended script execution
- Production environments

**Advantages:**
- Fully non-interactive
- No browser prompts
- Secure certificate-based authentication
- Long-term credential storage
- Works in headless environments

**Requirements:**
- Azure AD App Registration
- Self-signed certificate (or CA-issued)
- Application API permissions (not delegated)
- Admin consent granted

### Method 2: Interactive with Token Caching (Default)

**Best for:**
- Development and testing
- Administrative tasks
- Scripts run manually by administrators
- Environments where browser access is available

**Advantages:**
- Simple setup - no app registration needed initially
- Uses existing user credentials
- Token automatically cached and reused
- Browser prompt only when token expires
- Supports MFA

**Requirements:**
- User account with appropriate permissions
- Browser access for initial authentication
- Delegated API permissions

## 🚀 Quick Start

### Interactive Authentication (Simplest)

```powershell
# Connect to all services (Microsoft Graph, Exchange Online, Azure)
./Connect-M365Persistent.ps1

# Connect to specific services only
./Connect-M365Persistent.ps1 -Modules MgGraph, ExchangeOnline

# Force re-authentication (clear cached tokens)
./Connect-M365Persistent.ps1 -Force
```

The first time you run this, you'll see a browser prompt. After authentication, the token is cached and reused for subsequent runs until it expires (typically 1-2 hours for the session, but refresh tokens can last days).

### Certificate-Based Authentication (Production)

**Step 1: Generate Certificate**

```powershell
# Generate certificate and configuration
./New-M365AuthCertificate.ps1 -TenantId "12345678-1234-1234-1234-123456789012" `
    -Organization "contoso.onmicrosoft.com"
```

**Step 2: Complete Azure AD Setup**

Follow the detailed instructions printed by the script:
1. Create Azure AD App Registration (or use existing)
2. Upload the generated certificate (.cer file)
3. Grant required API permissions
4. Grant admin consent
5. Configure Exchange Online access

**Step 3: Use Certificate Authentication**

```powershell
# Connect using certificate (reads from ~/.ms-tools/auth-config.json)
./Connect-M365Persistent.ps1 -UseCertificate

# Or specify parameters explicitly
./Connect-M365Persistent.ps1 -UseCertificate `
    -TenantId "12345678-1234-1234-1234-123456789012" `
    -ClientId "87654321-4321-4321-4321-210987654321" `
    -CertificateThumbprint "A1B2C3D4E5F6..." `
    -Organization "contoso.onmicrosoft.com"
```

## 📊 Using in Your Scripts

### Pattern 1: Simple Usage

Add this to the beginning of any automation script:

```powershell
# Ensure authenticated connection to M365 services
& "$PSScriptRoot/../Auth/Connect-M365Persistent.ps1"

# Now use Microsoft Graph, Exchange Online, or Azure cmdlets
$users = Get-MgUser -All
$mailboxes = Get-Mailbox -ResultSize Unlimited
```

### Pattern 2: Certificate-Based for Scheduled Tasks

```powershell
# For unattended automation (scheduled tasks, CI/CD)
& "$PSScriptRoot/../Auth/Connect-M365Persistent.ps1" -UseCertificate

# Continue with automation
$users = Get-MgUser -All
# ... rest of your script
```

### Pattern 3: Check Connection Status

```powershell
# Connect if needed
& "$PSScriptRoot/../Auth/Connect-M365Persistent.ps1"

# Check which services are connected
if ($Global:M365Connected.MgGraph) {
    Write-Host "✓ Microsoft Graph is connected" -ForegroundColor Green
}

# Access connection metadata
Write-Host "Auth Method: $($Global:M365Connected.AuthMethod)"
Write-Host "Connected At: $($Global:M365Connected.ConnectedAt)"
```

### Pattern 4: Selective Module Connection

```powershell
# Only connect to services you need (faster)
& "$PSScriptRoot/../Auth/Connect-M365Persistent.ps1" -Modules MgGraph

# Now only Microsoft Graph is available
Get-MgUser -UserId "user@contoso.com"
```

## 🛡️ Azure AD App Registration Setup

### Required API Permissions

When setting up your Azure AD app registration for certificate-based authentication, grant these **Application permissions** (not Delegated):

#### Microsoft Graph API

| Permission | Purpose |
|------------|---------|
| `User.Read.All` | Read user profiles and properties |
| `Group.Read.All` | Read group memberships and properties |
| `Directory.Read.All` | Read directory data (users, groups, devices) |
| `DeviceManagementManagedDevices.Read.All` | Read Intune managed devices |
| `Reports.Read.All` | Read usage reports and activity logs |
| `AuditLog.Read.All` | Read audit logs and sign-in logs |
| `Organization.Read.All` | Read organization settings |
| `Team.ReadBasic.All` | Read Teams basic information |
| `GroupMember.Read.All` | Read group memberships |
| `Device.Read.All` | Read device information |

#### Exchange Online

| Permission | Purpose |
|------------|---------|
| `Exchange.ManageAsApp` | Access Exchange Online mailboxes as app |

**Additional Configuration Required:**
After granting the permission, configure service principal access:

```powershell
# Connect as Exchange admin
Connect-ExchangeOnline

# Grant app access to Exchange
New-ServicePrincipal -AppId "<YourClientId>" -ServiceId "<AppObjectId>"
```

#### SharePoint Online (Optional)

| Permission | Purpose |
|------------|---------|
| `Sites.FullControl.All` | Full control of SharePoint sites (if using SharePoint automation) |

### Step-by-Step App Registration

1. **Create App Registration**
   - Navigate to: [Azure Portal](https://portal.azure.com) > Azure Active Directory > App registrations
   - Click "New registration"
   - Name: e.g., "MSToolsAuth" or "PowerShell Automation"
   - Supported account types: "Accounts in this organizational directory only"
   - Click "Register"
   - **Copy the Application (client) ID** - you'll need this

2. **Upload Certificate**
   - In your app registration: Certificates & secrets
   - Click "Upload certificate"
   - Select the `.cer` file generated by `New-M365AuthCertificate.ps1`
   - Add a description with expiration date
   - Click "Add"

3. **Grant API Permissions**
   - In your app registration: API permissions
   - Click "Add a permission"
   - Select "Microsoft Graph" > "Application permissions"
   - Add all permissions from the table above
   - Repeat for "Office 365 Exchange Online" and "SharePoint" if needed

4. **Grant Admin Consent**
   - In API permissions page: Click "Grant admin consent for [Your Organization]"
   - Confirm by clicking "Yes"
   - Verify all permissions show "Granted" with green checkmark

5. **Note Required Information**
   - Tenant ID: Azure Active Directory > Overview > Tenant ID
   - Client ID: Your app registration > Overview > Application (client) ID
   - Certificate Thumbprint: Shown in script output and in app > Certificates & secrets
   - Organization: Your tenant domain (e.g., contoso.onmicrosoft.com)

## 🔧 Configuration File Format

Location: `~/.ms-tools/auth-config.json`

```json
{
  "TenantId": "12345678-1234-1234-1234-123456789012",
  "ClientId": "87654321-4321-4321-4321-210987654321",
  "CertificateThumbprint": "A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q7R8S9T0",
  "CertificateName": "MSToolsAuth",
  "CertificatePath": "/Users/username/.ms-tools/certificates/MSToolsAuth.cer",
  "Organization": "contoso.onmicrosoft.com",
  "CreatedAt": "2026-02-01T10:30:00Z",
  "ValidUntil": "2028-02-01T10:30:00Z"
}
```

**Security Note:** This file contains sensitive information. Ensure proper file permissions:
- Windows: Only your user account should have access
- macOS/Linux: `chmod 600 ~/.ms-tools/auth-config.json`

## 🔍 Troubleshooting

### Issue: "AADSTS700016: Application not found in the directory"

**Cause:** ClientId is incorrect or app registration doesn't exist in the tenant

**Solution:**
1. Verify ClientId matches your app registration
2. Ensure you're using the correct TenantId
3. Confirm app registration exists in Azure AD

### Issue: "Certificate with thumbprint ... was not found"

**Cause:** Certificate not properly installed or incorrect thumbprint

**Solution (Windows):**
```powershell
# List certificates in CurrentUser\My store
Get-ChildItem Cert:\CurrentUser\My

# Verify your certificate exists and copy exact thumbprint
```

**Solution (macOS/Linux):**
```bash
# Verify certificate file exists
ls -la ~/.ms-tools/certificates/

# Verify thumbprint matches
openssl x509 -in ~/.ms-tools/certificates/MSToolsAuth.cer -noout -fingerprint -sha1
```

### Issue: "Insufficient privileges to complete the operation"

**Cause:** Missing API permissions or admin consent not granted

**Solution:**
1. In Azure Portal > App registrations > Your app > API permissions
2. Verify all required permissions are listed
3. Ensure "Granted for [Organization]" shows green checkmark
4. Click "Grant admin consent" if not already done
5. Wait 5-10 minutes for permissions to propagate

### Issue: Exchange Online connection fails with certificate auth

**Cause:** Service principal not configured for Exchange access

**Solution:**
```powershell
# Connect as Exchange admin
Connect-ExchangeOnline

# Get your app's Object ID from Azure Portal (Enterprise Applications > Your App > Object ID)
# Then grant access:
New-ServicePrincipal -AppId "YOUR-CLIENT-ID" -ServiceId "YOUR-OBJECT-ID"

# Assign required role (e.g., Exchange Administrator)
# Azure Portal > Roles and administrators > Exchange Administrator > Add assignments
```

### Issue: Token expired or connection fails in interactive mode

**Cause:** Cached token has expired and needs refresh

**Solution:**
```powershell
# Force re-authentication to refresh token
./Connect-M365Persistent.ps1 -Force
```

### Issue: "Connect-MgGraph: One or more errors occurred"

**Cause:** Module not installed or permission scope mismatch

**Solution:**
```powershell
# Ensure latest Microsoft.Graph modules are installed
Install-Module Microsoft.Graph -Force -AllowClobber

# Or update existing modules
Update-Module Microsoft.Graph
```

### Issue: Works on Windows but fails on macOS/Linux

**Cause:** Certificate private key not accessible or wrong format

**Solution (macOS/Linux):**
```bash
# Verify private key file permissions
ls -la ~/.ms-tools/certificates/*.key

# Should show: -r-------- (chmod 400)
chmod 400 ~/.ms-tools/certificates/MSToolsAuth.key

# Verify certificate format
openssl x509 -in ~/.ms-tools/certificates/MSToolsAuth.cer -text -noout
```

## 📝 Best Practices

### Certificate Management

1. **Rotation:** Rotate certificates every 1-2 years before expiration
2. **Validity Period:** Use shortest period that meets operational needs (default: 2 years)
3. **Private Key Security:** Never share private keys or commit to source control
4. **Backup:** Securely backup certificates and configuration files
5. **Monitoring:** Track certificate expiration dates and set renewal reminders

### Security Considerations

1. **Least Privilege:** Only grant API permissions actually needed by your scripts
2. **Audit Logging:** Enable and monitor Azure AD app sign-in logs
3. **Conditional Access:** Consider applying conditional access policies to service principals
4. **Secret Scanning:** Add `.ms-tools/` to `.gitignore` to prevent credential leaks
5. **Environment Separation:** Use different app registrations for dev/test/prod environments

### Connection Management

1. **Check Before Connect:** The script automatically checks for existing connections
2. **Service-Specific:** Only connect to services you need (`-Modules` parameter)
3. **Connection Reuse:** Use `$Global:M365Connected` to check status in scripts
4. **Graceful Handling:** Implement error handling for authentication failures
5. **Disconnection:** Explicitly disconnect when finished for security

```powershell
# Example: Proper cleanup
try {
    & ./Connect-M365Persistent.ps1 -Modules MgGraph

    # Your automation logic here
    $users = Get-MgUser -All

} finally {
    # Cleanup (optional for interactive, recommended for certificate auth)
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}
```

## 🎯 Common Workflows

### Scheduled Task Setup (Windows)

```powershell
# Create scheduled task that runs automation script
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' `
    -Argument '-File "C:\Scripts\MyAutomation.ps1"'

$trigger = New-ScheduledTaskTrigger -Daily -At 2am

Register-ScheduledTask -TaskName "M365 Daily Automation" `
    -Action $action -Trigger $trigger -User "SYSTEM"

# Inside MyAutomation.ps1:
& "C:\Scripts\Auth\Connect-M365Persistent.ps1" -UseCertificate
# ... rest of automation
```

### Cron Job Setup (macOS/Linux)

```bash
# Edit crontab
crontab -e

# Add daily automation at 2 AM
0 2 * * * /usr/local/bin/pwsh /home/user/scripts/MyAutomation.ps1

# Inside MyAutomation.ps1:
& "/home/user/scripts/Auth/Connect-M365Persistent.ps1" -UseCertificate
# ... rest of automation
```

### CI/CD Pipeline Integration

```yaml
# GitHub Actions example
- name: Authenticate to M365
  run: |
    pwsh -File ./07-Automation/Auth/Connect-M365Persistent.ps1 -UseCertificate
  env:
    TENANT_ID: ${{ secrets.TENANT_ID }}
    CLIENT_ID: ${{ secrets.CLIENT_ID }}
    CERT_THUMBPRINT: ${{ secrets.CERT_THUMBPRINT }}

- name: Run Automation
  run: |
    pwsh -File ./scripts/automation.ps1
```

## 📚 Additional Resources

- [Microsoft Graph PowerShell SDK Documentation](https://learn.microsoft.com/en-us/powershell/microsoftgraph/)
- [App-only authentication with Microsoft Graph](https://learn.microsoft.com/en-us/powershell/microsoftgraph/app-only)
- [Exchange Online App-only authentication](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2)
- [Azure AD App Registration Best Practices](https://learn.microsoft.com/en-us/azure/active-directory/develop/security-best-practices-for-app-registration)
- [Certificate-based authentication in Azure AD](https://learn.microsoft.com/en-us/azure/active-directory/authentication/concept-certificate-based-authentication)

## 🔄 Script Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `Connect-M365Persistent.ps1` | Main authentication script | Called at start of automation scripts |
| `New-M365AuthCertificate.ps1` | Certificate generation and setup | One-time setup for certificate auth |
| `README.md` | This documentation | Reference guide |

---

**Questions or Issues?** Review the troubleshooting section above or consult Microsoft's official documentation for specific authentication scenarios.
