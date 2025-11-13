<#
.SYNOPSIS
Exports all disabled Active Directory users to a CSV file.

.DESCRIPTION
This script queries Active Directory for all user accounts that are currently disabled. 
It retrieves the Name property of each disabled user and exports the results to a CSV file 
at the specified path using UTF8 encoding and without type information. By default, the script runs in 
"WhatIf" mode to simulate the export without actually creating the CSV file. Remove or set -WhatIf:$false 
to perform the actual export. Ensure the ActiveDirectory module is installed and you have sufficient 
permissions to query AD users.

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-12
Requires    : ActiveDirectory module (RSAT) installed
Default Output File : C:\Temp\DisabledADUsers.csv
Usage       : Run the script in a session with AD privileges. Use -WhatIf:$false to perform the export.

.EXAMPLE
# Dry-run to simulate exporting disabled users
.\Export_Disabled_AD_Users.ps1 -WhatIf:$true

.EXAMPLE
# Perform the actual export
.\Export_Disabled_AD_Users.ps1 -WhatIf:$false

.EXAMPLE
# Export to a custom CSV path
.\Export_Disabled_AD_Users.ps1 -CsvPath "D:\Reports\DisabledUsers.csv" -WhatIf:$false
#>

[CmdletBinding()]
param (
    [string]$CsvPath = "C:\Temp\DisabledADUsers.csv",
    [switch]$WhatIf = $true
)

# Import Active Directory module
Import-Module ActiveDirectory

# Retrieve all disabled AD users
$disabledUsers = Get-ADUser -Filter "Enabled -eq 'False'" | Select-Object Name

if ($WhatIf) {
    Write-Host "[WhatIf] Would export $($disabledUsers.Count) disabled AD users to $CsvPath"
} else {
    # Export to CSV
    $disabledUsers | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Exported $($disabledUsers.Count) disabled AD users to $CsvPath"
}
