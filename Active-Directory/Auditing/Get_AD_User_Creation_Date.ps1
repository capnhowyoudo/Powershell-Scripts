<#
.SYNOPSIS
    Displays the creation date of a specified Active Directory user account.

.DESCRIPTION
    This script retrieves an Active Directory user object based on the provided username
    and shows the account's creation date (`whenCreated`) along with the username.
    The output is formatted as a list for readability.

.NOTES
    - Requires ActiveDirectory module (RSAT or Domain Controller)
    - Run as a domain account with read access to the target user
    - Replace <UserName> with the SamAccountName of the user you want to query
    - Example usage:
        Get_AD_User_Creation_Date.ps1
        Get-ADUser jdoe -Properties whenCreated | Format-List Name,whenCreated
    - You can export the output to CSV if needed:
        Get-ADUser jdoe -Properties whenCreated | 
        Select-Object Name, whenCreated | Export-Csv C:\Temp\UserCreationDate.csv -NoTypeInformation
#>

# Replace <UserName> with the actual SamAccountName of the user
Get-ADUser <UserName> -Properties whenCreated | Format-List Name,whenCreated
