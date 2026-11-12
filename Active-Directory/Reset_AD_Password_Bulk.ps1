#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Resets AD passwords to random values for any list of accounts and exports
    the new passwords to C:\temp.

.EXAMPLE
    .\Reset_AD_Password_Bulk.ps1 -Accounts 'user1','user2' -WhatIf
.EXAMPLE
    .\Reset_AD_Password_Bulk.ps1 -AccountListPath C:\temp\accounts.txt
.EXAMPLE
    .\Reset_AD_Password_Bulk.ps1 -AccountListPath C:\temp\accounts.txt -ChangePasswordAtLogon $false

.NOTES
    Run from an elevated PowerShell session with rights to reset passwords.

    Account list file format (accounts.txt) - one account per line, no quotes or commas.
    Each line can be a SamAccountName, Name or DisplayName. Blank lines are ignored.
    Example contents:

        Leasing [OTIS]
        Leasing [LAWRENCE HOUSE]
        Leasing [DUNCAN]
        Hall Lofts Leasing
        jsmith

    Tip: run with -WhatIf first to see which accounts match without changing anything.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    # One or more accounts (sAMAccountName, Name or DisplayName)
    [string[]]$Accounts,

    # Or a text file with one account per line
    [string]$AccountListPath,

    [int]$PasswordLength = 16,

    # $true = user must change password at next logon, $false = they keep it
    [bool]$ChangePasswordAtLogon = $true
)

if ($AccountListPath) {
    $Accounts = @(Get-Content -Path $AccountListPath | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
if (-not $Accounts -or $Accounts.Count -eq 0) {
    throw "No accounts supplied. Use -Accounts 'user1','user2' or -AccountListPath C:\temp\accounts.txt"
}

$OutDir  = 'C:\temp'
$OutFile = Join-Path $OutDir ("PasswordReset_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))

if (-not (Test-Path $OutDir)) {
    New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
}

function New-RandomPassword {
    param([int]$Length = 16)

    # Excludes look-alike characters (O,0,l,1,I) to make passwords easier to read
    $upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
    $lower   = 'abcdefghijkmnpqrstuvwxyz'.ToCharArray()
    $digits  = '23456789'.ToCharArray()
    $special = '!@#$%^&*-_=+?'.ToCharArray()
    $all     = $upper + $lower + $digits + $special

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    function Get-RandomIndex([int]$max) {
        $bytes = New-Object byte[] 4
        do {
            $rng.GetBytes($bytes)
            $val = [BitConverter]::ToUInt32($bytes, 0)
        } while ($val -ge ([uint32]::MaxValue - ([uint32]::MaxValue % $max)))
        return [int]($val % $max)
    }

    # Guarantee at least one of each character class
    $chars = @(
        $upper[(Get-RandomIndex $upper.Length)]
        $lower[(Get-RandomIndex $lower.Length)]
        $digits[(Get-RandomIndex $digits.Length)]
        $special[(Get-RandomIndex $special.Length)]
    )
    while ($chars.Count -lt $Length) {
        $chars += $all[(Get-RandomIndex $all.Length)]
    }

    # Shuffle (Fisher-Yates)
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $j = Get-RandomIndex ($i + 1)
        $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
    }
    $rng.Dispose()
    return -join $chars
}

$results = foreach ($acct in $Accounts) {
    $status   = 'Success'
    $password = ''
    $samName  = ''

    try {
        $safeName = $acct.Replace("'", "''")
        $found = @(Get-ADUser -Filter "SamAccountName -eq '$safeName' -or DisplayName -eq '$safeName' -or Name -eq '$safeName'" -ErrorAction Stop)
        if ($found.Count -eq 0) { throw "No AD user found with display name '$acct'" }
        if ($found.Count -gt 1) { throw "$($found.Count) users matched '$acct' - skipped to avoid resetting the wrong account" }
        $user = $found[0]
        $samName = $user.SamAccountName
        $password = New-RandomPassword -Length $PasswordLength
        $secure   = ConvertTo-SecureString -String $password -AsPlainText -Force

        if ($PSCmdlet.ShouldProcess($user.DistinguishedName, 'Reset password')) {
            Set-ADAccountPassword -Identity $user -NewPassword $secure -Reset -ErrorAction Stop
            Set-ADUser -Identity $user -ChangePasswordAtLogon $ChangePasswordAtLogon -ErrorAction Stop
        }
        else {
            $status = 'WhatIf'
        }
    }
    catch {
        $status   = "Failed: $($_.Exception.Message)"
        $password = ''
    }

    [pscustomobject]@{
        DisplayName    = $acct
        SamAccountName = $samName
        NewPassword    = $password
        Status         = $status
        Timestamp      = Get-Date -Format 's'
    }
}

if ($WhatIfPreference) {
    Write-Host "WhatIf mode: no passwords changed and no CSV written." -ForegroundColor Yellow
    $results | Format-Table DisplayName, SamAccountName, Status -AutoSize
    return
}

$results | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
Write-Host "Done. Results exported to $OutFile" -ForegroundColor Green
$results | Select-Object DisplayName, SamAccountName, Status | Format-Table -AutoSize
