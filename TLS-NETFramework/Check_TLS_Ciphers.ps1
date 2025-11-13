<#
.SYNOPSIS
Displays the list of TLS cipher suites enabled on the system.

.DESCRIPTION
This script retrieves all available TLS cipher suites configured on the local Windows system using the 
`Get-TlsCipherSuite` cmdlet and displays them in a formatted table showing their names.  

It is useful for security audits, compliance checks, and ensuring that only secure and modern cipher suites are enabled.  
This script can be executed by an administrator or via a system account (for example, through RMM tools) to remotely 
verify TLS configuration.

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-13
Requires    : PowerShell 5.1 or later
Usage       : Run the script to view all TLS cipher suites currently available on the system.
Limitations : Administrative privileges may be required on some systems to retrieve full cipher suite information.
#>

Get-TlsCipherSuite | Format-Table Name
