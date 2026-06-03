#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Analyzes a server to determine what roles and services it is actively performing.

.DESCRIPTION
    Checks for SMB shares, printer shares, SQL Server, Remote Desktop/Terminal Services,
    IIS/Web Server, DNS, DHCP, Active Directory, FTP, Remote Management, and more.
    Also performs a full Get-WindowsFeature sweep to catch every installed role and feature.
    Outputs results to the console and exports a self-contained HTML report.

.PARAMETER ComputerName
    The target server to analyze. Defaults to the local machine.

.PARAMETER Credential
    Optional credentials for remote connections.

.PARAMETER OutputPath
    Path for the HTML report. Defaults to C:\temp\ServerRoles_<ComputerName>_<date>.html

.EXAMPLE
    .\Get_Server_Roles.and_Audit.ps1
    .\Get_Server_Roles.and_Audit.ps1 -ComputerName "SERVER01"
    .\Get_Server_Roles.and_Audit.ps1 -ComputerName "SERVER01" -OutputPath "C:\Reports\server01.html"
    .\Get_Server_Roles.and_Audit.ps1 -ComputerName "SERVER01" -Credential (Get-Credential)
#>

[CmdletBinding()]
param(
    [string]$ComputerName = $env:COMPUTERNAME,
    [System.Management.Automation.PSCredential]$Credential,
    [string]$OutputPath = ""
)

# ─────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────

function Write-Header {
    param([string]$Title)
    $line = "=" * 60
    Write-Host "`n$line" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "$line" -ForegroundColor Cyan
}

function Write-Role {
    param([string]$Role, [string]$Status, [string]$Detail = "")
    $color  = if ($Status -eq "ACTIVE") { "Green" } elseif ($Status -eq "INSTALLED") { "Yellow" } else { "DarkGray" }
    $symbol = if ($Status -eq "ACTIVE") { "[+]" }   elseif ($Status -eq "INSTALLED") { "[~]" }    else { "[ ]" }
    $line   = "$symbol  {0,-35} {1}" -f $Role, $Status
    Write-Host $line -ForegroundColor $color
    if ($Detail) { Write-Host "       $Detail" -ForegroundColor Gray }
}

function Invoke-RemoteOrLocal {
    param([scriptblock]$ScriptBlock)
    try {
        if ($ComputerName -eq $env:COMPUTERNAME) {
            return & $ScriptBlock
        } else {
            $params = @{ ComputerName = $ComputerName; ScriptBlock = $ScriptBlock; ErrorAction = "Stop" }
            if ($Credential) { $params.Credential = $Credential }
            return Invoke-Command @params
        }
    } catch { return $null }
}

# HTML helpers
$script:htmlSections   = [System.Collections.Generic.List[string]]::new()
$script:htmlRoles      = [System.Collections.Generic.List[string]]::new()
$script:currentSection = ""
$script:currentRows    = [System.Collections.Generic.List[string]]::new()

function Html-OpenSection { param([string]$Title)
    $script:currentSection = $Title
    $script:currentRows    = [System.Collections.Generic.List[string]]::new()
}

function Html-AddRow { param([string]$Role, [string]$Status, [string]$Detail = "", [string[]]$SubItems = @())
    $badge = switch ($Status) {
        "ACTIVE"    { '<span class="badge active">ACTIVE</span>' }
        "INSTALLED" { '<span class="badge installed">INSTALLED</span>' }
        default     { '<span class="badge none">NONE</span>' }
    }
    $sub        = if ($SubItems) { "<ul class='subitems'>" + (($SubItems | ForEach-Object { "<li>$_</li>" }) -join "") + "</ul>" } else { "" }
    $detailHtml = if ($Detail)   { "<div class='detail'>$Detail</div>" } else { "" }
    $script:currentRows.Add("<tr class='row-$($Status.ToLower())'><td>$Role</td><td>$badge</td><td>$detailHtml$sub</td></tr>")
}

