<#
.SYNOPSIS
    Reports on Active Directory password complexity/policy requirements,
    including the default domain policy, any Fine-Grained Password Policies (PSOs),
    and (optionally) the resultant effective policy for specific users.

.DESCRIPTION
    - Checks that the ActiveDirectory module is available and imports it.
    - Retrieves the default domain password policy.
    - Retrieves all Fine-Grained Password Policies (FGPPs) and who they apply to.
    - Optionally checks the resultant (effective) policy for one or more specified users.
    - Outputs a readable console report.
    - Exports CSV reports AND a single styled HTML report.
    - Reports are placed in C:\Temp by default.

.PARAMETER Domain
    Optional. Target domain (e.g. "contoso.com"). Defaults to current domain.

.PARAMETER Users
    Optional. One or more sAMAccountNames to check effective/resultant password policy for.

.PARAMETER ExportPath
    Optional. Folder path to export CSV/HTML reports to. Defaults to C:\Temp.
    The folder is created automatically if it doesn't exist.

.EXAMPLE
    .\Get-AD_Password_Policy_Report.ps1

.EXAMPLE
    .\Get-AD_Password_Policy_Report.ps1 -Domain "contoso.com" -Users "jsmith","adavis"

.EXAMPLE
    .\Get-AD_Password_Policy_Report.ps1 -Users "jsmith" -ExportPath "D:\Reports"

.NOTES
    Reference: What each password policy setting means

    ComplexityEnabled
        True/False. When True, passwords must contain characters from at least
        3 of these 4 categories: uppercase, lowercase, digits, special characters.
        This is a single bundled rule in AD - there is no separate setting to
        specifically require numbers or special characters on their own.

    MinPasswordLength
        Minimum number of characters required in a password.
        Common guidance: 12+ recommended (7-8 is considered weak by modern standards).

    PasswordHistoryCount
        Number of previous passwords remembered, preventing reuse until that many
        password changes have occurred.

    MaxPasswordAge
        How long a password is valid before it must be changed (password expiration).
        A value of 0 means passwords never expire.

    MinPasswordAge
        Minimum time that must pass after a password change before it can be
        changed again. Prevents users from rapidly cycling through history to
        reuse an old password.

    LockoutThreshold
        Number of failed logon attempts allowed before the account is locked out.
        A value of 0 means account lockout is DISABLED - unlimited attempts are
        allowed, which leaves accounts exposed to brute-force / password-spray
        attacks. Common guidance: 5-10.

    LockoutDuration
        How long an account stays locked out after hitting the threshold, before
        it unlocks automatically. Not meaningful when LockoutThreshold is 0.

    LockoutObservationWindow
        The time window during which failed attempts are counted toward the
        LockoutThreshold. After this window passes with no new failures, the
        failed-attempt counter resets. Not meaningful when LockoutThreshold is 0.

    ReversibleEncryptionEnabled
        True/False. When True, passwords are stored in a form that can be
        decrypted (not just hashed), which is a significant security weakness.
        Should almost always be False.

    Example baseline worth flagging as risky:
        LockoutThreshold = 0            -> no brute-force protection
        MinPasswordLength < 12          -> weak by current standards
        ReversibleEncryptionEnabled = True -> passwords not securely stored
#>

[CmdletBinding()]
param(
    [string]$Domain,
    [string[]]$Users,
    [string]$ExportPath = "C:\Temp"
)

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
}

# --- 0. Ensure export folder exists ---
if (-not (Test-Path -Path $ExportPath)) {
    try {
        New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
        Write-Host "Created report folder: $ExportPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Could not create export folder '$ExportPath': $($_.Exception.Message)"
        return
    }
}

# --- 1. Ensure ActiveDirectory module is available ---
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "ActiveDirectory module not found. Install RSAT: Active Directory tools on this machine and re-run."
    return
}
Import-Module ActiveDirectory -ErrorAction Stop

# Containers used to build the HTML report at the end
$htmlSections = @()
$reportProps = @(
    'ComplexityEnabled','MinPasswordLength','PasswordHistoryCount','MaxPasswordAge',
    'MinPasswordAge','LockoutThreshold','LockoutDuration','LockoutObservationWindow',
    'ReversibleEncryptionEnabled'
)

# --- 2. Default Domain Password Policy ---
Write-Section "Default Domain Password Policy"

$defaultPolicy = $null
try {
    if ($Domain) {
        $defaultPolicy = Get-ADDefaultDomainPasswordPolicy -Identity $Domain
    } else {
        $defaultPolicy = Get-ADDefaultDomainPasswordPolicy
    }

    $defaultPolicy | Select-Object $reportProps | Format-List

    $defaultPolicy | Select-Object $reportProps |
        Export-Csv -Path (Join-Path $ExportPath "DefaultDomainPasswordPolicy.csv") -NoTypeInformation

    $htmlSections += ($defaultPolicy | Select-Object $reportProps |
        ConvertTo-Html -Fragment -PreContent "<h2>Default Domain Password Policy</h2>")
}
catch {
    Write-Warning "Could not retrieve default domain password policy: $($_.Exception.Message)"
    $htmlSections += "<h2>Default Domain Password Policy</h2><p class='err'>Error: $($_.Exception.Message)</p>"
}

# --- 3. Fine-Grained Password Policies (PSOs) ---
Write-Section "Fine-Grained Password Policies (PSOs)"

