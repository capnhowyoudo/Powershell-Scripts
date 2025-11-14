<#
.SYNOPSIS
Exports a list of all printers installed on the system to a CSV file.

.DESCRIPTION
This script retrieves all printers installed on the local system using the `Get-Printer` cmdlet.  
It collects each printer’s name, port name, and driver name, then exports the information to a CSV file  
for documentation or inventory purposes.  

It can be run by an administrator or as the SYSTEM account (for example, via RMM or remote management tools)  
to capture printer configurations across multiple systems.  
If the output directory (C:\Temp) does not exist, the script will create it automatically.

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-13
Requires    : PowerShell 5.1+ (or compatible version)
CSV Output  : C:\Temp\Printers.csv
Usage       : Run the script locally or remotely to export printer details. Modify the output path if needed.
Limitations : Requires access to the local print subsystem; network printers may appear differently based on configuration.
#>

# Ensure output directory exists
$OutputPath = "C:\Temp\Printers.csv"
$OutputDir  = Split-Path $OutputPath

if (-not (Test-Path $OutputDir)) {
    Write-Host "Creating directory $OutputDir..."
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Retrieve printer information and export to CSV
Get-Printer |
    Select-Object Name, PortName, DriverName |
    Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "✅ Printer information exported successfully to $OutputPath"