function Html-CloseSection {
    if ($script:currentRows.Count -eq 0) { return }
    $rows = $script:currentRows -join "`n"
    $script:htmlSections.Add(@"
<section>
  <h2>$($script:currentSection)</h2>
  <table>
    <thead><tr><th>Role / Service</th><th>Status</th><th>Details</th></tr></thead>
    <tbody>$rows</tbody>
  </table>
</section>
"@)
}

function Html-AddSummaryRole { param([string]$Role)
    $script:htmlRoles.Add("<li>$Role</li>")
}

# ─────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────

Clear-Host
Write-Host @"

  ╔═══════════════════════════════════════════════════════╗
  ║           SERVER ROLE & PURPOSE ANALYZER              ║
  ╚═══════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$scanDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "  Target : " -NoNewline; Write-Host $ComputerName.ToUpper() -ForegroundColor Yellow
Write-Host "  Analyst: " -NoNewline; Write-Host $env:USERNAME -ForegroundColor Yellow
Write-Host "  Date   : " -NoNewline; Write-Host $scanDate -ForegroundColor Yellow

# ─────────────────────────────────────────────
# SYSTEM INFO
# ─────────────────────────────────────────────

Write-Header "SYSTEM INFORMATION"

$sysInfo = Invoke-RemoteOrLocal {
    $os     = Get-CimInstance Win32_OperatingSystem
    $cs     = Get-CimInstance Win32_ComputerSystem
    $cpu    = Get-CimInstance Win32_Processor | Select-Object -First 1
    $uptime = (Get-Date) - $os.LastBootUpTime
    [PSCustomObject]@{
        OS       = $os.Caption
        Version  = $os.Version
        Arch     = $os.OSArchitecture
        RAM_GB   = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        CPUs     = $cs.NumberOfLogicalProcessors
        CPU_Name = $cpu.Name.Trim()
        Domain   = $cs.Domain
        Uptime   = "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
        LastBoot = $os.LastBootUpTime
    }
}

if ($sysInfo) {
    Write-Host "  OS       : $($sysInfo.OS) ($($sysInfo.Arch))" -ForegroundColor White
    Write-Host "  Version  : $($sysInfo.Version)" -ForegroundColor White
    Write-Host "  RAM      : $($sysInfo.RAM_GB) GB    CPUs: $($sysInfo.CPUs) ($($sysInfo.CPU_Name))" -ForegroundColor White
    Write-Host "  Domain   : $($sysInfo.Domain)" -ForegroundColor White
    Write-Host "  Uptime   : $($sysInfo.Uptime)  (Last boot: $($sysInfo.LastBoot))" -ForegroundColor White
}

# ─────────────────────────────────────────────
# COLLECT DATA
# ─────────────────────────────────────────────

Write-Host "`n  Collecting role data..." -ForegroundColor DarkGray

$data = Invoke-RemoteOrLocal {
    $allServices = Get-Service -ErrorAction SilentlyContinue

    $smbSharesAll = Get-SmbShare -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike 'IPC$' } |
        Select-Object Name, Path, Description

    $printers = Get-Printer -ErrorAction SilentlyContinue |
        Where-Object { $_.Shared -eq $true } |
        Select-Object Name, ShareName, DriverName, PortName

    $printSpooler = $allServices | Where-Object { $_.Name -eq 'Spooler' }

    $sqlServices  = $allServices | Where-Object { $_.Name -like 'MSSQL*' -or $_.Name -like 'SQLAgent*' -or $_.Name -like 'SQLBrowser*' -or $_.Name -eq 'SQLSERVERAGENT' }
    $sqlInstances = @()
    try { $sqlInstances = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server' -ErrorAction Stop).InstalledInstances } catch {}

    $iisService = $allServices | Where-Object { $_.Name -eq 'W3SVC' }
    $iisFeature = Get-WindowsFeature -Name 'Web-Server' -ErrorAction SilentlyContinue
    $websites   = @()
    try {
        Import-Module WebAdministration -ErrorAction Stop
        $websites = Get-Website -ErrorAction SilentlyContinue | Select-Object Name, State, PhysicalPath,
            @{N='Bindings';E={($_.Bindings.Collection | ForEach-Object { $_.bindingInformation }) -join ', '}}
    } catch {}

    $rdpService  = $allServices | Where-Object { $_.Name -eq 'TermService' }
    $rdpEnabled  = (Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue).fDenyTSConnections
    $rdpSessions = @()
    try { $rdpSessions = (query session 2>&1) | Where-Object { $_ -match 'Active|Disc' } } catch {}
    $rdshRole    = Get-WindowsFeature -Name 'RDS-RD-Server' -ErrorAction SilentlyContinue

    $dnsService = $allServices | Where-Object { $_.Name -eq 'DNS' }
    $dnsZones   = @()
    try { $dnsZones = Get-DnsServerZone -ErrorAction SilentlyContinue | Select-Object ZoneName, ZoneType, IsDsIntegrated } catch {}

    $dhcpService = $allServices | Where-Object { $_.Name -eq 'DHCPServer' }
    $dhcpScopes  = @()
    try { $dhcpScopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Select-Object Name, StartRange, EndRange, State } catch {}

    $adService   = $allServices | Where-Object { $_.Name -eq 'NTDS' }
    $addsFeature = Get-WindowsFeature -Name 'AD-Domain-Services' -ErrorAction SilentlyContinue
    $adInfo      = $null
    try { $adInfo = Get-ADDomain -ErrorAction SilentlyContinue | Select-Object DNSRoot, DomainMode, PDCEmulator } catch {}

    $ftpService = $allServices | Where-Object { $_.Name -eq 'FTPSVC' -or $_.Name -eq 'msftpsvc' }
    $ftpFeature = Get-WindowsFeature -Name 'Web-Ftp-Server' -ErrorAction SilentlyContinue

    $winrmService = $allServices | Where-Object { $_.Name -eq 'WinRM' }

    $hvService = $allServices | Where-Object { $_.Name -eq 'vmms' }
    $hvFeature = Get-WindowsFeature -Name 'Hyper-V' -ErrorAction SilentlyContinue
    $vms       = @()
    try { $vms = Get-VM -ErrorAction SilentlyContinue | Select-Object Name, State, CPUUsage, MemoryAssigned } catch {}

    $wsusService    = $allServices | Where-Object { $_.Name -eq 'WsusService' }
    $caService      = $allServices | Where-Object { $_.Name -eq 'CertSvc' }
    $smtpService    = $allServices | Where-Object { $_.Name -eq 'SMTPSVC' }
    $nfsService     = $allServices | Where-Object { $_.Name -eq 'NfsService' -or $_.Name -eq 'Server for NFS' }
    $nfsFeature     = Get-WindowsFeature -Name 'FS-NFS-Service' -ErrorAction SilentlyContinue
    $wbService      = $allServices | Where-Object { $_.Name -eq 'wbengine' }
    $wbFeature      = Get-WindowsFeature -Name 'Windows-Server-Backup' -ErrorAction SilentlyContinue
    $clusterService = $allServices | Where-Object { $_.Name -eq 'ClusSvc' }
    $dfsService     = $allServices | Where-Object { $_.Name -eq 'Dfsr' -or $_.Name -eq 'Dfs' }
    $iscsiService   = $allServices | Where-Object { $_.Name -eq 'MSiSCSI' }
    $mpio           = Get-WindowsFeature -Name 'Multipath-IO' -ErrorAction SilentlyContinue

    $ports = @()
    try {
        $ports = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty LocalPort | Sort-Object -Unique
    } catch {}

    # ── Full Windows Feature sweep ──────────────────────────────
    $allFeatures = @()
    try {
        $allFeatures = Get-WindowsFeature -ErrorAction SilentlyContinue |
            Where-Object { $_.Installed -eq $true } |
            Select-Object Name, DisplayName, FeatureType, Path, Depth
    } catch {}

    [PSCustomObject]@{
        SMBShares     = $smbSharesAll;   Printers      = $printers;     PrintSpooler  = $printSpooler
        SQLServices   = $sqlServices;    SQLInstances  = $sqlInstances
        IISService    = $iisService;     IISFeature    = $iisFeature;   Websites      = $websites
        RDPService    = $rdpService;     RDPEnabled    = $rdpEnabled;   RDPSessions   = $rdpSessions;  RDSHRole = $rdshRole
        DNSService    = $dnsService;     DNSZones      = $dnsZones
        DHCPService   = $dhcpService;    DHCPScopes    = $dhcpScopes
        ADService     = $adService;      ADDSFeature   = $addsFeature;  ADInfo        = $adInfo
        FTPService    = $ftpService;     FTPFeature    = $ftpFeature
        WinRM         = $winrmService
        HVService     = $hvService;      HVFeature     = $hvFeature;    VMs           = $vms
        WSUS          = $wsusService;    CertSvc       = $caService;    SMTP          = $smtpService
        NFSService    = $nfsService;     NFSFeature    = $nfsFeature
        BackupService = $wbService;      BackupFeature = $wbFeature
        ClusterSvc    = $clusterService; DFSService    = $dfsService
        iSCSI         = $iscsiService;   MPIO          = $mpio
        ListeningPorts = $ports
        AllFeatures   = $allFeatures
    }
}

if (-not $data) {
    Write-Host "`n  [ERROR] Unable to connect to $ComputerName. Check connectivity and credentials." -ForegroundColor Red
    exit 1
}

# ─────────────────────────────────────────────
# SECTION: FILE & STORAGE
# ─────────────────────────────────────────────

Write-Header "FILE & STORAGE SERVICES"
Html-OpenSection "File & Storage Services"

$nonAdminShares = $data.SMBShares | Where-Object { $_.Name -notin @('ADMIN$','C$','D$','E$','IPC$') -and $_.Name -notmatch '^\w\$$' }
if ($nonAdminShares) {
    $subs = $nonAdminShares | ForEach-Object { "\\$ComputerName\$($_.Name) &rarr; $($_.Path)" }
    Write-Role "SMB File Sharing" "ACTIVE" "$($nonAdminShares.Count) user share(s)"
    $nonAdminShares | ForEach-Object { Write-Host "         \\$ComputerName\$($_.Name)  ->  $($_.Path)" -ForegroundColor DarkGray }
    Html-AddRow "SMB File Sharing" "ACTIVE" "$($nonAdminShares.Count) user share(s)" $subs
} else {
    Write-Role "SMB File Sharing" "NONE" "No user-defined shares found"
    Html-AddRow "SMB File Sharing" "NONE" "No user-defined shares found"
}

if ($data.Printers) {
    $subs = $data.Printers | ForEach-Object { "\\$ComputerName\$($_.ShareName) [$($_.DriverName)]" }
    Write-Role "Printer Sharing (Print Server)" "ACTIVE" "$($data.Printers.Count) shared printer(s)"
    $data.Printers | ForEach-Object { Write-Host "         \\$ComputerName\$($_.ShareName)  [$($_.DriverName)]" -ForegroundColor DarkGray }
    Html-AddRow "Printer Sharing (Print Server)" "ACTIVE" "$($data.Printers.Count) shared printer(s)" $subs
} elseif ($data.PrintSpooler -and $data.PrintSpooler.Status -eq 'Running') {
    Write-Role "Print Spooler" "ACTIVE" "Spooler running but no shared printers"
    Html-AddRow "Print Spooler" "ACTIVE" "Spooler running but no shared printers"
} else {
    Write-Role "Print Spooler / Printer Sharing" "NONE"
    Html-AddRow "Print Spooler / Printer Sharing" "NONE"
}

if ($data.NFSService -and $data.NFSService.Status -eq 'Running') {
    Write-Role "NFS Server" "ACTIVE"; Html-AddRow "NFS Server" "ACTIVE"
} elseif ($data.NFSFeature -and $data.NFSFeature.Installed) {
    Write-Role "NFS Server" "INSTALLED" "Service not running"; Html-AddRow "NFS Server" "INSTALLED" "Service not running"
} else {
    Write-Role "NFS Server" "NONE"; Html-AddRow "NFS Server" "NONE"
}

$dfsSvc = $data.DFSService | Where-Object { $_.Status -eq 'Running' }
if ($dfsSvc) {
    Write-Role "DFS (Distributed File System)" "ACTIVE"; Html-AddRow "DFS" "ACTIVE"
} elseif ($data.DFSService) {
    Write-Role "DFS (Distributed File System)" "INSTALLED" "Service stopped"; Html-AddRow "DFS" "INSTALLED" "Service stopped"
} else {
    Write-Role "DFS (Distributed File System)" "NONE"; Html-AddRow "DFS" "NONE"
}

if ($data.iSCSI -and $data.iSCSI.Status -eq 'Running') {
    Write-Role "iSCSI Initiator (SAN)" "ACTIVE"; Html-AddRow "iSCSI Initiator (SAN)" "ACTIVE"
} else {
    Write-Role "iSCSI Initiator (SAN)" "NONE"; Html-AddRow "iSCSI Initiator (SAN)" "NONE"
}

if ($data.MPIO -and $data.MPIO.Installed) {
    Write-Role "Multipath I/O (MPIO)" "INSTALLED"; Html-AddRow "Multipath I/O (MPIO)" "INSTALLED"
} else {
    Write-Role "Multipath I/O (MPIO)" "NONE"; Html-AddRow "Multipath I/O (MPIO)" "NONE"
}

Html-CloseSection

# ─────────────────────────────────────────────
# SECTION: DATABASE
# ─────────────────────────────────────────────

Write-Header "DATABASE SERVICES"
Html-OpenSection "Database Services"

$activeSql   = $data.SQLServices | Where-Object { $_.Name -like 'MSSQL$*' -or $_.Name -eq 'MSSQLSERVER' }
$runningSql  = $activeSql | Where-Object { $_.Status -eq 'Running' }
if ($runningSql) {
    $subs = $runningSql | ForEach-Object {
        $inst = if ($_.Name -eq 'MSSQLSERVER') { 'Default (MSSQLSERVER)' } else { $_.Name -replace '^MSSQL\$','' }
        "$inst [$($_.Status)]"
    }
    Write-Role "SQL Server" "ACTIVE" "$($runningSql.Count) instance(s) running"
    $runningSql | ForEach-Object {
        $inst = if ($_.Name -eq 'MSSQLSERVER') { 'Default Instance' } else { $_.Name -replace '^MSSQL\$','Instance: ' }
        Write-Host "         $inst  [$($_.Status)]" -ForegroundColor DarkGray
    }
    Html-AddRow "SQL Server" "ACTIVE" "$($runningSql.Count) instance(s)" $subs
} elseif ($activeSql) {
    Write-Role "SQL Server" "INSTALLED" "Instances present but not running"; Html-AddRow "SQL Server" "INSTALLED" "Not running"
} elseif ($data.SQLInstances) {
    Write-Role "SQL Server" "INSTALLED" "Instances: $($data.SQLInstances -join ', ')"; Html-AddRow "SQL Server" "INSTALLED" "$($data.SQLInstances -join ', ')"
} else {
    Write-Role "SQL Server" "NONE"; Html-AddRow "SQL Server" "NONE"
}

$sqlAgent = $data.SQLServices | Where-Object { ($_.Name -like 'SQLAgent*' -or $_.Name -eq 'SQLSERVERAGENT') -and $_.Status -eq 'Running' }
if ($sqlAgent) { Write-Role "SQL Server Agent" "ACTIVE"; Html-AddRow "SQL Server Agent" "ACTIVE" }

$sqlBrowser = $data.SQLServices | Where-Object { $_.Name -eq 'SQLBrowser' -and $_.Status -eq 'Running' }
if ($sqlBrowser) { Write-Role "SQL Server Browser" "ACTIVE"; Html-AddRow "SQL Server Browser" "ACTIVE" }

$dbPorts = @{3306='MySQL'; 5432='PostgreSQL'; 27017='MongoDB'; 1521='Oracle DB'}
foreach ($port in $dbPorts.Keys) {
    if ($port -in $data.ListeningPorts) {
        Write-Role "$($dbPorts[$port]) (port $port)" "ACTIVE" "Detected via open port"
        Html-AddRow "$($dbPorts[$port])" "ACTIVE" "Detected via open port $port"
    }
}

Html-CloseSection

# ─────────────────────────────────────────────
# SECTION: REMOTE ACCESS
# ─────────────────────────────────────────────

Write-Header "REMOTE ACCESS & TERMINAL SERVICES"
Html-OpenSection "Remote Access & Terminal Services"

if ($data.RDPService -and $data.RDPService.Status -eq 'Running') {
    $rdpState    = if ($data.RDPEnabled -eq 0) { "ACTIVE" } else { "INSTALLED" }
    $rdpNote     = if ($data.RDPEnabled -eq 0) { "RDP enabled" } else { "Service running but connections denied" }
    $sessionList = if ($data.RDPSessions) { $data.RDPSessions | ForEach-Object { "$_" } } else { @() }
    Write-Role "Remote Desktop (RDP)" $rdpState $rdpNote
    if ($data.RDPSessions) { $data.RDPSessions | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray } }
    Html-AddRow "Remote Desktop (RDP)" $rdpState $rdpNote $sessionList
} else {
    Write-Role "Remote Desktop (RDP)" "NONE"; Html-AddRow "Remote Desktop (RDP)" "NONE"
}

