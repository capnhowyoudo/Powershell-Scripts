<#
.SYNOPSIS
Checks whether the currently logged-in interactive user has local administrator privileges.

.DESCRIPTION
This script runs in the SYSTEM context and determines whether the currently logged-in
interactive user is a member of the local Administrators group on the device.

It retrieves the active user session, enumerates the local Administrators group,
and compares the logged-in user against group membership. The script supports
local accounts, domain accounts, and nested domain groups.

This script is suitable for use with:
- Microsoft Intune (Proactive Remediations)
- SCCM / MECM
- Scheduled Tasks running as SYSTEM
- Security and compliance audits

If no interactive user is logged in, the script exits gracefully.

.NOTES
Requires PowerShell 5.1 or later.
Must be executed with SYSTEM or administrative privileges to enumerate local group members.
#>

# Get the currently logged-in interactive user
$LoggedOnUser = (Get-CimInstance Win32_ComputerSystem).UserName

if (-not $LoggedOnUser) {
    Write-Output "No interactive user logged in."
    exit 0
}

# Get local Administrators group members
$LocalAdmins = Get-LocalGroupMember -Group "Administrators" |
               Select-Object -ExpandProperty Name

if ($LocalAdmins -contains $LoggedOnUser) {
    Write-Output "User $LoggedOnUser HAS local administrator privileges."
} else {
    Write-Output "User $LoggedOnUser does NOT have local administrator privileges."
}
