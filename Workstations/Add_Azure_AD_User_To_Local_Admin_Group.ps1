<#
.SYNOPSIS
Adds an Azure AD (Microsoft Entra ID) user to the local Administrators group.

.DESCRIPTION
Uses the net localgroup command to add the specified Azure AD user account
to the local Administrators group, granting local administrative privileges
on the device.

.PARAMETER UserUpn
The Azure AD User Principal Name (UPN) of the user to add.

.EXAMPLE
net localgroup administrators /add "AzureAD\jdoe@contoso.com"

.NOTES
- Must be run from an elevated PowerShell session.
- The device must be Azure AD (Microsoft Entra ID) joined.
- Adding a user to the local Administrators group grants full administrative control.
#>

net localgroup administrators /add "AzureAD\UserUpn"
