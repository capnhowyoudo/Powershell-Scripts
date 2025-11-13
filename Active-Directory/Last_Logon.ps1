<#
.SYNOPSIS
Exports all enabled Active Directory users with their last logon timestamp to a CSV file.

.DESCRIPTION
This script queries Active Directory for all enabled user accounts and retrieves the `LastLogonTimeStamp` property. 
It converts the timestamp from the AD file time format to a human-readable format (`yyyy-MM-dd_hh:mm:ss`) and 
exports the results to a CSV file at the specified path. Ensure the ActiveDirectory module is installed 
and you have sufficient permissions to query AD user accounts. 

.NOTES
Author      : Your Name
Date        : 2025-11-12
Requires    : ActiveDirectory module (RSAT) installed
Output File : C:\alluser_reports.csv
Usage       : Run the script in a session with AD privileges. Modify the output path as needed.
#>

# Import Active Directory module
Import-Module ActiveDirectory

# Default output path
$csvPath = "C:\alluser_reports.csv"

# Retrieve enabled AD users and export LastLogonTimeStamp
Get-ADUser -Filter {enabled -eq $true} -Properties LastLogonTimeStamp |
    Select-Object Name, @{
        Name = "Stamp"
        Expression = {[DateTime]::FromFileTime($_.LastLogonTimeStamp).ToString('yyyy-MM-dd_HH:mm:ss')}
    } |
    Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
