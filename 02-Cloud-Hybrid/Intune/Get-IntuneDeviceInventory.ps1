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
    Retrieves an inventory of all Intune-managed devices with key details.

.DESCRIPTION
    This script connects to Microsoft Graph and retrieves all Intune-managed
    devices, collecting essential information including device name, serial
    number, notes field, operating system, and other relevant details.
    Results are displayed in a formatted table and exported to CSV.

    Key information collected:
    - Device Name
    - Serial Number
    - Notes (device notes field)
    - Operating System and Version
    - User information
    - Last sync time
    - Enrollment date
    - Compliance state
    - Manufacturer and Model

.PARAMETER ExportPath
    Path for the CSV export file (default: IntuneDeviceInventory_<timestamp>.csv)

.PARAMETER IncludeAllProperties
    Include all available device properties in the export (default: standard set only)

.PARAMETER FilterOS
    Filter devices by operating system (e.g., "Windows", "iOS", "Android", "macOS")

.EXAMPLE
    .\Get-IntuneDeviceInventory.ps1
    Retrieves all devices and exports to timestamped CSV

.EXAMPLE
    .\Get-IntuneDeviceInventory.ps1 -ExportPath "C:\Reports\devices.csv"
    Exports to a specific file path

.EXAMPLE
    .\Get-IntuneDeviceInventory.ps1 -FilterOS "Windows"
    Retrieves only Windows devices

.EXAMPLE
    .\Get-IntuneDeviceInventory.ps1 -IncludeAllProperties
    Exports all available device properties
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ExportPath = "IntuneDeviceInventory_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",

    [Parameter(Mandatory=$false)]
    [switch]$IncludeAllProperties,

    [Parameter(Mandatory=$false)]
    [ValidateSet("Windows", "iOS", "Android", "macOS", "")]
    [string]$FilterOS = ""
)

# Check if Microsoft.Graph modules are installed
$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.DeviceManagement',
    'Microsoft.Graph.Users'
)

Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Intune Device Inventory Report" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

# Check and install required modules
Write-Host "Checking required modules..." -ForegroundColor Cyan
foreach ($module in $requiredModules) {
    Write-Host "  Checking $module..." -ForegroundColor Gray
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "  ⚠ Module not found. Please install Microsoft Graph modules first." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To install required modules, run:" -ForegroundColor Yellow
        Write-Host "  Install-Module Microsoft.Graph -Scope CurrentUser -Force" -ForegroundColor White
        Write-Host ""
        Write-Host "Or run the dependency installer:" -ForegroundColor Yellow
        Write-Host "  ./Install-M365Dependencies.ps1" -ForegroundColor White
        Write-Host ""
        exit 1
    }
    Write-Host "  ✓ $module found" -ForegroundColor Green
}

# Import modules
Write-Host "`nImporting Microsoft Graph modules..." -ForegroundColor Cyan
try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop
    Import-Module Microsoft.Graph.Users -ErrorAction Stop
    Write-Host "✓ Modules imported successfully" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to import modules: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please ensure Microsoft Graph modules are properly installed:" -ForegroundColor Yellow
    Write-Host "  Install-Module Microsoft.Graph -Scope CurrentUser -Force" -ForegroundColor White
    exit 1
}

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
$scopes = @(
    "DeviceManagementManagedDevices.Read.All",
    "User.Read.All"
)

try {
    Connect-MgGraph -Scopes $scopes -NoWelcome
    Write-Host "✓ Successfully connected to Microsoft Graph" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
    exit 1
}

# Retrieve all managed devices
Write-Host "`nRetrieving all managed devices from Intune..." -ForegroundColor Cyan

try {
    $allDevices = Get-MgDeviceManagementManagedDevice -All
    Write-Host "✓ Found $($allDevices.Count) total managed devices" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to retrieve devices: $_" -ForegroundColor Red
    Disconnect-MgGraph
    exit 1
}

# Filter by OS if specified
if ($FilterOS) {
    Write-Host "Filtering devices by OS: $FilterOS..." -ForegroundColor Cyan
    $allDevices = $allDevices | Where-Object { $_.OperatingSystem -like "*$FilterOS*" }
    Write-Host "✓ Filtered to $($allDevices.Count) $FilterOS devices" -ForegroundColor Green
}

if ($allDevices.Count -eq 0) {
    Write-Host "`n⚠ No devices found matching criteria. Exiting..." -ForegroundColor Yellow
    Disconnect-MgGraph
    exit 0
}

# Build the device inventory report
Write-Host "`nBuilding device inventory report..." -ForegroundColor Cyan
$report = @()
$totalDevices = $allDevices.Count
$currentCount = 0

