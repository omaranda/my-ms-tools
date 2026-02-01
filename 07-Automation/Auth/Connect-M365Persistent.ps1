<#
.SYNOPSIS
    Provides persistent authentication to Microsoft 365 services with certificate-based or cached interactive modes.

.DESCRIPTION
    Connect-M365Persistent.ps1 establishes connections to Microsoft 365 services (Microsoft Graph,
    Exchange Online, Azure, SharePoint) using either:

    1. Certificate-based authentication (Service Principal) - Fully non-interactive, ideal for automation
    2. Interactive authentication with token caching - Browser prompt once, reuse for days

    The script intelligently checks for existing connections before prompting for authentication,
    preventing unnecessary re-authentication. It supports selective module connection and tracks
    connection status globally for use by other scripts.

    This script is designed to be called at the beginning of other automation scripts to ensure
    authenticated sessions are available without repeated browser prompts.

.PARAMETER UseCertificate
    Use certificate-based authentication (Service Principal mode).
    Requires TenantId, ClientId, and CertificateThumbprint (or config file).

.PARAMETER TenantId
    Azure AD Tenant ID (GUID format).
    Required for certificate-based auth, optional for interactive (will prompt if needed).

.PARAMETER ClientId
    Azure AD Application (Client) ID.
    Required for certificate-based auth.

.PARAMETER CertificateThumbprint
    Thumbprint of the certificate used for authentication.
    Required for certificate-based auth unless using config file.

.PARAMETER ConfigFile
    Path to JSON configuration file containing authentication parameters.
    Default: ~/.ms-tools/auth-config.json
    File should contain: TenantId, ClientId, CertificateThumbprint, Organization

.PARAMETER Modules
    Array of modules to connect. Valid values: MgGraph, ExchangeOnline, Az, PnP
    Default: All modules

.PARAMETER Force
    Force re-authentication even if existing connections are detected.

.PARAMETER Organization
    Organization domain for Exchange Online (e.g., contoso.onmicrosoft.com).
    Required for certificate-based Exchange Online authentication.

.EXAMPLE
    .\Connect-M365Persistent.ps1

    Connects to all M365 services using interactive authentication with token caching.
    Will only prompt for credentials if no existing valid session is found.

.EXAMPLE
    .\Connect-M365Persistent.ps1 -Modules MgGraph, ExchangeOnline

    Connects only to Microsoft Graph and Exchange Online, skipping Azure and SharePoint.

.EXAMPLE
    .\Connect-M365Persistent.ps1 -UseCertificate

    Connects using certificate-based authentication, reading configuration from ~/.ms-tools/auth-config.json

