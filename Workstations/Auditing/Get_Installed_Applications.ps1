<#
.SYNOPSIS
Retrieves all installed applications on the local Windows system and optionally exports to CSV.

.DESCRIPTION
This script reads installed applications from both the 32-bit and 64-bit uninstall registry keys:
- HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*
- HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*

It collects the DisplayName, DisplayVersion, Publisher, and InstallDate properties for each installed application.  
The results are sorted alphabetically by DisplayName, displayed in the console using a formatted table, and optionally exported to a CSV file.

The export option can be set to $true or $false.

This is useful for auditing, inventory, or compliance purposes. The script does not modify any system settings.

.NOTES
File Name   : Get_Installed_Applications.ps1
Author      : capnhowyoudo
Date        : 2025-11-13
Requires    : PowerShell 3.0+
Usage       : 
    - Display installed applications in console without export:
        .\Get_Installed_Applications.ps1 -Export $false
    - Export installed applications to CSV:
        .\Get_Installed_Applications.ps1 -Export $true
Output File : C:\Temp\InstalledApplications.csv
Limitations : Only lists applications registered in the registry under the uninstall keys.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [bool]$Export = $false
)

# Registry paths for installed applications
$uninstallKeys = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

# Initialize array for results
$installedApps = @()

# Retrieve installed applications from both registry paths
foreach ($key in $uninstallKeys) {
    $apps = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue | 
            Where-Object {$_.DisplayName} | 
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
    $installedApps += $apps
}

# Sort alphabetically by DisplayName
$installedApps = $installedApps | Sort-Object -Property DisplayName

# Display results in console
$installedApps | Format-Table -AutoSize

# Export to CSV if $Export is true
if ($Export -eq $true) {
    $OutputPath = "C:\Temp\InstalledApplications.csv"
    if (!(Test-Path (Split-Path $OutputPath))) {
        New-Item -ItemType Directory -Path (Split-Path $OutputPath) -Force | Out-Null
    }
    $installedApps | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "Installed applications exported to $OutputPath" -ForegroundColor Green
}