if ($data.RDSHRole -and $data.RDSHRole.Installed) {
    Write-Role "Remote Desktop Session Host (Terminal Server)" "ACTIVE" "Full multi-user terminal server"
    Html-AddRow "Remote Desktop Session Host (Terminal Server)" "ACTIVE" "Full multi-user terminal server"
} else {
    Write-Role "Remote Desktop Session Host (Terminal Server)" "NONE"
    Html-AddRow "Remote Desktop Session Host (Terminal Server)" "NONE"
}

if ($data.WinRM -and $data.WinRM.Status -eq 'Running') {
    Write-Role "WinRM / PowerShell Remoting" "ACTIVE"; Html-AddRow "WinRM / PowerShell Remoting" "ACTIVE"
} else {
    Write-Role "WinRM / PowerShell Remoting" "NONE"; Html-AddRow "WinRM / PowerShell Remoting" "NONE"
}

if (22 -in $data.ListeningPorts) {
    Write-Role "SSH Server (port 22)" "ACTIVE" "Detected via open port"; Html-AddRow "SSH Server" "ACTIVE" "Port 22 open"
} else {
    Write-Role "SSH Server" "NONE"; Html-AddRow "SSH Server" "NONE"
}

Html-CloseSection

# ─────────────────────────────────────────────
# SECTION: WEB & APPLICATION
# ─────────────────────────────────────────────

