#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Comprehensive Active Directory Inventory Report
    Exports Users, Computers, and Groups with creation dates,
    last logon dates (for Users & Computers), and key attributes.

.DESCRIPTION
    Generates three CSV reports and one summary HTML report:
      - ADInventory_Users.csv
      - ADInventory_Computers.csv
      - ADInventory_Groups.csv
      - ADInventory_Summary.html

    Run as a domain user with at least Read access to AD objects.
    For accurate LastLogon data, run on a Domain Controller or
    ensure replication is current (LastLogonDate is replicated;
    LastLogon is DC-local only).

.PARAMETER OutputPath
    Folder where all report files are saved.
    Defaults to the current directory.

.PARAMETER SearchBase
    The Distinguished Name to start searching from.
    Defaults to the whole domain root (automatic).

.EXAMPLE
    .\Comprehensive_Active_Directory_Inventory_Report.ps1

.EXAMPLE
    .\Comprehensive_Active_Directory_Inventory_Report.ps1 -OutputPath "C:\Reports" -SearchBase "OU=Corporate,DC=contoso,DC=com"
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$OutputPath = (Get-Location).Path,

    [Parameter()]
    [string]$SearchBase = ""
)

#region ── Helpers ──────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "`n[$([datetime]::Now.ToString('HH:mm:ss'))] $Message" -ForegroundColor $Color
}

function ConvertFrom-ADFileTime {
    <#
    Converts a raw AD FileTime integer to a readable datetime string.
    Returns "Never" for 0 / 9223372036854775807 (max int64).
    #>
    param([long]$FileTime)
    if ($FileTime -le 0 -or $FileTime -eq [long]::MaxValue) { return "Never" }
    try { return [datetime]::FromFileTime($FileTime).ToString("yyyy-MM-dd HH:mm:ss") }
    catch { return "Never" }
}

function Ensure-OutputPath {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Step "Created output folder: $Path" "Yellow"
    }
}

#endregion

#region ── Preflight ────────────────────────────────────────────────────────────

Write-Step "Starting AD Inventory Script" "Green"

# Verify the ActiveDirectory module is available
if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
    Write-Error "ActiveDirectory module not found. Install RSAT or run on a Domain Controller."
    exit 1
}
Import-Module ActiveDirectory -ErrorAction Stop

Ensure-OutputPath -Path $OutputPath

# Resolve domain root if no SearchBase provided
if ([string]::IsNullOrWhiteSpace($SearchBase)) {
    $SearchBase = (Get-ADDomain).DistinguishedName
    Write-Step "SearchBase: $SearchBase"
}

$timestamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$usersFile      = Join-Path $OutputPath "ADInventory_Users_$timestamp.csv"
$computersFile  = Join-Path $OutputPath "ADInventory_Computers_$timestamp.csv"
$groupsFile     = Join-Path $OutputPath "ADInventory_Groups_$timestamp.csv"
$summaryFile    = Join-Path $OutputPath "ADInventory_Summary_$timestamp.html"

#endregion

#region ── USERS ────────────────────────────────────────────────────────────────

Write-Step "Querying AD Users..."

$userProperties = @(
    'SamAccountName', 'DisplayName', 'GivenName', 'Surname',
    'UserPrincipalName', 'EmailAddress', 'Title', 'Department',
    'Company', 'Manager', 'DistinguishedName', 'Enabled',
    'Created', 'Modified', 'LastLogonDate', 'LastLogon',
    'BadLogonCount', 'LockedOut', 'PasswordNeverExpires',
    'PasswordLastSet', 'AccountExpirationDate',
    'MemberOf', 'Description', 'Office', 'TelephoneNumber',
    'whenCreated'
)

try {
    $allUsers = Get-ADUser -Filter * -SearchBase $SearchBase `
                           -Properties $userProperties `
                           -ErrorAction Stop
} catch {
    Write-Error "Failed to query AD Users: $_"
    $allUsers = @()
}

Write-Step "Processing $($allUsers.Count) users..."

