<#
.SYNOPSIS
Searches Active Directory for objects with a specific email address or proxy address.

.DESCRIPTION
This script queries Active Directory for any object (user, contact, or group) that has either 
a primary email address (`mail`) or a proxy address (`proxyAddresses`) matching the specified value. 
It retrieves the `mail` and `proxyAddresses` properties for each matching object. Replace 
`youremail.com` with the actual email address you want to search for. Ensure the ActiveDirectory 
module is installed and that you have sufficient permissions to query AD objects.

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-12
Requires    : ActiveDirectory module (RSAT) installed
Usage       : Modify the filter values to the email address you want to search. Run in a session with AD privileges.
Example     : Search-ADObject -Properties mail, proxyAddresses -Filter {mail -eq "user@example.com" -or proxyAddresses -eq "smtp:user@example.com"}
#>

# Import Active Directory module
Import-Module ActiveDirectory

# Search AD objects by email or proxy address
$searchEmail = "youremail.com"

Get-ADObject -Properties mail, proxyAddresses -Filter {
    mail -eq $searchEmail -or proxyAddresses -eq "smtp:$searchEmail"
}
