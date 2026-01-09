<#
.SYNOPSIS
Checks the password expiration date for a single Active Directory user.

.DESCRIPTION
This script retrieves the password expiration information for a specified
Active Directory user. It determines whether the user has a fine-grained
password policy applied; if not, it falls back to the default domain password
policy. If the account is configured so the password never expires, the script
reports that status. Otherwise, it calculates and displays the exact password
expiration date.
#>

Import-Module ActiveDirectory

$username = "username"

$user   = Get-ADUser $username -Properties PasswordLastSet, PasswordNeverExpires
$policy = Get-ADUserResultantPasswordPolicy $username

if (-not $policy) {
    $policy = Get-ADDefaultDomainPasswordPolicy
}

if ($user.PasswordNeverExpires) {
    Write-Output "Password never expires"
} else {
    $expires = $user.PasswordLastSet + $policy.MaxPasswordAge
    Write-Output "Password expires on: $expires"
}
