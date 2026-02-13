<#
.SYNOPSIS
    Retrieves an Active Directory user object based on a specific email address.

.DESCRIPTION
    This script uses the Get-ADUser cmdlet to search the Active Directory 'mail' attribute. 
    It returns the user's primary identity along with the specified 'mail' and 'displayName' 
    properties. This is the most efficient way to locate a user when only their primary 
    SMTP address is known.

.NOTES
    - Requires the RSAT (Remote Server Administration Tools) Active Directory module.
    - The search is performed against the 'mail' attribute, which typically holds the 
      primary SMTP address. It does not search secondary aliases (proxyAddresses).
    - Ensure you have the necessary permissions to read user objects in the target OU/domain.
#>

Get-ADUser -Filter "mail -eq 'user@example.com'" -Properties mail, displayName
