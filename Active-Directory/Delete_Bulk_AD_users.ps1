<#
.SYNOPSIS
Deletes Active Directory users based on a list of SamAccountNames from a CSV file.

.DESCRIPTION
This script imports a CSV file containing SamAccountNames of Active Directory users to be removed. 
It then iterates through each entry and deletes the corresponding AD user. By default, the script 
runs in "WhatIf" mode to simulate deletions without making changes. Remove the -WhatIf switch 
to perform actual deletions. The CSV file must have a column named "samAccountName". 
Ensure you have sufficient permissions to delete AD user accounts before running this script.

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-12
Requires    : ActiveDirectory module (RSAT) installed
CSV Format  : The CSV file should contain a column header named "samAccountName" Can aquire with the following
https://github.com/capnhowyoudo/Powershell-Scripts/blob/main/Active-Directory/Export_Enabled_Accounts.ps1
https://github.com/capnhowyoudo/Powershell-Scripts/blob/main/Active-Directory/Export_Inactive_Users_Time_Span.ps1

Example CSV:
samAccountName
jdoe
asmith

Usage       : Modify the path to the CSV file and run the script in a session with AD privileges.

.EXAMPLE
# Run the script in test mode to simulate deletions
.\Delete_Bulk_AD_users.ps1

.EXAMPLE
# Run the script to actually remove users (remove -WhatIf)
Import-Csv "C:\Scripts\delete.csv" | ForEach-Object {
    $samAccountName = $_.samAccountName
    Remove-ADUser $samAccountName -Confirm:$False
}
#>

# Import Active Directory module
Import-Module ActiveDirectory

# Path to CSV
$csvPath = "C:\Scripts\delete.csv"

# Import CSV and remove users (default is WhatIf mode)
Import-Csv $csvPath | ForEach-Object {
    $samAccountName = $_.samAccountName
    Remove-ADUser $samAccountName -Confirm:$False -WhatIf
}