.EXAMPLE
    .\Connect-M365Persistent.ps1 -UseCertificate -TenantId "12345678-1234-1234-1234-123456789012" `
        -ClientId "87654321-4321-4321-4321-210987654321" -CertificateThumbprint "A1B2C3..." -Organization "contoso.onmicrosoft.com"

    Connects using certificate-based authentication with explicitly provided parameters.

.EXAMPLE
    .\Connect-M365Persistent.ps1 -Force

    Forces re-authentication even if existing connections are detected.

.NOTES
    Author: Microsoft 365 Tools Team
    Version: 1.0.0
    Date: 2026-02-01

    Required Modules:
    - Microsoft.Graph.Authentication
    - ExchangeOnlineManagement
    - Az.Accounts
    - PnP.PowerShell (optional)

    Required Permissions (for Service Principal):
    - Microsoft Graph API: User.Read.All, Group.Read.All, Directory.Read.All,
      DeviceManagementManagedDevices.Read.All, Reports.Read.All, AuditLog.Read.All,
      Organization.Read.All, Team.ReadBasic.All
    - Exchange Online: Exchange.ManageAsApp
    - Azure: Contributor or Reader (depending on operations)

    Platform: Cross-platform (PowerShell 7+)
    Compatibility: Windows, macOS, Linux

.LINK
    https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands
    https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'Certificate')]
    [switch]$UseCertificate,

    [Parameter(ParameterSetName = 'Certificate')]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Certificate')]
    [string]$ClientId,

    [Parameter(ParameterSetName = 'Certificate')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'Certificate')]
    [Parameter(ParameterSetName = 'Interactive')]
    [string]$ConfigFile = (Join-Path $HOME ".ms-tools/auth-config.json"),

    [Parameter(ParameterSetName = 'Certificate')]
    [Parameter(ParameterSetName = 'Interactive')]
    [ValidateSet('MgGraph', 'ExchangeOnline', 'Az', 'PnP')]
    [string[]]$Modules = @('MgGraph', 'ExchangeOnline', 'Az'),

    [Parameter(ParameterSetName = 'Certificate')]
    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$Force,

    [Parameter(ParameterSetName = 'Certificate')]
    [string]$Organization
)

# ============================================================================
# INITIALIZATION
# ============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Microsoft 365 Persistent Authentication" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Initialize global connection tracking
if (-not $Global:M365Connected) {
    $Global:M365Connected = @{
        MgGraph        = $false
        ExchangeOnline = $false
        Az             = $false
        PnP            = $false
        AuthMethod     = $null
        ConnectedAt    = $null
    }
}

# ============================================================================
# LOAD CONFIGURATION FROM FILE (if exists)
# ============================================================================

$config = $null
if (Test-Path $ConfigFile) {
    try {
        $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        Write-Host "✓ Configuration loaded from: $ConfigFile" -ForegroundColor Green

        # Override parameters with config values if not explicitly provided
        if ($UseCertificate) {
            if (-not $TenantId -and $config.TenantId) { $TenantId = $config.TenantId }
            if (-not $ClientId -and $config.ClientId) { $ClientId = $config.ClientId }
            if (-not $CertificateThumbprint -and $config.CertificateThumbprint) {
                $CertificateThumbprint = $config.CertificateThumbprint
            }
            if (-not $Organization -and $config.Organization) { $Organization = $config.Organization }
        }
    }
    catch {
        Write-Host "⚠ Warning: Could not load configuration file: $_" -ForegroundColor Yellow
    }
}

# ============================================================================
# VALIDATE PARAMETERS FOR CERTIFICATE AUTH
# ============================================================================

if ($UseCertificate) {
    $missingParams = @()
    if (-not $TenantId) { $missingParams += 'TenantId' }
    if (-not $ClientId) { $missingParams += 'ClientId' }
    if (-not $CertificateThumbprint) { $missingParams += 'CertificateThumbprint' }

    if ($missingParams.Count -gt 0) {
        Write-Host "✗ Error: Certificate-based authentication requires the following parameters:" -ForegroundColor Red
        $missingParams | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Write-Host ""
        Write-Host "Either provide them as parameters or ensure they exist in: $ConfigFile" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "Authentication Mode: Certificate-based (Service Principal)" -ForegroundColor Cyan
    Write-Host "Tenant ID: $TenantId" -ForegroundColor White
    Write-Host "Client ID: $ClientId" -ForegroundColor White
    Write-Host "Certificate: $CertificateThumbprint" -ForegroundColor White
    Write-Host ""

    $Global:M365Connected.AuthMethod = 'Certificate'
}
else {
    Write-Host "Authentication Mode: Interactive with Token Caching" -ForegroundColor Cyan
    Write-Host ""
    $Global:M365Connected.AuthMethod = 'Interactive'
}

# ============================================================================
# MODULE INSTALLATION CHECK
# ============================================================================

Write-Host "Checking required PowerShell modules..." -ForegroundColor Cyan

$requiredModules = @()
if ($Modules -contains 'MgGraph') { $requiredModules += 'Microsoft.Graph.Authentication' }
if ($Modules -contains 'ExchangeOnline') { $requiredModules += 'ExchangeOnlineManagement' }
if ($Modules -contains 'Az') { $requiredModules += 'Az.Accounts' }
if ($Modules -contains 'PnP') { $requiredModules += 'PnP.PowerShell' }

foreach ($module in $requiredModules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Write-Host "⚠ Module not found: $module - Installing..." -ForegroundColor Yellow
        try {
            Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
            Write-Host "✓ Installed: $module" -ForegroundColor Green
        }
        catch {
            Write-Host "✗ Failed to install $module : $_" -ForegroundColor Red
            exit 1
        }
    }
}

Write-Host ""

# ============================================================================
# FUNCTION: Check Microsoft Graph Connection
# ============================================================================

function Test-MgGraphConnection {
    try {
        $context = Get-MgContext -ErrorAction SilentlyContinue
        return ($null -ne $context)
    }
    catch {
        return $false
    }
}

# ============================================================================
# FUNCTION: Check Exchange Online Connection
# ============================================================================

function Test-ExchangeOnlineConnection {
    try {
        $sessions = Get-PSSession | Where-Object {
            $_.ConfigurationName -eq 'Microsoft.Exchange' -and $_.State -eq 'Opened'
        }
        return ($sessions.Count -gt 0)
    }
    catch {
        return $false
    }
}

# ============================================================================
# FUNCTION: Check Azure Connection
# ============================================================================

function Test-AzConnection {
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        return ($null -ne $context)
    }
    catch {
        return $false
    }
}

# ============================================================================
# FUNCTION: Check PnP Connection
# ============================================================================

function Test-PnPConnection {
    try {
        $connection = Get-PnPConnection -ErrorAction SilentlyContinue
        return ($null -ne $connection)
    }
    catch {
        return $false
    }
}

# ============================================================================
# CONNECT TO MICROSOFT GRAPH
# ============================================================================

if ($Modules -contains 'MgGraph') {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

    $isConnected = Test-MgGraphConnection

    if ($isConnected -and -not $Force) {
        $context = Get-MgContext
        Write-Host "✓ Already connected to Microsoft Graph" -ForegroundColor Green
        Write-Host "  Account: $($context.Account)" -ForegroundColor White
        Write-Host "  Tenant: $($context.TenantId)" -ForegroundColor White
        $Global:M365Connected.MgGraph = $true
    }
    else {
        if ($Force -and $isConnected) {
            Write-Host "⚠ Force reconnection requested - Disconnecting existing session..." -ForegroundColor Yellow
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }

        try {
            Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

            if ($UseCertificate) {
                # Certificate-based authentication
                Connect-MgGraph -ClientId $ClientId -TenantId $TenantId `
                    -CertificateThumbprint $CertificateThumbprint -NoWelcome -ErrorAction Stop

                Write-Host "✓ Connected to Microsoft Graph (Certificate)" -ForegroundColor Green
            }
            else {
                # Interactive authentication with comprehensive scopes
                $scopes = @(
                    'User.Read.All',
                    'Group.Read.All',
                    'Directory.Read.All',
                    'DeviceManagementManagedDevices.Read.All',
                    'Reports.Read.All',
                    'AuditLog.Read.All',
                    'Organization.Read.All',
                    'Team.ReadBasic.All',
                    'GroupMember.Read.All',
                    'Device.Read.All'
                )

                Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop

                $context = Get-MgContext
                Write-Host "✓ Connected to Microsoft Graph (Interactive)" -ForegroundColor Green
                Write-Host "  Account: $($context.Account)" -ForegroundColor White
                Write-Host "  Tenant: $($context.TenantId)" -ForegroundColor White
            }

            $Global:M365Connected.MgGraph = $true
        }
        catch {
            Write-Host "✗ Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
            $Global:M365Connected.MgGraph = $false
        }
    }
    Write-Host ""
}