Write-Header "WEB & APPLICATION SERVICES"
Html-OpenSection "Web & Application Services"

if ($data.IISService -and $data.IISService.Status -eq 'Running') {
    $subs = $data.Websites | ForEach-Object { "[$($_.State)] $($_.Name) — $($_.Bindings)" }
    Write-Role "IIS Web Server" "ACTIVE" "$($data.Websites.Count) site(s)"
    $data.Websites | ForEach-Object { Write-Host "         [$($_.State)] $($_.Name)  Bindings: $($_.Bindings)" -ForegroundColor DarkGray }
    Html-AddRow "IIS Web Server" "ACTIVE" "$($data.Websites.Count) site(s)" $subs
} elseif ($data.IISFeature -and $data.IISFeature.Installed) {
    Write-Role "IIS Web Server" "INSTALLED" "Service not running"; Html-AddRow "IIS Web Server" "INSTALLED" "Service not running"
} else {
    Write-Role "IIS Web Server" "NONE"; Html-AddRow "IIS Web Server" "NONE"
}

if ($data.FTPService -and ($data.FTPService | Where-Object Status -eq 'Running')) {
    Write-Role "FTP Server" "ACTIVE"; Html-AddRow "FTP Server" "ACTIVE"
} elseif ($data.FTPFeature -and $data.FTPFeature.Installed) {
    Write-Role "FTP Server" "INSTALLED" "Service not running"; Html-AddRow "FTP Server" "INSTALLED" "Service not running"
} else {
    Write-Role "FTP Server" "NONE"; Html-AddRow "FTP Server" "NONE"
}

if ($data.SMTP -and $data.SMTP.Status -eq 'Running') {
    Write-Role "SMTP Mail Server" "ACTIVE"; Html-AddRow "SMTP Mail Server" "ACTIVE"
} elseif (25 -in $data.ListeningPorts) {
    Write-Role "SMTP (port 25)" "ACTIVE" "Detected via open port"; Html-AddRow "SMTP" "ACTIVE" "Port 25 open"
} else {
    Write-Role "SMTP Mail Server" "NONE"; Html-AddRow "SMTP Mail Server" "NONE"
}

foreach ($port in @(8080, 8443)) {
    if ($port -in $data.ListeningPorts) {
        Write-Role "HTTP Alt (port $port)" "ACTIVE" "Detected via open port"
        Html-AddRow "HTTP Alt (port $port)" "ACTIVE" "Detected via open port"
    }
}

