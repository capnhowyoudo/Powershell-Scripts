<#
.SYNOPSIS
    Retrieves the Security Identifier (SID) for a specified Active Directory user.

.DESCRIPTION
    This script uses the Active Directory PowerShell module to find a user's 
    ObjectSID based on their Identity (SamAccountName, DistinguishedName, GUID, or SID).
    It outputs the user's Display Name and SID string to the console.

.NOTES
    Name: Get_AD_Users_SID.ps1
    Requirements: Active Directory PowerShell module (RSAT).
    Permissions: Requires read access to the Active Directory domain.
    Replace jdoe with username of user.
#>

Get-ADUser -Identity "jdoe" | Select-Object Name, SID