# ============================================================================
# CONNECT TO EXCHANGE ONLINE
# ============================================================================

if ($Modules -contains 'ExchangeOnline') {
    Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan

    $isConnected = Test-ExchangeOnlineConnection

    if ($isConnected -and -not $Force) {
        Write-Host "✓ Already connected to Exchange Online" -ForegroundColor Green
        $Global:M365Connected.ExchangeOnline = $true
    }
    else {
        if ($Force -and $isConnected) {
            Write-Host "⚠ Force reconnection requested - Disconnecting existing session..." -ForegroundColor Yellow
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        }

        try {
            Import-Module ExchangeOnlineManagement -ErrorAction Stop

            if ($UseCertificate) {
                # Certificate-based authentication
                if (-not $Organization) {
                    Write-Host "✗ Error: -Organization parameter required for Exchange Online certificate auth" -ForegroundColor Red
                    $Global:M365Connected.ExchangeOnline = $false
                }
                else {
                    Connect-ExchangeOnline -CertificateThumbprint $CertificateThumbprint `
                        -AppId $ClientId -Organization $Organization -ShowBanner:$false -ErrorAction Stop

                    Write-Host "✓ Connected to Exchange Online (Certificate)" -ForegroundColor Green
                    Write-Host "  Organization: $Organization" -ForegroundColor White
                    $Global:M365Connected.ExchangeOnline = $true
                }
            }
            else {
                # Interactive authentication
                Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop

                Write-Host "✓ Connected to Exchange Online (Interactive)" -ForegroundColor Green
                $Global:M365Connected.ExchangeOnline = $true
            }
        }
        catch {
            Write-Host "✗ Failed to connect to Exchange Online: $_" -ForegroundColor Red
            $Global:M365Connected.ExchangeOnline = $false
        }
    }
    Write-Host ""
}

# ============================================================================
# CONNECT TO AZURE
# ============================================================================

if ($Modules -contains 'Az') {
    Write-Host "Connecting to Azure..." -ForegroundColor Cyan

    $isConnected = Test-AzConnection

    if ($isConnected -and -not $Force) {
        $context = Get-AzContext
        Write-Host "✓ Already connected to Azure" -ForegroundColor Green
        Write-Host "  Account: $($context.Account)" -ForegroundColor White
        Write-Host "  Subscription: $($context.Subscription.Name)" -ForegroundColor White
        $Global:M365Connected.Az = $true
    }
    else {
        if ($Force -and $isConnected) {
            Write-Host "⚠ Force reconnection requested - Disconnecting existing session..." -ForegroundColor Yellow
            Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
        }

        try {
            Import-Module Az.Accounts -ErrorAction Stop

            if ($UseCertificate) {
                # Certificate-based authentication
                $secureThumbprint = ConvertTo-SecureString $CertificateThumbprint -AsPlainText -Force
                Connect-AzAccount -ServicePrincipal -TenantId $TenantId `
                    -CertificateThumbprint $CertificateThumbprint `
                    -ApplicationId $ClientId -ErrorAction Stop | Out-Null

                $context = Get-AzContext
                Write-Host "✓ Connected to Azure (Certificate)" -ForegroundColor Green
                Write-Host "  Subscription: $($context.Subscription.Name)" -ForegroundColor White
            }
            else {
                # Interactive authentication
                Connect-AzAccount -ErrorAction Stop | Out-Null

                $context = Get-AzContext
                Write-Host "✓ Connected to Azure (Interactive)" -ForegroundColor Green
                Write-Host "  Account: $($context.Account)" -ForegroundColor White
                Write-Host "  Subscription: $($context.Subscription.Name)" -ForegroundColor White
            }

            $Global:M365Connected.Az = $true
        }
        catch {
            Write-Host "✗ Failed to connect to Azure: $_" -ForegroundColor Red
            $Global:M365Connected.Az = $false
        }
    }
    Write-Host ""
}

# ============================================================================
# CONNECT TO SHAREPOINT (PnP)
# ============================================================================

if ($Modules -contains 'PnP') {
    Write-Host "⚠ SharePoint PnP connection requires site URL and is typically site-specific" -ForegroundColor Yellow
    Write-Host "  Use Connect-PnPOnline directly in your scripts with the appropriate site URL" -ForegroundColor Yellow
    Write-Host ""
    $Global:M365Connected.PnP = $false
}

# ============================================================================
# CONNECTION SUMMARY
# ============================================================================

$Global:M365Connected.ConnectedAt = Get-Date

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Connection Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$connectionStatus = @(
    @{Service = 'Microsoft Graph'; Connected = $Global:M365Connected.MgGraph }
    @{Service = 'Exchange Online'; Connected = $Global:M365Connected.ExchangeOnline }
    @{Service = 'Azure'; Connected = $Global:M365Connected.Az }
    @{Service = 'SharePoint (PnP)'; Connected = $Global:M365Connected.PnP }
)

foreach ($status in $connectionStatus) {
    $statusText = if ($status.Connected) { "✓ Connected" } else { "✗ Not Connected" }
    $color = if ($status.Connected) { "Green" } else { "Red" }
    Write-Host ("{0,-20} : " -f $status.Service) -NoNewline
    Write-Host $statusText -ForegroundColor $color
}

Write-Host ""
Write-Host "Authentication Method: $($Global:M365Connected.AuthMethod)" -ForegroundColor Cyan
Write-Host "Connected At: $($Global:M365Connected.ConnectedAt.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host ""

$successCount = ($connectionStatus | Where-Object { $_.Connected }).Count
$totalCount = ($Modules | Where-Object { $_ -ne 'PnP' }).Count

if ($successCount -eq $totalCount) {
    Write-Host "✓ All requested connections established successfully!" -ForegroundColor Green
}
elseif ($successCount -gt 0) {
    Write-Host "⚠ Partial success: $successCount of $totalCount connections established" -ForegroundColor Yellow
}
else {
    Write-Host "✗ All connections failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