Html-CloseSection

# ─────────────────────────────────────────────
# SECTION: INFRASTRUCTURE
# ─────────────────────────────────────────────

Write-Header "INFRASTRUCTURE & DIRECTORY SERVICES"
Html-OpenSection "Infrastructure & Directory Services"

if ($data.ADService -and $data.ADService.Status -eq 'Running') {
    $adDetail = if ($data.ADInfo) { "Domain: $($data.ADInfo.DNSRoot) | PDC: $($data.ADInfo.PDCEmulator)" } else { "" }
    Write-Role "Active Directory Domain Services (DC)" "ACTIVE" $adDetail
    Html-AddRow "Active Directory Domain Services (DC)" "ACTIVE" $adDetail
} elseif ($data.ADDSFeature -and $data.ADDSFeature.Installed) {
    Write-Role "Active Directory Domain Services" "INSTALLED" "NTDS not running"
    Html-AddRow "Active Directory Domain Services" "INSTALLED" "NTDS not running"
} else {
    Write-Role "Active Directory Domain Services" "NONE"; Html-AddRow "Active Directory Domain Services" "NONE"
}

if ($data.DNSService -and $data.DNSService.Status -eq 'Running') {
    $filteredZones = $data.DNSZones | Where-Object { -not $_.ZoneName.StartsWith('..') } | Select-Object -First 8
    $subs = $filteredZones | ForEach-Object { "$($_.ZoneName) [$($_.ZoneType)]" }
    Write-Role "DNS Server" "ACTIVE" "$($data.DNSZones.Count) zone(s)"
    $filteredZones | ForEach-Object { Write-Host "         $($_.ZoneName)  [$($_.ZoneType)]" -ForegroundColor DarkGray }
    Html-AddRow "DNS Server" "ACTIVE" "$($data.DNSZones.Count) zone(s)" $subs
} else {
    Write-Role "DNS Server" "NONE"; Html-AddRow "DNS Server" "NONE"
}

if ($data.DHCPService -and $data.DHCPService.Status -eq 'Running') {
    $subs = $data.DHCPScopes | ForEach-Object { "$($_.Name): $($_.StartRange) &ndash; $($_.EndRange) [$($_.State)]" }
    Write-Role "DHCP Server" "ACTIVE" "$($data.DHCPScopes.Count) scope(s)"
    $data.DHCPScopes | ForEach-Object { Write-Host "         $($_.Name) : $($_.StartRange) - $($_.EndRange)  [$($_.State)]" -ForegroundColor DarkGray }
    Html-AddRow "DHCP Server" "ACTIVE" "$($data.DHCPScopes.Count) scope(s)" $subs
} else {
    Write-Role "DHCP Server" "NONE"; Html-AddRow "DHCP Server" "NONE"
}

if ($data.CertSvc -and $data.CertSvc.Status -eq 'Running') {
    Write-Role "Certificate Authority (AD CS)" "ACTIVE"; Html-AddRow "Certificate Authority (AD CS)" "ACTIVE"
} else {
    Write-Role "Certificate Authority (AD CS)" "NONE"; Html-AddRow "Certificate Authority (AD CS)" "NONE"
}

if ($data.WSUS -and $data.WSUS.Status -eq 'Running') {
    Write-Role "WSUS (Windows Update Server)" "ACTIVE"; Html-AddRow "WSUS (Windows Update Server)" "ACTIVE"
} else {
    Write-Role "WSUS (Windows Update Server)" "NONE"; Html-AddRow "WSUS (Windows Update Server)" "NONE"
}

Html-CloseSection

# ─────────────────────────────────────────────
# SECTION: VIRTUALIZATION
# ─────────────────────────────────────────────

Write-Header "VIRTUALIZATION & HIGH AVAILABILITY"
Html-OpenSection "Virtualization & High Availability"

if ($data.HVService -and $data.HVService.Status -eq 'Running') {
    $subs = $data.VMs | ForEach-Object {
        $mem = if ($_.MemoryAssigned) { "$([math]::Round($_.MemoryAssigned/1GB,1)) GB" } else { "?" }
        "$($_.Name) [$($_.State)] RAM: $mem"
    }
    Write-Role "Hyper-V (Virtualization Host)" "ACTIVE" "$($data.VMs.Count) VM(s)"
    $data.VMs | ForEach-Object {
        $mem = if ($_.MemoryAssigned) { "$([math]::Round($_.MemoryAssigned/1GB,1)) GB" } else { "?" }
        Write-Host "         $($_.Name)  [$($_.State)]  RAM: $mem" -ForegroundColor DarkGray
    }
    Html-AddRow "Hyper-V (Virtualization Host)" "ACTIVE" "$($data.VMs.Count) VM(s)" $subs
} elseif ($data.HVFeature -and $data.HVFeature.Installed) {
    Write-Role "Hyper-V" "INSTALLED" "Service not running"; Html-AddRow "Hyper-V" "INSTALLED" "Service not running"
} else {
    Write-Role "Hyper-V" "NONE"; Html-AddRow "Hyper-V" "NONE"
}

if ($data.ClusterSvc -and $data.ClusterSvc.Status -eq 'Running') {
    Write-Role "Failover Clustering" "ACTIVE"; Html-AddRow "Failover Clustering" "ACTIVE"
} else {
    Write-Role "Failover Clustering" "NONE"; Html-AddRow "Failover Clustering" "NONE"
}

Html-CloseSection

# ─────────────────────────────────────────────
# SECTION: BACKUP
# ─────────────────────────────────────────────

Write-Header "BACKUP & MANAGEMENT"
Html-OpenSection "Backup & Management"

if ($data.BackupService -and $data.BackupService.Status -eq 'Running') {
    Write-Role "Windows Server Backup" "ACTIVE"; Html-AddRow "Windows Server Backup" "ACTIVE"
} elseif ($data.BackupFeature -and $data.BackupFeature.Installed) {
    Write-Role "Windows Server Backup" "INSTALLED" "Service not running"; Html-AddRow "Windows Server Backup" "INSTALLED" "Service not running"
} else {
    Write-Role "Windows Server Backup" "NONE"; Html-AddRow "Windows Server Backup" "NONE"
}

