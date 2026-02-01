<#
.SYNOPSIS
    Generates a self-signed certificate for Microsoft 365 service principal authentication.

.DESCRIPTION
    New-M365AuthCertificate.ps1 creates a self-signed certificate for use with Azure AD application
    authentication (app-only/service principal authentication). This enables non-interactive,
    certificate-based authentication for PowerShell automation scripts.

    The script performs the following actions:
    1. Generates a self-signed X.509 certificate with specified validity period
    2. Exports the public key (.cer file) for uploading to Azure AD
    3. Stores the private key securely in the certificate store (Windows) or keychain (macOS)
    4. Creates/updates authentication configuration file at ~/.ms-tools/auth-config.json
    5. Provides step-by-step instructions for Azure AD app registration setup

    Platform Support:
    - Windows: Uses New-SelfSignedCertificate cmdlet
    - macOS/Linux: Uses openssl for certificate generation

    After running this script, follow the printed instructions to complete Azure AD setup.

.PARAMETER TenantId
    Azure AD Tenant ID (GUID format). This is required to save in the configuration file.
    Find this in Azure Portal > Azure Active Directory > Overview > Tenant ID

.PARAMETER ClientId
    Azure AD Application (Client) ID. If you have an existing app registration, provide its ID.
    If not provided, the script will guide you to create one.

.PARAMETER CertificateName
    Friendly name for the certificate. This name will be used for:
    - Certificate subject (CN=<CertificateName>)
    - Certificate file names
    Default: MSToolsAuth

.PARAMETER ValidityYears
    Number of years the certificate should be valid.
    Default: 2 years
    Maximum recommended: 3 years (align with organizational security policies)

.PARAMETER Organization
    Organization domain for Exchange Online (e.g., contoso.onmicrosoft.com).
    Required for Exchange Online certificate-based authentication.

.PARAMETER OutputPath
    Directory path where certificate files will be saved.
    Default: ~/.ms-tools/certificates/

.EXAMPLE
    .\New-M365AuthCertificate.ps1 -TenantId "12345678-1234-1234-1234-123456789012"

    Generates a certificate named "MSToolsAuth" valid for 2 years and saves configuration.
    Prompts for Organization domain if needed.

.EXAMPLE
    .\New-M365AuthCertificate.ps1 -TenantId "12345678-1234-1234-1234-123456789012" `
        -ClientId "87654321-4321-4321-4321-210987654321" -Organization "contoso.onmicrosoft.com" `
        -CertificateName "ContosoAutomation" -ValidityYears 3

    Generates a certificate for an existing app registration with 3-year validity.

