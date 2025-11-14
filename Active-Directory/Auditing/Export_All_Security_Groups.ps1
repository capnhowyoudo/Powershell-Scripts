<#
.SYNOPSIS
Exports all security groups in Active Directory that are not domain-local to a CSV file.

.DESCRIPTION
This script queries Active Directory to retrieve all groups where the GroupCategory is 'Security' 
and the GroupScope is not 'DomainLocal'. The results are exported to a CSV file in C:\Temp for 
reporting or auditing purposes. Ensure the ActiveDirectory module is installed and you have sufficient 
permissions to query AD groups. You can modify the CSV path as needed.

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-12
Requires    : ActiveDirectory module (RSAT) installed
CSV Output  : C:\Temp\SecurityGroups.csv
Usage       : Run the script in a session with AD privileges. Modify the filter or output path as needed.
#>

# Import Active Directory module
Import-Module ActiveDirectory

# Set CSV output path
$CsvPath = "C:\Temp\SecurityGroups.csv"

# Retrieve security groups that are not domain-local and export to CSV
Get-ADGroup -Filter "GroupCategory -eq 'Security' -and GroupScope -ne 'DomainLocal'" |
    Select-Object Name, GroupScope, GroupCategory, DistinguishedName |
    Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

Write-Host "Exported security groups to $CsvPath"