$userReport = foreach ($user in $allUsers) {

    # Manager display name (resolve DN → Name)
    $managerName = if ($user.Manager) {
        try { (Get-ADUser $user.Manager -Properties DisplayName).DisplayName }
        catch { $user.Manager }
    } else { "" }

    # Group memberships (comma-separated CN values)
    $groups = if ($user.MemberOf) {
        ($user.MemberOf | ForEach-Object {
            ($_ -split ',')[0] -replace '^CN=', ''
        }) -join '; '
    } else { "" }

    # LastLogon is DC-local; LastLogonDate is replicated – use whichever is more recent
    $lastLogonRaw  = ConvertFrom-ADFileTime -FileTime $user.LastLogon
    $lastLogonDate = if ($user.LastLogonDate) {
        $user.LastLogonDate.ToString("yyyy-MM-dd HH:mm:ss")
    } else { "Never" }

    [PSCustomObject]@{
        SamAccountName       = $user.SamAccountName
        DisplayName          = $user.DisplayName
        FirstName            = $user.GivenName
        LastName             = $user.Surname
        UserPrincipalName    = $user.UserPrincipalName
        EmailAddress         = $user.EmailAddress
        Title                = $user.Title
        Department           = $user.Department
        Company              = $user.Company
        Manager              = $managerName
        Office               = $user.Office
        Phone                = $user.TelephoneNumber
        Description          = $user.Description
        Enabled              = $user.Enabled
        LockedOut            = $user.LockedOut
        PasswordNeverExpires = $user.PasswordNeverExpires
        PasswordLastSet      = if ($user.PasswordLastSet) { $user.PasswordLastSet.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
        AccountExpiration    = if ($user.AccountExpirationDate) { $user.AccountExpirationDate.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
        CreationDate         = if ($user.Created) { $user.Created.ToString("yyyy-MM-dd HH:mm:ss") } else { $user.whenCreated }
        LastModified         = if ($user.Modified) { $user.Modified.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
        LastLogonDate        = $lastLogonDate
        LastLogon_DCLocal    = $lastLogonRaw
        BadLogonCount        = $user.BadLogonCount
        GroupMemberships     = $groups
        OU                   = ($user.DistinguishedName -replace '^CN=[^,]+,', '')
        DistinguishedName    = $user.DistinguishedName
    }
}

$userReport | Export-Csv -Path $usersFile -NoTypeInformation -Encoding UTF8
Write-Step "Users exported → $usersFile" "Green"

#endregion

#region ── COMPUTERS ────────────────────────────────────────────────────────────

Write-Step "Querying AD Computers..."

$computerProperties = @(
    'Name', 'DNSHostName', 'IPv4Address', 'OperatingSystem',
    'OperatingSystemVersion', 'OperatingSystemServicePack',
    'Description', 'Enabled', 'Created', 'Modified',
    'LastLogonDate', 'LastLogon', 'DistinguishedName',
    'ManagedBy', 'Location', 'whenCreated'
)

try {
    $allComputers = Get-ADComputer -Filter * -SearchBase $SearchBase `
                                   -Properties $computerProperties `
                                   -ErrorAction Stop
} catch {
    Write-Error "Failed to query AD Computers: $_"
    $allComputers = @()
}

Write-Step "Processing $($allComputers.Count) computers..."

$computerReport = foreach ($comp in $allComputers) {

    $managedByName = if ($comp.ManagedBy) {
        try { (Get-ADUser $comp.ManagedBy -Properties DisplayName).DisplayName }
        catch { $comp.ManagedBy }
    } else { "" }

    $lastLogonRaw  = ConvertFrom-ADFileTime -FileTime $comp.LastLogon
    $lastLogonDate = if ($comp.LastLogonDate) {
        $comp.LastLogonDate.ToString("yyyy-MM-dd HH:mm:ss")
    } else { "Never" }

    # Infer device type from OS name
    $osName  = $comp.OperatingSystem
    $devType = switch -Wildcard ($osName) {
        "*Server*"    { "Server" }
        "*Windows 1*" { "Workstation" }
        "*Windows 7*" { "Workstation (Legacy)" }
        "*Windows 8*" { "Workstation (Legacy)" }
        default       { if ($osName) { "Other" } else { "Unknown" } }
    }

    [PSCustomObject]@{
        ComputerName           = $comp.Name
        DNSHostName            = $comp.DNSHostName
        IPv4Address            = $comp.IPv4Address
        DeviceType             = $devType
        OperatingSystem        = $comp.OperatingSystem
        OSVersion              = $comp.OperatingSystemVersion
        OSServicePack          = $comp.OperatingSystemServicePack
        Description            = $comp.Description
        Location               = $comp.Location
        ManagedBy              = $managedByName
        Enabled                = $comp.Enabled
        CreationDate           = if ($comp.Created) { $comp.Created.ToString("yyyy-MM-dd HH:mm:ss") } else { $comp.whenCreated }
        LastModified           = if ($comp.Modified) { $comp.Modified.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
        LastLogonDate          = $lastLogonDate
        LastLogon_DCLocal      = $lastLogonRaw
        OU                     = ($comp.DistinguishedName -replace '^CN=[^,]+,', '')
        DistinguishedName      = $comp.DistinguishedName
    }
}

$computerReport | Export-Csv -Path $computersFile -NoTypeInformation -Encoding UTF8
Write-Step "Computers exported → $computersFile" "Green"

#endregion

#region ── GROUPS ───────────────────────────────────────────────────────────────

Write-Step "Querying AD Groups..."

$groupProperties = @(
    'Name', 'SamAccountName', 'GroupCategory', 'GroupScope',
    'Description', 'ManagedBy', 'Members', 'MemberOf',
    'Created', 'Modified', 'DistinguishedName', 'whenCreated',
    'mail'
)

try {
    $allGroups = Get-ADGroup -Filter * -SearchBase $SearchBase `
                             -Properties $groupProperties `
                             -ErrorAction Stop
} catch {
    Write-Error "Failed to query AD Groups: $_"
    $allGroups = @()
}

Write-Step "Processing $($allGroups.Count) groups..."

$groupReport = foreach ($grp in $allGroups) {

    $managedByName = if ($grp.ManagedBy) {
        try { (Get-ADUser $grp.ManagedBy -Properties DisplayName).DisplayName }
        catch {
            try { (Get-ADGroup $grp.ManagedBy).Name }
            catch { $grp.ManagedBy }
        }
    } else { "" }

    $memberCount   = if ($grp.Members) { $grp.Members.Count } else { 0 }

    $memberOfNames = if ($grp.MemberOf) {
        ($grp.MemberOf | ForEach-Object {
            ($_ -split ',')[0] -replace '^CN=', ''
        }) -join '; '
    } else { "" }

    [PSCustomObject]@{
        GroupName         = $grp.Name
        SamAccountName    = $grp.SamAccountName
        GroupCategory     = $grp.GroupCategory    # Security / Distribution
        GroupScope        = $grp.GroupScope        # DomainLocal / Global / Universal
        EmailAddress      = $grp.mail
        Description       = $grp.Description
        ManagedBy         = $managedByName
        MemberCount       = $memberCount
        MemberOf          = $memberOfNames
        CreationDate      = if ($grp.Created) { $grp.Created.ToString("yyyy-MM-dd HH:mm:ss") } else { $grp.whenCreated }
        LastModified      = if ($grp.Modified) { $grp.Modified.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
        OU                = ($grp.DistinguishedName -replace '^CN=[^,]+,', '')
        DistinguishedName = $grp.DistinguishedName
    }
}

$groupReport | Export-Csv -Path $groupsFile -NoTypeInformation -Encoding UTF8
Write-Step "Groups exported → $groupsFile" "Green"

#endregion

#region ── HTML SUMMARY ─────────────────────────────────────────────────────────

Write-Step "Generating HTML Summary Report..."

# ── Calculated stats ──────────────────────────────────────────────────────────
$enabledUsers     = ($userReport | Where-Object { $_.Enabled -eq $true }).Count
$disabledUsers    = ($userReport | Where-Object { $_.Enabled -eq $false }).Count
$lockedUsers      = ($userReport | Where-Object { $_.LockedOut -eq $true }).Count
$neverLoggedOn    = ($userReport | Where-Object { $_.LastLogonDate -eq "Never" }).Count

$enabledComputers = ($computerReport | Where-Object { $_.Enabled -eq $true }).Count
$disabledComps    = ($computerReport | Where-Object { $_.Enabled -eq $false }).Count
$staleComputers   = ($computerReport | Where-Object {
    $_.LastLogonDate -ne "Never" -and
    [datetime]::ParseExact($_.LastLogonDate, "yyyy-MM-dd HH:mm:ss", $null) -lt (Get-Date).AddDays(-90)
}).Count

$securityGroups   = ($groupReport | Where-Object { $_.GroupCategory -eq "Security" }).Count
$distGroups       = ($groupReport | Where-Object { $_.GroupCategory -eq "Distribution" }).Count

$domainInfo  = Get-ADDomain
$forestInfo  = Get-ADForest
$reportDate  = Get-Date -Format "dddd, MMMM dd yyyy  HH:mm:ss"

# ── Build HTML ────────────────────────────────────────────────────────────────
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>AD Inventory Summary – $($domainInfo.DNSRoot)</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', Arial, sans-serif; background: #f0f2f5; color: #222; }
  header { background: #003087; color: #fff; padding: 28px 36px; }
  header h1 { font-size: 1.8rem; font-weight: 700; }
  header p  { font-size: 0.9rem; opacity: .8; margin-top: 4px; }
  .container { max-width: 1100px; margin: 30px auto; padding: 0 20px; }

  /* Stat cards */
  .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 30px; }
  .card { background: #fff; border-radius: 8px; padding: 20px 24px; box-shadow: 0 2px 6px rgba(0,0,0,.08); border-top: 4px solid #0066cc; }
  .card.green  { border-top-color: #28a745; }
  .card.orange { border-top-color: #fd7e14; }
  .card.red    { border-top-color: #dc3545; }
  .card.purple { border-top-color: #6f42c1; }
  .card h3 { font-size: 0.75rem; text-transform: uppercase; letter-spacing: .05em; color: #666; margin-bottom: 8px; }
  .card .value { font-size: 2rem; font-weight: 700; color: #003087; }
  .card .sub   { font-size: 0.78rem; color: #888; margin-top: 4px; }

  /* Section tables */
  .section { background: #fff; border-radius: 8px; box-shadow: 0 2px 6px rgba(0,0,0,.08); margin-bottom: 30px; overflow: hidden; }
  .section-header { background: #003087; color: #fff; padding: 14px 22px; font-size: 1rem; font-weight: 600; }
  .section-header span { font-weight: 400; font-size: 0.85rem; opacity: .7; margin-left: 8px; }
  table { width: 100%; border-collapse: collapse; font-size: 0.82rem; }
  th { background: #eef3fb; padding: 10px 14px; text-align: left; border-bottom: 2px solid #ccd9f0; color: #003087; font-weight: 600; }
  td { padding: 9px 14px; border-bottom: 1px solid #eee; }
  tr:last-child td { border-bottom: none; }
  tr:nth-child(even) td { background: #f8f9fc; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 0.72rem; font-weight: 600; }
  .badge-enabled  { background: #d4edda; color: #155724; }
  .badge-disabled { background: #f8d7da; color: #721c24; }
  .badge-security { background: #d1ecf1; color: #0c5460; }
  .badge-dist     { background: #fff3cd; color: #856404; }
  .never { color: #aaa; font-style: italic; }

  footer { text-align: center; font-size: 0.78rem; color: #888; padding: 20px; }
</style>
</head>
<body>
<header>
  <h1>&#x1F5C2; Active Directory Inventory</h1>
  <p>Domain: <strong>$($domainInfo.DNSRoot)</strong> &nbsp;|&nbsp; Forest: <strong>$($forestInfo.Name)</strong> &nbsp;|&nbsp; Generated: $reportDate</p>
</header>

<div class="container">

  <!-- Summary cards -->
  <div class="cards">
    <div class="card">
      <h3>Total Users</h3>
      <div class="value">$($userReport.Count)</div>
      <div class="sub">$enabledUsers enabled &bull; $disabledUsers disabled</div>
    </div>
    <div class="card red">
      <h3>Locked Out</h3>
      <div class="value">$lockedUsers</div>
      <div class="sub">Users currently locked out</div>
    </div>
    <div class="card orange">
      <h3>Never Logged On</h3>
      <div class="value">$neverLoggedOn</div>
      <div class="sub">Users with no logon recorded</div>
    </div>
    <div class="card green">
      <h3>Total Computers</h3>
      <div class="value">$($computerReport.Count)</div>
      <div class="sub">$enabledComputers enabled &bull; $disabledComps disabled</div>
    </div>
    <div class="card orange">
      <h3>Stale Computers</h3>
      <div class="value">$staleComputers</div>
      <div class="sub">No logon in 90+ days</div>
    </div>
    <div class="card purple">
      <h3>Total Groups</h3>
      <div class="value">$($groupReport.Count)</div>
      <div class="sub">$securityGroups security &bull; $distGroups distribution</div>
    </div>
  </div>

  <!-- Users table (top 50 most recently active) -->
  <div class="section">
    <div class="section-header">
      &#x1F464; Users <span>(showing up to 50 most recently active)</span>
    </div>
    <table>
      <thead>
        <tr>
          <th>Username</th><th>Display Name</th><th>Department</th>
          <th>Status</th><th>Created</th><th>Last Logon</th><th>Password Last Set</th>
        </tr>
      </thead>
      <tbody>
"@

$topUsers = $userReport |
    Sort-Object { if ($_.LastLogonDate -ne "Never") { [datetime]::ParseExact($_.LastLogonDate,"yyyy-MM-dd HH:mm:ss",$null) } else { [datetime]::MinValue } } -Descending |
    Select-Object -First 50

foreach ($u in $topUsers) {
    $badge  = if ($u.Enabled) { '<span class="badge badge-enabled">Enabled</span>' } else { '<span class="badge badge-disabled">Disabled</span>' }
    $logon  = if ($u.LastLogonDate -eq "Never") { '<span class="never">Never</span>' } else { $u.LastLogonDate }
    $html += @"
        <tr>
          <td><strong>$($u.SamAccountName)</strong></td>
          <td>$($u.DisplayName)</td>
          <td>$($u.Department)</td>
          <td>$badge</td>
          <td>$($u.CreationDate)</td>
          <td>$logon</td>
          <td>$($u.PasswordLastSet)</td>
        </tr>
"@
}

$html += @"
      </tbody>
    </table>
  </div>

  <!-- Computers table (top 50) -->
  <div class="section">
    <div class="section-header">
      &#x1F4BB; Computers <span>(showing up to 50 most recently active)</span>
    </div>
    <table>
      <thead>
        <tr>
          <th>Computer Name</th><th>Type</th><th>Operating System</th>
          <th>Status</th><th>Created</th><th>Last Logon</th>
        </tr>
      </thead>
      <tbody>
"@

$topComputers = $computerReport |
    Sort-Object { if ($_.LastLogonDate -ne "Never") { [datetime]::ParseExact($_.LastLogonDate,"yyyy-MM-dd HH:mm:ss",$null) } else { [datetime]::MinValue } } -Descending |
    Select-Object -First 50

foreach ($c in $topComputers) {
    $badge = if ($c.Enabled) { '<span class="badge badge-enabled">Enabled</span>' } else { '<span class="badge badge-disabled">Disabled</span>' }
    $logon = if ($c.LastLogonDate -eq "Never") { '<span class="never">Never</span>' } else { $c.LastLogonDate }
    $html += @"
        <tr>
          <td><strong>$($c.ComputerName)</strong></td>
          <td>$($c.DeviceType)</td>
          <td>$($c.OperatingSystem)</td>
          <td>$badge</td>
          <td>$($c.CreationDate)</td>
          <td>$logon</td>
        </tr>
"@
}

$html += @"
      </tbody>
    </table>
  </div>

  <!-- Groups table -->
  <div class="section">
    <div class="section-header">
      &#x1F465; Groups <span>($($groupReport.Count) total)</span>
    </div>
    <table>
      <thead>
        <tr>
          <th>Group Name</th><th>Category</th><th>Scope</th>
          <th>Members</th><th>Managed By</th><th>Created</th><th>Last Modified</th>
        </tr>
      </thead>
      <tbody>
"@

foreach ($g in ($groupReport | Sort-Object GroupName)) {
    $cat = if ($g.GroupCategory -eq "Security") {
        '<span class="badge badge-security">Security</span>'
    } else {
        '<span class="badge badge-dist">Distribution</span>'
    }
    $html += @"
        <tr>
          <td><strong>$($g.GroupName)</strong></td>
          <td>$cat</td>
          <td>$($g.GroupScope)</td>
          <td>$($g.MemberCount)</td>
          <td>$($g.ManagedBy)</td>
          <td>$($g.CreationDate)</td>
          <td>$($g.LastModified)</td>
        </tr>
"@
}

$html += @"
      </tbody>
    </table>
  </div>

</div><!-- /container -->
<footer>
  AD Inventory &bull; Domain: $($domainInfo.DNSRoot) &bull; Generated $reportDate &bull;
  CSV files saved to: $OutputPath
</footer>
</body>
</html>
"@

$html | Out-File -FilePath $summaryFile -Encoding UTF8
Write-Step "HTML Summary exported → $summaryFile" "Green"

#endregion

#region ── Final Summary ────────────────────────────────────────────────────────

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  AD INVENTORY COMPLETE" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Domain       : $($domainInfo.DNSRoot)"
Write-Host "  Users        : $($userReport.Count) total  ($enabledUsers enabled, $disabledUsers disabled, $lockedUsers locked)"
Write-Host "  Computers    : $($computerReport.Count) total  ($enabledComputers enabled, $staleComputers stale >90d)"
Write-Host "  Groups       : $($groupReport.Count) total  ($securityGroups security, $distGroups distribution)"
Write-Host ""
Write-Host "  Output Files:"
Write-Host "    $usersFile"
Write-Host "    $computersFile"
Write-Host "    $groupsFile"
Write-Host "    $summaryFile"
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green

#endregion