.EXAMPLE
    .\New-M365AuthCertificate.ps1 -TenantId "12345678-1234-1234-1234-123456789012" `
        -OutputPath "/custom/path/certificates"

    Generates a certificate and saves files to a custom directory.

.NOTES
    Author: Microsoft 365 Tools Team
    Version: 1.0.0
    Date: 2026-02-01

    Prerequisites:
    - PowerShell 7+ (cross-platform)
    - Azure AD tenant with administrative access
    - Windows: Administrator privileges (for certificate store access)
    - macOS/Linux: openssl installed

    Required Azure AD Permissions (to be configured manually):
    Application Permissions (not Delegated):
    - Microsoft Graph API:
      * User.Read.All
      * Group.Read.All
      * Directory.Read.All
      * DeviceManagementManagedDevices.Read.All
      * Reports.Read.All
      * AuditLog.Read.All
      * Organization.Read.All
      * Team.ReadBasic.All
    - Exchange Online:
      * Exchange.ManageAsApp
    - SharePoint:
      * Sites.FullControl.All (if using SharePoint automation)

    Security Considerations:
    - Certificate private key is stored securely in OS certificate store/keychain
    - Never share the private key or .pfx file
    - Rotate certificates before expiration
    - Use shortest validity period that meets operational needs
    - Audit app registration activity regularly

.LINK
    https://learn.microsoft.com/en-us/powershell/microsoftgraph/app-only
    https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$CertificateName = "MSToolsAuth",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 5)]
    [int]$ValidityYears = 2,

    [Parameter(Mandatory = $false)]
    [string]$Organization,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path $HOME ".ms-tools/certificates")
)

# ============================================================================
# INITIALIZATION
# ============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Microsoft 365 Authentication Certificate Generator" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$isWindows = $PSVersionTable.Platform -eq 'Win32NT' -or $PSVersionTable.PSVersion.Major -le 5
$isMacOS = $PSVersionTable.Platform -eq 'Unix' -and $IsMacOS
$isLinux = $PSVersionTable.Platform -eq 'Unix' -and -not $IsMacOS

Write-Host "Platform Detected: " -NoNewline
if ($isWindows) { Write-Host "Windows" -ForegroundColor Green }
elseif ($isMacOS) { Write-Host "macOS" -ForegroundColor Green }
elseif ($isLinux) { Write-Host "Linux" -ForegroundColor Green }
Write-Host ""

# ============================================================================
# CREATE OUTPUT DIRECTORY
# ============================================================================

$configDir = Join-Path $HOME ".ms-tools"
$configFile = Join-Path $configDir "auth-config.json"

if (-not (Test-Path $OutputPath)) {
    Write-Host "Creating output directory: $OutputPath" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-Host "✓ Directory created" -ForegroundColor Green
    Write-Host ""
}

if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

# ============================================================================
# CERTIFICATE PARAMETERS
# ============================================================================

$certSubject = "CN=$CertificateName"
$notAfter = (Get-Date).AddYears($ValidityYears)
$certPath = Join-Path $OutputPath "$CertificateName.cer"
$pfxPath = Join-Path $OutputPath "$CertificateName.pfx"

Write-Host "Certificate Configuration:" -ForegroundColor Cyan
Write-Host "  Name: $CertificateName" -ForegroundColor White
Write-Host "  Subject: $certSubject" -ForegroundColor White
Write-Host "  Validity: $ValidityYears years (until $($notAfter.ToString('yyyy-MM-dd')))" -ForegroundColor White
Write-Host "  Output Path: $OutputPath" -ForegroundColor White
Write-Host ""

# ============================================================================
# GENERATE CERTIFICATE (WINDOWS)
# ============================================================================

if ($isWindows) {
    Write-Host "Generating certificate using New-SelfSignedCertificate..." -ForegroundColor Cyan

    try {
        # Create self-signed certificate
        $cert = New-SelfSignedCertificate -Subject $certSubject `
            -CertStoreLocation "Cert:\CurrentUser\My" `
            -KeyExportPolicy Exportable `
            -KeySpec Signature `
            -KeyLength 2048 `
            -KeyAlgorithm RSA `
            -HashAlgorithm SHA256 `
            -NotAfter $notAfter `
            -ErrorAction Stop

        $thumbprint = $cert.Thumbprint
        Write-Host "✓ Certificate generated successfully" -ForegroundColor Green
        Write-Host "  Thumbprint: $thumbprint" -ForegroundColor White
        Write-Host ""

        # Export public key (.cer)
        Write-Host "Exporting public key (.cer)..." -ForegroundColor Cyan
        Export-Certificate -Cert $cert -FilePath $certPath -Type CERT | Out-Null
        Write-Host "✓ Public key exported: $certPath" -ForegroundColor Green
        Write-Host ""

        # Optionally export PFX (private key) with password protection
        Write-Host "⚠ Private key stored in Certificate Store: Cert:\CurrentUser\My\$thumbprint" -ForegroundColor Yellow
        Write-Host "  Do NOT share the private key or delete from certificate store" -ForegroundColor Yellow
        Write-Host ""

    }
    catch {
        Write-Host "✗ Failed to generate certificate: $_" -ForegroundColor Red
        exit 1
    }
}

# ============================================================================
# GENERATE CERTIFICATE (macOS/Linux using OpenSSL)
# ============================================================================

else {
    Write-Host "Generating certificate using OpenSSL..." -ForegroundColor Cyan

    # Check if openssl is installed
    $opensslExists = Get-Command openssl -ErrorAction SilentlyContinue
    if (-not $opensslExists) {
        Write-Host "✗ Error: OpenSSL is not installed or not in PATH" -ForegroundColor Red
        Write-Host ""
        if ($isMacOS) {
            Write-Host "Install OpenSSL using Homebrew:" -ForegroundColor Yellow
            Write-Host "  brew install openssl" -ForegroundColor White
        }
        else {
            Write-Host "Install OpenSSL using your package manager:" -ForegroundColor Yellow
            Write-Host "  sudo apt-get install openssl (Debian/Ubuntu)" -ForegroundColor White
            Write-Host "  sudo yum install openssl (RHEL/CentOS)" -ForegroundColor White
        }
        exit 1
    }

    try {
        $keyPath = Join-Path $OutputPath "$CertificateName.key"
        $csrPath = Join-Path $OutputPath "$CertificateName.csr"
        $validityDays = $ValidityYears * 365

        # Generate private key
        Write-Host "Generating RSA private key (2048-bit)..." -ForegroundColor Cyan
        & openssl genrsa -out $keyPath 2048 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to generate private key" }
        Write-Host "✓ Private key generated: $keyPath" -ForegroundColor Green

        # Generate certificate signing request (CSR)
        Write-Host "Generating certificate signing request..." -ForegroundColor Cyan
        & openssl req -new -key $keyPath -out $csrPath -subj "/CN=$CertificateName" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to generate CSR" }
        Write-Host "✓ CSR generated: $csrPath" -ForegroundColor Green

        # Generate self-signed certificate
        Write-Host "Generating self-signed certificate..." -ForegroundColor Cyan
        & openssl x509 -req -days $validityDays -in $csrPath -signkey $keyPath -out $certPath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to generate certificate" }
        Write-Host "✓ Certificate generated: $certPath" -ForegroundColor Green
        Write-Host ""

        # Get thumbprint (SHA-1 fingerprint)
        $thumbprintOutput = & openssl x509 -in $certPath -noout -fingerprint -sha1 2>&1
        $thumbprint = ($thumbprintOutput -replace 'SHA1 Fingerprint=', '') -replace ':', ''
        Write-Host "  Thumbprint: $thumbprint" -ForegroundColor White
        Write-Host ""

        # Create PFX (PKCS12) for easier import if needed
        Write-Host "Creating PFX file (PKCS12 format)..." -ForegroundColor Cyan
        $pfxPassword = "temp-password"  # You can prompt for this if needed
        & openssl pkcs12 -export -out $pfxPath -inkey $keyPath -in $certPath -password pass:$pfxPassword 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ PFX file created: $pfxPath (password: temp-password)" -ForegroundColor Green
            Write-Host "  ⚠ Change this password if using for production!" -ForegroundColor Yellow
        }
        Write-Host ""

        # Security reminder
        Write-Host "⚠ Private key location: $keyPath" -ForegroundColor Yellow
        Write-Host "  Do NOT share the private key file" -ForegroundColor Yellow
        Write-Host "  Protect file permissions: chmod 400 $keyPath" -ForegroundColor Yellow
        Write-Host ""

        # Set restrictive permissions on private key
        if ($isMacOS -or $isLinux) {
            & chmod 400 $keyPath
        }

    }
    catch {
        Write-Host "✗ Failed to generate certificate: $_" -ForegroundColor Red
        exit 1
    }
}

# ============================================================================
# PROMPT FOR ORGANIZATION IF NOT PROVIDED
# ============================================================================

if (-not $Organization) {
    Write-Host "⚠ Organization domain is required for Exchange Online authentication" -ForegroundColor Yellow
    Write-Host "  Example: contoso.onmicrosoft.com" -ForegroundColor White
    $Organization = Read-Host "Enter your organization domain (or press Enter to skip)"
    Write-Host ""
}

# ============================================================================
# SAVE CONFIGURATION FILE
# ============================================================================

Write-Host "Saving configuration to: $configFile" -ForegroundColor Cyan

$config = @{
    TenantId              = $TenantId
    ClientId              = $ClientId
    CertificateThumbprint = $thumbprint
    CertificateName       = $CertificateName
    CertificatePath       = $certPath
    Organization          = $Organization
    CreatedAt             = (Get-Date).ToString('o')
    ValidUntil            = $notAfter.ToString('o')
}

# Load existing config if exists and merge
if (Test-Path $configFile) {
    try {
        $existingConfig = Get-Content $configFile -Raw | ConvertFrom-Json -AsHashtable
        # Preserve any additional properties
        foreach ($key in $existingConfig.Keys) {
            if (-not $config.ContainsKey($key)) {
                $config[$key] = $existingConfig[$key]
            }
        }
    }
    catch {
        Write-Host "⚠ Could not load existing config, will overwrite" -ForegroundColor Yellow
    }
}

$config | ConvertTo-Json -Depth 10 | Set-Content $configFile -Encoding UTF8
Write-Host "✓ Configuration saved" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PRINT SETUP INSTRUCTIONS
# ============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Azure AD App Registration Setup Instructions" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

if (-not $ClientId) {
    Write-Host "STEP 1: Create Azure AD App Registration" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    Write-Host "1. Go to Azure Portal: https://portal.azure.com" -ForegroundColor White
    Write-Host "2. Navigate to: Azure Active Directory > App registrations" -ForegroundColor White
    Write-Host "3. Click 'New registration'" -ForegroundColor White
    Write-Host "   - Name: $CertificateName" -ForegroundColor White
    Write-Host "   - Supported account types: Accounts in this organizational directory only" -ForegroundColor White
    Write-Host "4. Click 'Register'" -ForegroundColor White
    Write-Host "5. Copy the 'Application (client) ID' from the Overview page" -ForegroundColor White
    Write-Host ""
    Write-Host "⚠ After creating the app, update the config file with ClientId:" -ForegroundColor Yellow
    Write-Host "  Edit: $configFile" -ForegroundColor White
    Write-Host "  Add: `"ClientId`": `"your-client-id-here`"" -ForegroundColor White
    Write-Host ""
}
else {
    Write-Host "✓ Using existing App Registration: $ClientId" -ForegroundColor Green
    Write-Host ""
}

