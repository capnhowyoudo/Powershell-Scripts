<#
.SYNOPSIS
Exports all members of a specified Active Directory group to a CSV file.

.DESCRIPTION
This script retrieves all members of an Active Directory group specified by the `$GroupName` variable. 
It selects only the `Name` property of each group member and exports the results to a CSV file at the specified path. 
Ensure the ActiveDirectory module is installed and that you have sufficient permissions to query the group and its members. 
Modify the group name and output path as needed.

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-12
Requires    : ActiveDirectory module (RSAT) installed
CSV Output  : C:\IT\GroupMembers.csv
Usage       : Run the script in a session with AD privileges. Change the group name and output path as needed.
#>

# Import Active Directory module
Import-Module ActiveDirectory

# Set the group name (generic example) and CSV output path
$GroupName = "GenericGroupName"
$CsvPath = "C:\IT\GroupMembers.csv"

# Retrieve group members and export to CSV
Get-ADGroupMember -Identity $GroupName |
    Select-Object Name |
    Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