Html-CloseSection

# ─────────────────────────────────────────────
# SECTION: WINDOWS ROLES & FEATURES (full sweep)
# ─────────────────────────────────────────────

Write-Header "INSTALLED WINDOWS ROLES & FEATURES"
Html-OpenSection "Installed Windows Roles &amp; Features (Get-WindowsFeature)"

if ($data.AllFeatures -and $data.AllFeatures.Count -gt 0) {

    # Split into Roles (depth 1), Role Services, and Features
    $topRoles   = $data.AllFeatures | Where-Object { $_.FeatureType -eq 'Role'         -and $_.Depth -eq 1 } | Sort-Object DisplayName
    $roleSvcs   = $data.AllFeatures | Where-Object { $_.FeatureType -eq 'Role Service'                     } | Sort-Object DisplayName
    $topFeats   = $data.AllFeatures | Where-Object { $_.FeatureType -eq 'Feature'       -and $_.Depth -eq 1 } | Sort-Object DisplayName
    $subFeats   = $data.AllFeatures | Where-Object { $_.FeatureType -eq 'Feature'       -and $_.Depth -gt 1 } | Sort-Object DisplayName

    Write-Host "  Installed Roles    : $($topRoles.Count)" -ForegroundColor White
    Write-Host "  Role Services      : $($roleSvcs.Count)" -ForegroundColor White
    Write-Host "  Installed Features : $($topFeats.Count + $subFeats.Count)" -ForegroundColor White

    # ── Roles ──────────────────────────────────────────────
    foreach ($f in $topRoles) {
        Write-Host "    [ROLE] $($f.DisplayName)" -ForegroundColor Green
        # Child role services whose path starts with this role's name
        $children = $roleSvcs | Where-Object { $_.Path -like "$($f.Name)*" }
        $subs = $children | ForEach-Object { "&#8627; $($_.DisplayName) <em style='color:var(--muted);font-size:11px'>(Role Service)</em>" }
        Html-AddRow $f.DisplayName "ACTIVE" '<span class="feat-badge feat-role">Role</span>' $subs
    }

    # ── Top-level Features ─────────────────────────────────
    foreach ($f in $topFeats) {
        Write-Host "    [FEAT] $($f.DisplayName)" -ForegroundColor Cyan
        $children = $subFeats | Where-Object { $_.Path -like "$($f.Name)*" }
        $subs = $children | ForEach-Object { "&#8627; $($_.DisplayName)" }
        Html-AddRow $f.DisplayName "INSTALLED" '<span class="feat-badge feat-feature">Feature</span>' $subs
    }

    # ── Orphaned Role Services (parent role not top-level installed) ──
    $orphans = $roleSvcs | Where-Object {
        $parentName = ($_.Path -split '\\')[0]
        -not ($topRoles | Where-Object { $_.Name -eq $parentName })
    }
    foreach ($f in ($orphans | Sort-Object DisplayName)) {
        Write-Host "    [SVC ] $($f.DisplayName)" -ForegroundColor Yellow
        Html-AddRow $f.DisplayName "INSTALLED" '<span class="feat-badge feat-rolesvc">Role Service</span>'
    }

} else {
    Write-Host "  No feature data returned — requires Server OS and admin rights." -ForegroundColor Yellow
    Html-AddRow "Get-WindowsFeature" "NONE" "No data returned. Requires Windows Server OS and administrator rights."
}

Html-CloseSection

# ─────────────────────────────────────────────
# LISTENING PORTS
# ─────────────────────────────────────────────

Write-Header "LISTENING PORTS (Notable)"

$knownPorts = @{
    21='FTP'; 22='SSH'; 25='SMTP'; 53='DNS'; 67='DHCP'; 80='HTTP'; 88='Kerberos'
    110='POP3'; 135='RPC'; 139='NetBIOS'; 143='IMAP'; 389='LDAP'; 443='HTTPS'
    445='SMB'; 464='Kerberos PW'; 514='Syslog'; 636='LDAPS'; 993='IMAPS'
    1433='SQL Server'; 1521='Oracle'; 3306='MySQL'; 3389='RDP'; 5432='PostgreSQL'
    5985='WinRM HTTP'; 5986='WinRM HTTPS'; 8080='HTTP Alt'; 8443='HTTPS Alt'
    9090='Cockpit/Other'; 27017='MongoDB'
}

$notablePorts = $data.ListeningPorts | Where-Object { $_ -in $knownPorts.Keys } | Sort-Object
if ($notablePorts) {
    foreach ($p in $notablePorts) { Write-Host ("  {0,-8} {1}" -f $p, $knownPorts[$p]) -ForegroundColor White }
} else {
    Write-Host "  No notable ports detected." -ForegroundColor DarkGray
}
Write-Host "`n  All listening TCP ports:" -ForegroundColor DarkGray
Write-Host "  $($data.ListeningPorts -join ', ')" -ForegroundColor DarkGray

$portRowsHtml = ($notablePorts | ForEach-Object { "<tr><td><strong>$_</strong></td><td>$($knownPorts[$_])</td></tr>" }) -join "`n"
$allPortsHtml = $data.ListeningPorts -join ', '

# ─────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────

Write-Header "SUMMARY — SERVER IS ACTING AS:"