foreach ($device in $allDevices) {
    $currentCount++
    Write-Progress -Activity "Processing Intune devices" `
                   -Status "Processing $($device.DeviceName) ($currentCount of $totalDevices)" `
                   -PercentComplete (($currentCount / $totalDevices) * 100)

    # Get user information
    $userName = "Not assigned"
    $userEmail = "Not assigned"
    if ($device.UserId) {
        try {
            $user = Get-MgUser -UserId $device.UserId -ErrorAction SilentlyContinue
            if ($user) {
                $userName = $user.DisplayName
                $userEmail = $user.UserPrincipalName
            }
        } catch {
            # User not found or no access
            $userName = "Unable to retrieve"
            $userEmail = "Unable to retrieve"
        }
    }

    # Format dates for readability
    $lastSync = if ($device.LastSyncDateTime) {
        ([DateTime]$device.LastSyncDateTime).ToString("yyyy-MM-dd HH:mm:ss")
    } else {
        "Never"
    }

    $enrolledDate = if ($device.EnrolledDateTime) {
        ([DateTime]$device.EnrolledDateTime).ToString("yyyy-MM-dd HH:mm:ss")
    } else {
        "Unknown"
    }

    # Build device object
    if ($IncludeAllProperties) {
        # Include all properties
        $deviceInfo = [PSCustomObject]@{
            DeviceName = $device.DeviceName
            SerialNumber = $device.SerialNumber
            Notes = $device.Notes
            OperatingSystem = $device.OperatingSystem
            OSVersion = $device.OSVersion
            UserDisplayName = $userName
            UserPrincipalName = $userEmail
            Manufacturer = $device.Manufacturer
            Model = $device.Model
            LastSyncDateTime = $lastSync
            EnrolledDateTime = $enrolledDate
            ComplianceState = $device.ComplianceState
            ManagementAgent = $device.ManagementAgent
            DeviceEnrollmentType = $device.DeviceEnrollmentType
            AzureADRegistered = $device.AzureAdRegistered
            AzureADDeviceId = $device.AzureAdDeviceId
            DeviceId = $device.Id
            IMEI = $device.Imei
            MEID = $device.Meid
            WiFiMacAddress = $device.WiFiMacAddress
            EthernetMacAddress = $device.EthernetMacAddress
            TotalStorageSpaceInBytes = $device.TotalStorageSpaceInBytes
            FreeStorageSpaceInBytes = $device.FreeStorageSpaceInBytes
            ManagedDeviceOwnerType = $device.ManagedDeviceOwnerType
            DeviceActionResults = ($device.DeviceActionResults | ForEach-Object { "$($_.ActionName): $($_.ActionState)" }) -join "; "
            IsEncrypted = $device.IsEncrypted
            IsSupervised = $device.IsSupervised
            JailBroken = $device.JailBroken
            PhoneNumber = $device.PhoneNumber
        }
    } else {
        # Standard property set
        $deviceInfo = [PSCustomObject]@{
            DeviceName = $device.DeviceName
            SerialNumber = $device.SerialNumber
            Notes = $device.Notes
            OperatingSystem = $device.OperatingSystem
            OSVersion = $device.OSVersion
            UserDisplayName = $userName
            UserPrincipalName = $userEmail
            Manufacturer = $device.Manufacturer
            Model = $device.Model
            LastSyncDateTime = $lastSync
            EnrolledDateTime = $enrolledDate
            ComplianceState = $device.ComplianceState
            ManagementAgent = $device.ManagementAgent
        }
    }

    $report += $deviceInfo
}

Write-Progress -Activity "Processing Intune devices" -Completed

# Export to CSV
Write-Host "`nExporting to CSV: $ExportPath" -ForegroundColor Cyan
try {
    $report | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Host "✓ Successfully exported $($report.Count) devices to CSV" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to export CSV: $_" -ForegroundColor Red
}

# Generate summary statistics
Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
Write-Host "Summary Report" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan

Write-Host "`nTotal Devices: $($report.Count)" -ForegroundColor White

# Group by Operating System
$groupedByOS = $report | Group-Object -Property OperatingSystem | Sort-Object Count -Descending
Write-Host "`nBy Operating System:" -ForegroundColor White
foreach ($group in $groupedByOS) {
    Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor Gray
}

# Group by Compliance State
$groupedByCompliance = $report | Group-Object -Property ComplianceState | Sort-Object Count -Descending
Write-Host "`nBy Compliance State:" -ForegroundColor White
foreach ($group in $groupedByCompliance) {
    $color = switch ($group.Name) {
        "compliant" { "Green" }
        "noncompliant" { "Red" }
        default { "Yellow" }
    }
    Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor $color
}

# Group by Manufacturer
$groupedByManufacturer = $report | Group-Object -Property Manufacturer | Sort-Object Count -Descending | Select-Object -First 5
Write-Host "`nTop 5 Manufacturers:" -ForegroundColor White
foreach ($group in $groupedByManufacturer) {
    Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor Gray
}

# Devices with Notes
$devicesWithNotes = $report | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Notes) }
Write-Host "`nDevices with Notes: $($devicesWithNotes.Count) of $($report.Count)" -ForegroundColor White

# Recently synced devices (last 24 hours)
$recentlySynced = $report | Where-Object {
    $_.LastSyncDateTime -ne "Never" -and
    ([DateTime]$_.LastSyncDateTime) -gt (Get-Date).AddDays(-1)
}
Write-Host "Recently Synced (24h): $($recentlySynced.Count) of $($report.Count)" -ForegroundColor White

Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan

# Display sample of devices in table format
Write-Host "`nSample Device Report (first 10):" -ForegroundColor Cyan
$report | Select-Object -First 10 |
    Format-Table DeviceName, SerialNumber, OperatingSystem, UserDisplayName, LastSyncDateTime, ComplianceState -AutoSize

# Highlight devices with notes if any exist
if ($devicesWithNotes.Count -gt 0) {
    Write-Host "`nDevices with Notes:" -ForegroundColor Cyan
    $devicesWithNotes |
        Select-Object DeviceName, SerialNumber, Notes, OperatingSystem |
        Format-Table -AutoSize
}

# Disconnect from Microsoft Graph
Write-Host "`nDisconnecting from Microsoft Graph..." -ForegroundColor Cyan
Disconnect-MgGraph

Write-Host "`n" + ("=" * 80) -ForegroundColor Green
Write-Host "✓ Report completed successfully!" -ForegroundColor Green
Write-Host "✓ Report saved to: $ExportPath" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host ""
