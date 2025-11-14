<#
.SYNOPSIS
Exports all enabled Active Directory users and their basic information to a CSV file.

.DESCRIPTION
This script queries Active Directory for all user accounts that are currently enabled. 
It retrieves the user's GivenName, Surname, SamAccountName, and EmailAddress, 
and exports this information to a CSV file. By default, the script runs in "WhatIf" mode 
to simulate the export without creating the file. Remove or set -WhatIf:$false to perform the actual export. 
Ensure the ActiveDirectory module is installed and you have sufficient permissions to query AD users.

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-12
Requires    : ActiveDirectory module (RSAT) installed
Default Output File : C:\Temp\EnabledADUsers.csv
Usage       : Run the script in a session with AD privileges. Use -WhatIf:$false to perform the export.

.EXAMPLE
# Dry-run (simulate) export
.\Export_Enabled_Accounts.ps1 -WhatIf:$true

.EXAMPLE
# Perform the actual export
.\Export_Enabled_Accounts.ps1 -WhatIf:$false

.EXAMPLE
# Export to a custom path
$csvPath = "D:\Reports\EnabledUsers.csv"
.Export_Enabled_Accounts.ps1 -CsvPath $csvPath -WhatIf:$false
#>

[CmdletBinding()]
param (
    [string]$CsvPath = "C:\Temp\EnabledADUsers.csv",
    [switch]$WhatIf = $true
)

# Import Active Directory module
Import-Module ActiveDirectory

# Retrieve enabled AD users
$enabledUsers = Get-ADUser -Filter 'enabled -eq $true' -Properties GivenName, Surname, SamAccountName, EmailAddress |
    Select-Object GivenName, Surname, SamAccountName, EmailAddress

if ($WhatIf) {
    Write-Host "[WhatIf] Would export $($enabledUsers.Count) enabled AD users to $CsvPath"
} else {
    # Export to CSV
    $enabledUsers | Export-Csv -Path $CsvPath -NoTypeInformation
    Write-Host "Exported $($enabledUsers.Count) enabled AD users to $CsvPath"
}
