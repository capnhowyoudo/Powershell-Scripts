<#
.SYNOPSIS
Exports all Active Directory computers and their key properties to a CSV file.

.DESCRIPTION
This script retrieves all computer objects from Active Directory and selects key properties, 
including Name, DNSHostName, Enabled status, and LastLogonDate. The results are exported to a CSV file 
at the specified path using UTF8 encoding and without type information. By default, the script runs in 
"WhatIf" mode to simulate the export without actually creating the CSV file. Remove or set -WhatIf:$false 
to perform the actual export. Ensure the ActiveDirectory module is installed and that you have sufficient 
permissions to query computer objects in AD.

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-12
Requires    : ActiveDirectory module (RSAT) installed
Default Output File : C:\AllComputers.csv
Usage       : Run the script in a session with AD privileges. Use -WhatIf:$false to perform the export.

.EXAMPLE
# Dry-run to simulate export
.\Export_All_AD_Computers.ps1 -WhatIf:$true

.EXAMPLE
# Perform the actual export
.\Export_All_AD_Computers.ps1 -WhatIf:$false

.EXAMPLE
# Export to a custom CSV path
.\Export_All_AD_Computers.ps1 -CsvPath "D:\Reports\AllComputers.csv" -WhatIf:$false
#>

[CmdletBinding()]
param (
    [string]$CsvPath = "C:\AllComputers.csv",
    [switch]$WhatIf = $true
)

# Import Active Directory module
Import-Module ActiveDirectory

# Retrieve all AD computers
$allComputers = Get-ADComputer -Filter * -Properties * |
    Select-Object Name, DNSHostName, Enabled, LastLogonDate

if ($WhatIf) {
    Write-Host "[WhatIf] Would export $($allComputers.Count) AD computers to $CsvPath"
} else {
    # Export to CSV
    $allComputers | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Exported $($allComputers.Count) AD computers to $CsvPath"
}
