<#
.SYNOPSIS
Disables Active Directory user accounts based on a list of SamAccountNames from a CSV file.

.DESCRIPTION
This script imports a CSV file containing SamAccountNames of Active Directory users to be disabled. 
For each user, it disables the account and updates the AD description field with a timestamp indicating 
when the account was disabled. By default, the script runs in "WhatIf" mode to simulate changes 
without actually modifying any accounts. Remove or set -WhatIf:$false to perform the actual changes. 
The CSV file must have a column named "samAccountName". Ensure you have sufficient permissions to 
disable AD accounts and modify user attributes before running this script.

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-12
Requires    : ActiveDirectory module (RSAT) installed
CSV Format  : The CSV file should contain a column header named "samAccountName" Can aquire with List_Enabled_Accounts.ps1
Usage       : Modify the path to the CSV file and run the script in a session with AD privileges.

.EXAMPLE
# Dry-run to simulate disabling users
.\Disable_Bulk_Users.ps1 -WhatIf:$true

.EXAMPLE
# Perform the actual account disabling
.\Disable_Bulk_Users.ps1 -WhatIf:$false

.EXAMPLE
# Use a custom CSV path
.\Disable_Bulk_Users.ps1 -CsvPath "D:\UsersToDisable.csv" -WhatIf:$false
#>

[CmdletBinding()]
param (
    [string]$CsvPath = "C:\Scripts\Disableusers.csv",
    [switch]$WhatIf = $true
)

# Import Active Directory module
Import-Module ActiveDirectory

# Import CSV and disable users
Import-Csv $CsvPath | ForEach-Object {
    $samAccountName = $_.samAccountName

    if ($WhatIf) {
        Write-Host "[WhatIf] Would disable account and update description for user: $samAccountName"
    } else {
        # Disable the account
        Get-ADUser -Identity $samAccountName | Disable-ADAccount
        # Update description with timestamp
        Get-ADUser $samAccountName | Set-ADUser -Description "Account disabled $(Get-Date)"
        Write-Host "Disabled account and updated description for user: $samAccountName"
    }
}