Write-Host "STEP 2: Upload Certificate to App Registration" -ForegroundColor Yellow
Write-Host "-----------------------------------------------" -ForegroundColor Yellow
Write-Host "1. In your App Registration, go to: Certificates & secrets" -ForegroundColor White
Write-Host "2. Click 'Upload certificate'" -ForegroundColor White
Write-Host "3. Upload this file: $certPath" -ForegroundColor White
Write-Host "4. Add description: $CertificateName - Expires $($notAfter.ToString('yyyy-MM-dd'))" -ForegroundColor White
Write-Host "5. Click 'Add'" -ForegroundColor White
Write-Host ""

Write-Host "STEP 3: Grant API Permissions" -ForegroundColor Yellow
Write-Host "------------------------------" -ForegroundColor Yellow
Write-Host "1. In your App Registration, go to: API permissions" -ForegroundColor White
Write-Host "2. Click 'Add a permission'" -ForegroundColor White
Write-Host ""
Write-Host "   For Microsoft Graph (Application permissions):" -ForegroundColor Cyan
Write-Host "   - User.Read.All" -ForegroundColor White
Write-Host "   - Group.Read.All" -ForegroundColor White
Write-Host "   - Directory.Read.All" -ForegroundColor White
Write-Host "   - DeviceManagementManagedDevices.Read.All" -ForegroundColor White
Write-Host "   - Reports.Read.All" -ForegroundColor White
Write-Host "   - AuditLog.Read.All" -ForegroundColor White
Write-Host "   - Organization.Read.All" -ForegroundColor White
Write-Host "   - Team.ReadBasic.All" -ForegroundColor White
Write-Host "   - GroupMember.Read.All" -ForegroundColor White
Write-Host "   - Device.Read.All" -ForegroundColor White
Write-Host ""
Write-Host "   For Exchange Online:" -ForegroundColor Cyan
Write-Host "   - APIs my organization uses > Office 365 Exchange Online" -ForegroundColor White
Write-Host "   - Application permissions > Exchange.ManageAsApp" -ForegroundColor White
Write-Host ""
Write-Host "   For SharePoint (if using):" -ForegroundColor Cyan
Write-Host "   - SharePoint > Application permissions > Sites.FullControl.All" -ForegroundColor White
Write-Host ""

