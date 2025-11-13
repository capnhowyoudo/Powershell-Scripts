<#
.Synopsis
    This script identifies all disabled user accounts in Active Directory and removes them from their group memberships, excluding the "Domain Users" group. The removal process is simulated with the '-WhatIf' parameter to avoid accidental changes during testing.

.Description
    This PowerShell script automates the cleanup of group memberships for disabled users in Active Directory (AD). It queries all user accounts that are disabled (i.e., where the "Enabled" property is set to 'False') and retrieves the groups they belong to. For each group, the script removes the disabled user, except for the "Domain Users" group, which is excluded to avoid accidental removal of all domain users from this default group.
    
    The removal action is simulated using the '-WhatIf' parameter, which allows for testing without making any changes. Once confirmed, the '-WhatIf' parameter can be removed to perform the actual removal of users from their groups.
    
    All activities are logged to a text file for auditing purposes, ensuring that changes can be tracked.

.Notes
    Requires: Active Directory module for PowerShell
    Tested On: [Version of Windows Server/Active Directory, etc.]
    Log File Path: C:\temp\Disabled_Rmeoval_Groups.txt
    Use with caution. Test with '-WhatIf' before removing the '-WhatIf' parameter to perform actual removals.
    Excludes the "Domain Users" group from removal to prevent accidental modification of this default group.
#>

# Start Logging Transcript
Start-Transcript -Append C:\temp\Disabled_Rmeoval_Groups.txt

# Import the Active Directory module if not already loaded
Import-Module ActiveDirectory

# Get all disabled user accounts and their group memberships
$DisabledUsers = Get-ADUser -Filter "Enabled -eq 'False'" -Properties MemberOf

# Loop through each disabled user
foreach ($User in $DisabledUsers) {
    Write-Host "Processing disabled user: $($User.SamAccountName)"

    # Get all groups the user is a member of
    $Groups = Get-ADPrincipalGroupMembership -Identity $User

    # Loop through each group and remove the user, excluding "Domain Users"
    # The Remove-ADGroupMember cmdlet is simulated with '-WhatIf' for testing
    foreach ($Group in $Groups) {
        if ($Group.Name -ne "Domain Users") {
            Write-Host "Removing $($User.SamAccountName) from group: $($Group.Name)"
            Remove-ADGroupMember -Identity $Group -Members $User -Confirm:$false -WhatIf
        }
    }
}

Write-Host "Group membership removal for disabled users complete."