$roles = @()
$nonAdmin = $data.SMBShares | Where-Object { $_.Name -notin @('ADMIN$','C$','D$','E$','IPC$') -and $_.Name -notmatch '^\w\$$' }
if ($nonAdmin)                                                                                              { $roles += "File Server (SMB)" }
if ($data.Printers)                                                                                         { $roles += "Print Server" }
if ($data.NFSService -and $data.NFSService.Status -eq 'Running')                                           { $roles += "NFS Server" }
if ($data.SQLServices | Where-Object { $_.Status -eq 'Running' -and $_.Name -like 'MSSQL*' })             { $roles += "SQL Database Server" }
if ($data.IISService -and $data.IISService.Status -eq 'Running')                                           { $roles += "Web Server (IIS)" }
if ($data.FTPService -and ($data.FTPService | Where-Object Status -eq 'Running'))                          { $roles += "FTP Server" }
if ($data.SMTP -and $data.SMTP.Status -eq 'Running')                                                       { $roles += "SMTP Server" }
if ($data.RDSHRole -and $data.RDSHRole.Installed)                                                          { $roles += "Terminal Server (RDSH)" }
elseif ($data.RDPService -and $data.RDPService.Status -eq 'Running' -and $data.RDPEnabled -eq 0)          { $roles += "Remote Desktop Host" }
if ($data.ADService -and $data.ADService.Status -eq 'Running')                                             { $roles += "Active Directory Domain Controller" }
if ($data.DNSService -and $data.DNSService.Status -eq 'Running')                                           { $roles += "DNS Server" }
if ($data.DHCPService -and $data.DHCPService.Status -eq 'Running')                                         { $roles += "DHCP Server" }
if ($data.CertSvc -and $data.CertSvc.Status -eq 'Running')                                                { $roles += "Certificate Authority" }
if ($data.WSUS -and $data.WSUS.Status -eq 'Running')                                                       { $roles += "WSUS Update Server" }
if ($data.HVService -and $data.HVService.Status -eq 'Running')                                             { $roles += "Hyper-V Host" }
if ($data.ClusterSvc -and $data.ClusterSvc.Status -eq 'Running')                                           { $roles += "Failover Cluster Node" }
if ($data.DFSService -and ($data.DFSService | Where-Object Status -eq 'Running'))                          { $roles += "DFS Server" }
if ($data.WinRM -and $data.WinRM.Status -eq 'Running')                                                     { $roles += "Remote Management (WinRM)" }
if ($data.iSCSI -and $data.iSCSI.Status -eq 'Running')                                                     { $roles += "iSCSI Initiator (SAN)" }
if (22 -in $data.ListeningPorts)                                                                            { $roles += "SSH Server" }
# Add any top-level roles from the feature sweep not already captured above
if ($data.AllFeatures) {
    $data.AllFeatures | Where-Object { $_.FeatureType -eq 'Role' -and $_.Depth -eq 1 } | ForEach-Object {
        if ($_.DisplayName -notin $roles) { $roles += $_.DisplayName }
    }
}

$line = "=" * 60
Write-Host "`n$line" -ForegroundColor Green
if ($roles.Count -eq 0) {
    Write-Host "  No active roles detected (workstation or minimal server?)" -ForegroundColor Yellow
} else {
    foreach ($r in $roles) { Write-Host "   >> $r" -ForegroundColor Green }
}
Write-Host $line -ForegroundColor Green
Write-Host "`n  Scan complete: $(Get-Date -Format 'HH:mm:ss')`n" -ForegroundColor Cyan

$roles | ForEach-Object { Html-AddSummaryRole $_ }

# ─────────────────────────────────────────────
# BUILD HTML REPORT
# ─────────────────────────────────────────────

$summaryItems = if ($script:htmlRoles.Count -gt 0) {
    ($script:htmlRoles | ForEach-Object { $_ }) -join "`n"
} else { "<li>No active roles detected</li>" }