Write-Host "STEP 4: Grant Admin Consent" -ForegroundColor Yellow
Write-Host "---------------------------" -ForegroundColor Yellow
Write-Host "1. In API permissions page, click 'Grant admin consent for [Your Org]'" -ForegroundColor White
Write-Host "2. Click 'Yes' to confirm" -ForegroundColor White
Write-Host "3. Verify all permissions show 'Granted for [Your Org]' with green checkmark" -ForegroundColor White
Write-Host ""

Write-Host "STEP 5: Configure Exchange Online (if using)" -ForegroundColor Yellow
Write-Host "---------------------------------------------" -ForegroundColor Yellow
Write-Host "1. Connect to Exchange Online PowerShell as administrator" -ForegroundColor White
Write-Host "2. Run the following command to grant app access:" -ForegroundColor White
Write-Host ""
if ($ClientId) {
    Write-Host "   New-ServicePrincipal -AppId $ClientId -ServiceId <ObjectId>" -ForegroundColor Cyan
}
else {
    Write-Host "   New-ServicePrincipal -AppId <YourClientId> -ServiceId <ObjectId>" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "3. Find ObjectId: Azure AD > Enterprise applications > Search for app name > Object ID" -ForegroundColor White
Write-Host ""

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Testing Your Configuration" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

Write-Host "After completing the setup, test the connection:" -ForegroundColor White
Write-Host ""
Write-Host "  ./Connect-M365Persistent.ps1 -UseCertificate" -ForegroundColor Cyan
Write-Host ""

Write-Host "Configuration file location:" -ForegroundColor White
Write-Host "  $configFile" -ForegroundColor Cyan
Write-Host ""

Write-Host "Certificate files:" -ForegroundColor White
Write-Host "  Public key (upload to Azure): $certPath" -ForegroundColor Cyan
if (-not $isWindows) {
    Write-Host "  Private key (keep secure): $keyPath" -ForegroundColor Cyan
}
Write-Host ""

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""
