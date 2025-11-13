<#
.SYNOPSIS
Copies selected Active Directory user attributes and group memberships from one user to another.

.DESCRIPTION
This script retrieves a source AD user and a target AD user, then copies specified attributes 
(such as department, title, office, phone number, address, company, description, and manager) 
from the source user to the target user. Additionally, it can copy the group memberships of the 
source user to the target user, excluding the default "Domain Users" group. 

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-12
Requires    : ActiveDirectory module (RSAT) installed
Usage       : Modify $sourceUser and $targetUser to the distinguished names (DNs) of the users.
             Ensure you have sufficient permissions to update AD user attributes and group memberships.
#>

# ---------------------------
# Variables
# ---------------------------
$sourceUser = "CN=John Doe,OU=Users,DC=fakedomain,DC=local"
$targetUser = "CN=Jane Smith,OU=Users,DC=fakedomain,DC=local"

# ---------------------------
# Get source and target user objects
# ---------------------------
$source = Get-ADUser -Identity $sourceUser -Properties *
$target = Get-ADUser -Identity $targetUser -Properties *

# ---------------------------
# List of attributes to copy
# ---------------------------
$attributesToCopy = @(
    "department", "title", "office", "telephoneNumber",
    "streetAddress", "city", "postalCode", "state",
    "company", "description", "manager"
)

# ---------------------------
# Copy each attribute
# ---------------------------
foreach ($attr in $attributesToCopy) {
    if ($source.$attr) {
        Set-ADUser -Identity $target -Replace @{ $attr = $source.$attr }
        Write-Host "Copied $attr"
    }
}

# ---------------------------
# Copy group memberships (optional)
# ---------------------------
$groups = Get-ADPrincipalGroupMembership $source | Where-Object { $_.Name -notlike "Domain Users" }
foreach ($group in $groups) {
    Add-ADGroupMember -Identity $group -Members $target -ErrorAction SilentlyContinue
    Write-Host "Added $($group.Name) to target user"
}

Write-Host "User profile copy complete."