$sysInfoHtml = if ($sysInfo) { @"
<div class="sysinfo-grid">
  <div class="si-item"><span class="si-label">OS</span><span class="si-val">$($sysInfo.OS) ($($sysInfo.Arch))</span></div>
  <div class="si-item"><span class="si-label">Version</span><span class="si-val">$($sysInfo.Version)</span></div>
  <div class="si-item"><span class="si-label">RAM</span><span class="si-val">$($sysInfo.RAM_GB) GB</span></div>
  <div class="si-item"><span class="si-label">CPUs</span><span class="si-val">$($sysInfo.CPUs) &times; $($sysInfo.CPU_Name)</span></div>
  <div class="si-item"><span class="si-label">Domain</span><span class="si-val">$($sysInfo.Domain)</span></div>
  <div class="si-item"><span class="si-label">Uptime</span><span class="si-val">$($sysInfo.Uptime)</span></div>
  <div class="si-item"><span class="si-label">Last Boot</span><span class="si-val">$($sysInfo.LastBoot)</span></div>
  <div class="si-item"><span class="si-label">Analyst</span><span class="si-val">$env:USERNAME</span></div>
</div>
"@ } else { "<p>System info unavailable.</p>" }

$sectionsHtml = $script:htmlSections -join "`n"

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Server Role Report &mdash; $($ComputerName.ToUpper())</title>
<style>
  :root {
    --bg: #f1f5f9; --surface: #ffffff; --surface2: #f8fafc;
    --border: #e2e8f0; --text: #1e293b; --muted: #64748b;
    --active: #16a34a; --active-bg: #f0fdf4; --active-border: #bbf7d0;
    --installed: #d97706; --installed-bg: #fffbeb; --installed-border: #fde68a;
    --none: #94a3b8; --none-bg: #f8fafc; --none-border: #e2e8f0;
    --accent: #4f46e5; --accent2: #4338ca;
    --header-grad: linear-gradient(135deg, #4f46e5 0%, #3b82f6 100%);
    --header-border: #c7d2fe; --header-sub: #c7d2fe;
    --chip-bg: rgba(255,255,255,0.15); --chip-border: rgba(255,255,255,0.3); --chip-text: #e0e7ff;
    --hover-row: #f8fafc; --shadow: 0 1px 3px rgba(0,0,0,.06);
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: var(--bg); color: var(--text); font-family: 'Segoe UI', system-ui, sans-serif; font-size: 14px; line-height: 1.6; }
  a { color: var(--accent); }
  .report-header { background: var(--header-grad); border-bottom: 1px solid var(--header-border); padding: 32px 40px; }
  .report-header h1 { font-size: 26px; font-weight: 700; color: #fff; letter-spacing: .5px; }
  .report-header .subtitle { color: var(--header-sub); margin-top: 4px; font-size: 13px; }
  .report-header .meta { margin-top: 16px; display: flex; gap: 24px; flex-wrap: wrap; }
  .meta-chip { background: var(--chip-bg); border: 1px solid var(--chip-border); border-radius: 6px; padding: 4px 12px; font-size: 12px; color: var(--chip-text); }
  .meta-chip strong { color: #fff; }
  .container { max-width: 1100px; margin: 0 auto; padding: 32px 24px; }
  .summary-card { background: var(--surface); border: 1px solid var(--active-border); border-radius: 10px; padding: 24px 28px; margin-bottom: 36px; box-shadow: var(--shadow); }
  .summary-card h2 { font-size: 15px; text-transform: uppercase; letter-spacing: 1px; color: var(--active); margin-bottom: 16px; }
  .summary-card ul { list-style: none; display: flex; flex-wrap: wrap; gap: 10px; }
  .summary-card ul li { background: var(--active-bg); border: 1px solid var(--active-border); color: var(--active); border-radius: 6px; padding: 5px 14px; font-size: 13px; font-weight: 600; }
  .sysinfo-card { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 24px 28px; margin-bottom: 36px; box-shadow: var(--shadow); }
  .sysinfo-card h2 { font-size: 15px; text-transform: uppercase; letter-spacing: 1px; color: var(--accent2); margin-bottom: 16px; }
  .sysinfo-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 12px; }
  .si-item { background: var(--surface2); border: 1px solid var(--border); border-radius: 6px; padding: 10px 14px; }
  .si-label { display: block; font-size: 11px; color: var(--muted); text-transform: uppercase; letter-spacing: .5px; margin-bottom: 2px; }
  .si-val { font-weight: 600; font-size: 13px; color: var(--text); }
  section { margin-bottom: 32px; }
  section h2 { font-size: 15px; text-transform: uppercase; letter-spacing: 1px; color: var(--accent2); margin-bottom: 12px; padding-bottom: 8px; border-bottom: 2px solid var(--border); }
  table { width: 100%; border-collapse: collapse; background: var(--surface); border-radius: 10px; overflow: hidden; border: 1px solid var(--border); box-shadow: var(--shadow); }
  thead tr { background: var(--surface2); }
  th { padding: 10px 16px; text-align: left; font-size: 12px; text-transform: uppercase; letter-spacing: .5px; color: var(--muted); border-bottom: 1px solid var(--border); }
  td { padding: 10px 16px; border-bottom: 1px solid var(--border); vertical-align: top; }
  tr:last-child td { border-bottom: none; }
  td:first-child { font-weight: 600; width: 30%; color: var(--text); }
  td:nth-child(2) { width: 110px; }
  tbody tr:hover td { background: var(--hover-row); }
  .row-active    td { background: rgba(22,163,74,.03); }
  .row-installed td { background: rgba(217,119,6,.03); }
  .row-none      td { opacity: .55; }
  .badge { display: inline-block; padding: 2px 10px; border-radius: 20px; font-size: 11px; font-weight: 700; letter-spacing: .5px; }
  .badge.active    { background: var(--active-bg);    color: var(--active);    border: 1px solid var(--active-border); }
  .badge.installed { background: var(--installed-bg); color: var(--installed); border: 1px solid var(--installed-border); }
  .badge.none      { background: var(--none-bg);      color: var(--none);      border: 1px solid var(--none-border); }
  .detail { color: var(--muted); font-size: 12px; margin-top: 2px; }
  ul.subitems { list-style: none; margin-top: 6px; }
  ul.subitems li { font-size: 12px; color: var(--muted); padding: 1px 0; }
  ul.subitems li::before { content: "› "; color: var(--accent); }
  /* Feature type badges */
  .feat-badge { display: inline-block; font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: .4px; border-radius: 4px; padding: 1px 7px; margin-left: 4px; vertical-align: middle; }
  .feat-role    { background: #ede9fe; color: #5b21b6; border: 1px solid #c4b5fd; }
  .feat-feature { background: var(--installed-bg); color: var(--installed); border: 1px solid var(--installed-border); }
  .feat-rolesvc { background: #e0f2fe; color: #0369a1; border: 1px solid #7dd3fc; }
  .ports-card { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 24px 28px; margin-bottom: 32px; box-shadow: var(--shadow); }
  .ports-card h2 { font-size: 15px; text-transform: uppercase; letter-spacing: 1px; color: var(--accent2); margin-bottom: 16px; }
  .port-table { width: 100%; border-collapse: collapse; }
  .port-table td { padding: 6px 12px; border-bottom: 1px solid var(--border); font-size: 13px; }
  .port-table tr:last-child td { border-bottom: none; }
  .all-ports { margin-top: 16px; font-size: 12px; color: var(--muted); word-break: break-all; }
  footer { text-align: center; padding: 24px; color: var(--muted); font-size: 12px; border-top: 1px solid var(--border); margin-top: 16px; }
</style>
</head>
<body>

<div class="report-header">
  <h1>&#128268; Server Role Report</h1>
  <div class="subtitle">Automated role and service detection</div>
  <div class="meta">
    <div class="meta-chip"><strong>Target:</strong> $($ComputerName.ToUpper())</div>
    <div class="meta-chip"><strong>Scan Date:</strong> $scanDate</div>
    <div class="meta-chip"><strong>Analyst:</strong> $env:USERNAME</div>
    <div class="meta-chip"><strong>Active Roles:</strong> $($roles.Count)</div>
  </div>
</div>

<div class="container">
  <div class="summary-card">
    <h2>&#9989; This Server Is Acting As</h2>
    <ul>$summaryItems</ul>
  </div>
  <div class="sysinfo-card">
    <h2>System Information</h2>
    $sysInfoHtml
  </div>
  $sectionsHtml
  <div class="ports-card">
    <h2>Listening Ports (Notable)</h2>
    <table class="port-table">
      <thead><tr><th>Port</th><th>Service</th></tr></thead>
      <tbody>$portRowsHtml</tbody>
    </table>
    <div class="all-ports"><strong>All listening TCP ports:</strong> $allPortsHtml</div>
  </div>
</div>

<footer>Generated by Get-ServerRoles.ps1 &mdash; $scanDate</footer>
</body>
</html>
"@

# ─────────────────────────────────────────────
# SAVE HTML
# ─────────────────────────────────────────────

if (-not $OutputPath) {
    $stamp      = Get-Date -Format "yyyyMMdd_HHmm"
    $OutputPath = "C:\temp\ServerRoles_$($ComputerName.ToUpper())_$stamp.html"
}

$outDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

try {
    $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
    Write-Host "  HTML Report : " -NoNewline -ForegroundColor Cyan
    Write-Host $OutputPath -ForegroundColor Yellow
    Write-Host "  Open in any browser to view the formatted report.`n" -ForegroundColor DarkGray
} catch {
    Write-Host "`n  [WARNING] Could not write HTML report: $_" -ForegroundColor Red
}