try {
    $fgpps = Get-ADFineGrainedPasswordPolicy -Filter * -Properties AppliesTo

    if ($fgpps) {
        $fgppRows = @()

        foreach ($policy in $fgpps) {
            Write-Host ""
            Write-Host ("--- Policy: {0} (Precedence: {1}) ---" -f $policy.Name, $policy.Precedence) -ForegroundColor Yellow

            $policy | Select-Object (@('Name','Precedence') + $reportProps) | Format-List

            $appliesToNames = @()
            if ($policy.AppliesTo) {
                Write-Host "Applies to:" -ForegroundColor DarkGray
                foreach ($dn in $policy.AppliesTo) {
                    try {
                        $obj = Get-ADObject -Identity $dn -Properties Name
                        Write-Host ("  - {0}" -f $obj.Name)
                        $appliesToNames += $obj.Name
                    }
                    catch {
                        Write-Host ("  - {0} (could not resolve)" -f $dn)
                        $appliesToNames += $dn
                    }
                }
            }

            $row = $policy | Select-Object (@('Name','Precedence') + $reportProps)
            $row | Add-Member -NotePropertyName AppliesTo -NotePropertyValue ($appliesToNames -join "; ")
            $fgppRows += $row
        }

        $fgppRows | Export-Csv -Path (Join-Path $ExportPath "FineGrainedPasswordPolicies.csv") -NoTypeInformation

        $htmlSections += ($fgppRows | ConvertTo-Html -Fragment -PreContent "<h2>Fine-Grained Password Policies (PSOs)</h2>")
    }
    else {
        Write-Host "No Fine-Grained Password Policies found in this domain." -ForegroundColor Green
        $htmlSections += "<h2>Fine-Grained Password Policies (PSOs)</h2><p>None found in this domain.</p>"
    }
}
catch {
    Write-Warning "Could not retrieve Fine-Grained Password Policies: $($_.Exception.Message)"
    $htmlSections += "<h2>Fine-Grained Password Policies (PSOs)</h2><p class='err'>Error: $($_.Exception.Message)</p>"
}

# --- 4. Resultant (Effective) Policy for Specific Users ---
if ($Users) {
    Write-Section "Resultant Password Policy for Specified Users"

    $userResults = @()

    foreach ($user in $Users) {
        try {
            $resultant = Get-ADUserResultantPasswordPolicy -Identity $user

            if ($resultant) {
                Write-Host ""
                Write-Host ("--- User: {0} (governed by an FGPP) ---" -f $user) -ForegroundColor Yellow
                $resultant | Select-Object $reportProps | Format-List

                $row = $resultant | Select-Object $reportProps
                $row | Add-Member -NotePropertyName User -NotePropertyValue $user
                $row | Add-Member -NotePropertyName PolicySource -NotePropertyValue "Fine-Grained Policy"
                $userResults += $row
            }
            else {
                Write-Host ""
                Write-Host ("--- User: {0} (no FGPP applies; default domain policy in effect) ---" -f $user) -ForegroundColor DarkGray

                $row = $defaultPolicy | Select-Object $reportProps
                $row | Add-Member -NotePropertyName User -NotePropertyValue $user
                $row | Add-Member -NotePropertyName PolicySource -NotePropertyValue "Default Domain Policy"
                $userResults += $row
            }
        }
        catch {
            Write-Warning ("Could not evaluate resultant policy for '{0}': {1}" -f $user, $_.Exception.Message)
        }
    }

    if ($userResults) {
        $orderedCols = @('User','PolicySource') + $reportProps
        $userResults | Select-Object $orderedCols |
            Export-Csv -Path (Join-Path $ExportPath "UserResultantPasswordPolicy.csv") -NoTypeInformation

        $htmlSections += ($userResults | Select-Object $orderedCols |
            ConvertTo-Html -Fragment -PreContent "<h2>Resultant Password Policy for Specified Users</h2>")
    }
}

# --- 5. Build combined HTML report ---
$htmlHead = @"
<style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 30px; color: #222; background: #f7f8fa; }
    h1 { color: #1a3c6e; border-bottom: 3px solid #1a3c6e; padding-bottom: 8px; }
    h2 { color: #1a3c6e; margin-top: 40px; }
    table { border-collapse: collapse; width: 100%; margin-top: 10px; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
    th { background: #1a3c6e; color: #fff; text-align: left; padding: 8px 12px; }
    td { padding: 8px 12px; border-bottom: 1px solid #e0e0e0; }
    tr:nth-child(even) { background: #f2f5fa; }
    .meta { color: #555; font-size: 0.9em; margin-bottom: 20px; }
    .err { color: #b00020; font-weight: bold; }
</style>
"@

$reportTitle = if ($Domain) { $Domain } else { $env:USERDNSDOMAIN }
$generatedOn = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$htmlBody = "<h1>AD Password Policy Report</h1>" +
            "<p class='meta'>Domain: $reportTitle &nbsp;|&nbsp; Generated: $generatedOn</p>" +
            ($htmlSections -join "`n")

$htmlReport = ConvertTo-Html -Head $htmlHead -Body $htmlBody -Title "AD Password Policy Report"
$htmlPath = Join-Path $ExportPath "ADPasswordPolicyReport.html"
$htmlReport | Out-File -FilePath $htmlPath -Encoding utf8

Write-Host ""
Write-Host "Report complete." -ForegroundColor Green
Write-Host "CSV files exported to: $ExportPath" -ForegroundColor Green
Write-Host "HTML report saved to: $htmlPath" -ForegroundColor Green
