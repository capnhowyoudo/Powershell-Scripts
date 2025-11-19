<#
.SYNOPSIS
Retrieves the creation date of an Active Directory user account.

.DESCRIPTION
This script uses the Get-ADUser cmdlet to fetch the 'whenCreated' property of a specified Active Directory user account.
The username is defined inside the script as a variable.

.NOTES
Author: capnhowyoudo
Date: 2025-11-19
Requires: ActiveDirectory module
#>

# Variables
$ADModule = "ActiveDirectory"  # Module name
$Username = "jdoe"            # Username to query

# Import AD module if not already imported
Import-Module $ADModule -ErrorAction SilentlyContinue

# Retrieve user creation date
$UserInfo = Get-ADUser -Identity $Username -Properties whenCreated | Select-Object Name, whenCreated

# Display result
$UserInfo
