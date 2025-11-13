<#
.SYNOPSIS
Exports all distribution groups in Active Directory that are not domain-local to a CSV file.

.DESCRIPTION
This script queries Active Directory to retrieve all groups where the GroupCategory is 'Distribution' 
and the GroupScope is not 'DomainLocal'. The results are exported to a CSV file in C:\Temp for 
reporting or auditing purposes. Ensure the ActiveDirectory module is installed and you have sufficient 
permissions to query AD groups.

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-12
Requires    : ActiveDirectory module (RSAT) installed
CSV Output  : C:\Temp\DistributionGroups.csv
Usage       : Run the script in a session with AD privileges. Modify the filter or output path as needed.
#>

# Import Active Directory module
Import-Module ActiveDirectory

# Set CSV output path
$CsvPath = "C:\Temp\DistributionGroups.csv"

# Retrieve distribution groups that are not domain-local and export to CSV
Get-ADGroup -Filter "GroupCategory -eq 'distribution' -and GroupScope -ne 'DomainLocal'" |
    Select-Object Name, GroupScope, GroupCategory, DistinguishedName |
    Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

Write-Host "Exported distribution groups to $CsvPath"
