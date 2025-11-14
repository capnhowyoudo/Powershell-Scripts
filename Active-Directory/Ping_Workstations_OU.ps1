<#
.SYNOPSIS
Pings all computers in a specified OU and exports the results to a CSV file.

.DESCRIPTION
This script queries Active Directory for all computer objects within a specified
Organizational Unit (OU), attempts to ping each computer, and logs either the
IPv4 address or the error returned. Results are exported to a CSV file for
reporting or auditing purposes.

The script is designed for administrators who need to quickly verify host
availability within a specific OU. It requires the ActiveDirectory module.

This script can be run with standard admin permissions, SYSTEM context, or via RMM tools.

.NOTES
Author: capnhowyoudo 
Requires: RSAT / ActiveDirectory module  
Output File: C:\temp\OUPing.csv  
#>

# Enter CSV file location
$csv = "C:\temp\OUPing.csv"

# Target OU (generic example)
$Computers = Get-ADComputer -Filter * -SearchBase "OU=Workstations,DC=example,DC=local" |
             Select-Object Name |
             Sort-Object Name

$Computers = $Computers.Name

# Write CSV headers
$Headers = "ComputerName,IP Address"
$Headers | Out-File -FilePath $csv -Encoding UTF8

foreach ($computer in $Computers) {
    Write-Host "Pinging $computer"

    $Test = Test-Connection -ComputerName $computer -Count 1 -ErrorAction SilentlyContinue -ErrorVariable Err

    if ($Test -ne $null) {
        $IP = $Test.IPV4Address.IPAddressToString
        $Output = "$computer,$IP"
        $Output | Out-File -FilePath $csv -Encoding UTF8 -Append
    }
    else {
        $Output = "$computer,$Err"
        $Output | Out-File -FilePath $csv -Encoding UTF8 -Append
    }

    Clear-Host
}
