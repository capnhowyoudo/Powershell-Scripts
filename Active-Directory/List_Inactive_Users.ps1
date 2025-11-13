<#
.SYNOPSIS
Exports all Active Directory user accounts that have been inactive for 90 days to a CSV file.

.DESCRIPTION
This script searches Active Directory for user accounts that have been inactive for the last 90 days. 
It filters the results to include only accounts that are still enabled, then exports the output 
to a CSV file containing the Name, SamAccountName, and DistinguishedName of each user.

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-12
Requires    : ActiveDirectory module (RSAT) installed
Output File : C:\Temp\InActiveUsers.CSV
#>

# Ensure ActiveDirectory module is imported
Import-Module ActiveDirectory

# Set variables
$timeSpan = New-TimeSpan -Days 90
$outputFile = "C:\Temp\InActiveUsers.CSV"

# Search AD for inactive user accounts and export enabled users to CSV
Search-ADAccount -AccountInactive -TimeSpan $timeSpan -ResultPageSize 2000 -ResultSetSize $null |
    Where-Object { $_.Enabled -eq $True } |
    Select-Object Name, SamAccountName, DistinguishedName |
    Export-Csv $outputFile -NoTypeInformation
