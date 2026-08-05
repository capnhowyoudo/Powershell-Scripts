<#
.SYNOPSIS
    Checks when a single AD user's password was last changed, and (if security
    auditing is enabled) who performed the change.

    THIS VERSION IS DESIGNED TO JUST HIT "RUN" (F5) IN POWERSHELL ISE.
    Edit the three variables in the "SETTINGS" section below, then run.

.NOTES
    Part 2 (who changed it) only returns results if "Audit User Account
    Management" (Success) is enabled via Group Policy on your DCs. If that
    auditing isn't turned on, there's no log entry to find - that's a
    logging limitation, not a script bug.

    Requires: RSAT ActiveDirectory PowerShell module, and rights to read
    the Security event log on your DCs.
#>

# ======================= SETTINGS - EDIT THESE =========================
$SamAccountName   = "jdoe"     # <-- the username to check
$DaysBack         = 30         # <-- how many days back to search event logs
$DomainController = @()        # <-- optional: e.g. @("DC01","DC02"). Leave @() to check all DCs
# =========================================================================


# --- Setup -------------------------------------------------------------
try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "Could not load the ActiveDirectory module. Install RSAT: Install-WindowsFeature RSAT-AD-PowerShell (on servers) or add the 'RSAT: Active Directory' Windows capability (on Windows 10/11)."
    return
}

# --- Part 1: Basic password info from AD --------------------------------
Write-Host "`n=== AD Account Password Info: $SamAccountName ===" -ForegroundColor Cyan

try {
    $user = Get-ADUser -Identity $SamAccountName -Properties PasswordLastSet, PasswordNeverExpires, PasswordExpired, LockedOut, LastLogonDate, DistinguishedName -ErrorAction Stop
}
catch {
    Write-Error "Could not find user '$SamAccountName' in AD. $_"
    return
}

[PSCustomObject]@{
    SamAccountName       = $user.SamAccountName
    DistinguishedName    = $user.DistinguishedName
    PasswordLastSet      = $user.PasswordLastSet
    PasswordNeverExpires = $user.PasswordNeverExpires
    PasswordExpired      = $user.PasswordExpired
    LockedOut            = $user.LockedOut
    LastLogonDate        = $user.LastLogonDate
} | Format-List

# --- Part 2: Who changed it (requires auditing enabled on DCs) ----------
Write-Host "`n=== Searching Security logs for password change/reset events (last $DaysBack days) ===" -ForegroundColor Cyan

if (-not $DomainController -or $DomainController.Count -eq 0) {
    try {
        $DomainController = (Get-ADDomainController -Filter *).HostName
    }
    catch {
        Write-Warning "Could not enumerate domain controllers automatically. Set `$DomainController explicitly in the SETTINGS section above."
        $DomainController = @()
    }
}

$startTime = (Get-Date).AddDays(-$DaysBack)
$results = @()

foreach ($dc in $DomainController) {
    Write-Verbose "Querying $dc ..." -Verbose
    try {
        # 4723 = user changed their own password
        # 4724 = an attempt was made to reset an account's password (admin reset)
        $events = Get-WinEvent -ComputerName $dc -FilterHashtable @{
            LogName   = 'Security'
            Id        = 4723, 4724
            StartTime = $startTime
        } -ErrorAction Stop

        foreach ($event in $events) {
            $xml = [xml]$event.ToXml()
            $data = @{}
            foreach ($node in $xml.Event.EventData.Data) {
                $data[$node.Name] = $node.'#text'
            }

            # TargetUserName = whose password was changed
            # SubjectUserName = who performed the action
            if ($data['TargetUserName'] -and $data['TargetUserName'] -eq $SamAccountName) {
                $results += [PSCustomObject]@{
                    TimeCreated       = $event.TimeCreated
                    EventId           = $event.Id
                    Action            = if ($event.Id -eq 4723) { 'Self-service password change' } else { 'Password reset by another account' }
                    TargetUser        = $data['TargetUserName']
                    PerformedBy       = $data['SubjectUserName']
                    PerformedByDomain = $data['SubjectDomainName']
                    DomainController  = $dc
                }
            }
        }
    }
    catch [System.Diagnostics.Eventing.Reader.EventLogNotFoundException] {
        Write-Verbose "No matching events on $dc in the given window." -Verbose
    }
    catch {
        Write-Warning "Could not query $dc : $_"
    }
}

if ($results.Count -eq 0) {
    Write-Host "No 4723/4724 events found for '$SamAccountName' in the last $DaysBack days." -ForegroundColor Yellow
    Write-Host "This usually means either: the change happened outside this window, logs have rolled over, or 'Audit User Account Management' auditing is not enabled on your DCs." -ForegroundColor Yellow
}
else {
    $results | Sort-Object TimeCreated -Descending | Format-Table -AutoSize
}
