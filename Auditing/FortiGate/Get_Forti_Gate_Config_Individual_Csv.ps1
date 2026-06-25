#Requires -Version 5.1
<#
.SYNOPSIS
    Retrieves network interfaces, VLANs, and VPN configurations from a FortiGate firewall.

.DESCRIPTION
    Connects to the FortiGate REST API and collects:
      - Standard network interfaces (IP, subnet, parent interface)
	  - license/status
      - VLANs (tag, description, parent interface, IP/subnet)
      - IPsec VPN Phase 1 and Phase 2 configurations
      - SSL/OpenVPN server configurations
      - Connected devices (ARP table, DHCP leases, active sessions)
      - Firewall policies
      - Virtual IPs (DNAT) and VIP groups
      - DNS settings, zones, and static entries
    Results are exported as CSV files to C:\Temp automatically.

.PARAMETER FortiGateHost
    The IP address or hostname of the FortiGate firewall.
    Example: "192.168.1.1" or "fw.corp.local"

.PARAMETER Port
    The HTTPS port used to reach the FortiGate management interface.
    Default is 443. Use this if your firewall management runs on a non-standard port (e.g. 8443).
    Example: -Port 8443

.PARAMETER ApiToken
    The REST API token generated on the FortiGate under:
    System > Administrators > Create New > REST API Admin
    Example: -ApiToken "abc123xyz"

.PARAMETER Credential
    A PSCredential object (username + password) as an alternative to an API token.
    Example: -Credential (Get-Credential)

.PARAMETER Vdom
    The VDOM to query. Default is "root".
    Only needed if your FortiGate uses multiple VDOMs.
    Example: -Vdom "CORP"

.PARAMETER SkipCertificateCheck
    Bypasses SSL certificate validation. Use this when the FortiGate
    is using a self-signed certificate (which is the default on most units).

.EXAMPLE
    # Minimum required - token auth on default port 443
    .\Get_Forti_Gate_Config_Individual_Csv.ps1 -FortiGateHost "192.168.1.1" -ApiToken "YourApiTokenHere"

.EXAMPLE
    # Self-signed cert (most common for on-prem FortiGates)
    .\Get_Forti_Gate_Config_Individual_Csv.ps1 -FortiGateHost "192.168.1.1" -ApiToken "YourApiTokenHere" -SkipCertificateCheck

.EXAMPLE
    # Non-standard management port
    .\Get_Forti_Gate_Config_Individual_Csv.ps1 -FortiGateHost "192.168.1.1" -ApiToken "YourApiTokenHere" -Port 8443 -SkipCertificateCheck

.EXAMPLE
    # Full example with all common options
    .\Get_Forti_Gate_Config_Individual_Csv.ps1 -FortiGateHost "FW_IP" -ApiToken "YourApiTokenHere" -Port 8443 -SkipCertificateCheck

.EXAMPLE
    # Username and password instead of API token
    .\Get_Forti_Gate_Config_Individual_Csv.ps1 -FortiGateHost "192.168.1.1" -Credential (Get-Credential) -SkipCertificateCheck

.EXAMPLE
    # Query a specific VDOM
    .\Get_Forti_Gate_Config_Individual_Csv.ps1 -FortiGateHost "192.168.1.1" -ApiToken "YourApiTokenHere" -Vdom "CORP" -SkipCertificateCheck

.NOTES
    Requires FortiOS 6.4+. Firewall policies, VIPs, and DNS require no extra permissions
    beyond standard read access to System, Network, VPN, and Firewall API categories.
    CSV files are saved to C:\Temp and named with the firewall IP and a timestamp.

    -------------------------------------------------------------------------
    HOW TO CREATE A REST API TOKEN ON THE FORTIGATE
    -------------------------------------------------------------------------

    STEP 1 - Create an Administrator Profile (recommended, can skip for testing)
    -------------------------------------------------------------------------
    A least-privilege read-only profile is best practice over using the
    built-in super-admin profile (prof_admin).

      1. Go to System > Admin Profiles
      2. Click Create New
      3. Name it (e.g. api_readonly)
      4. Set the following categories to Read access:
           - Network
           - VPN
           - System
           - Firewall
      5. Click OK

    STEP 2 - Create the REST API Admin
    -------------------------------------------------------------------------
      1. Go to System > Administrators
      2. Click Create New > REST API Admin
      3. Fill in the following fields:
           Username           : e.g. ps_api_user
           Administrator Profile : select the profile from Step 1 (or prof_admin)
           PKI Group          : leave blank (only for certificate auth)
           CORS Allow Origin  : leave blank (only for browser-based apps)
           Trusted Hosts      : *** STRONGLY RECOMMENDED ***
                                Enter the IP of the machine running this script
                                e.g. 192.168.1.50/32
                                This restricts which IPs can use the token.
                                If you get HTTP 403 errors, your source IP is
                                not in this list.
      4. Click OK

    STEP 3 - Copy the Token
    -------------------------------------------------------------------------
      - FortiGate displays the API token ONCE immediately after saving.
        Copy it now - it will never be shown again.
      - Store it securely (password manager, secrets vault, etc.)
      - If you lose it: System > Administrators > Edit the account >
        Regenerate API Token

    COMMON ERRORS
    -------------------------------------------------------------------------
      HTTP 401 - Token is invalid or expired. Regenerate it.
      HTTP 403 - Your machine's IP is not in the Trusted Hosts list.
      No response - Wrong IP/port, or management access not enabled on
                    that interface. Check System > Network > Interfaces and
                    ensure HTTPS is listed under Access.
#>

[CmdletBinding(DefaultParameterSetName = 'Token')]
param (
    [Parameter(Mandatory = $true)]
    [string]$FortiGateHost,

    [Parameter(Mandatory = $false)]
    [int]$Port = 443,

    [Parameter(Mandatory = $true, ParameterSetName = 'Token')]
    [string]$ApiToken,

    [Parameter(Mandatory = $true, ParameterSetName = 'Credential')]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [string]$Vdom = 'root',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCertificateCheck
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# TLS / certificate bypass (PS 5.x)
# ---------------------------------------------------------------------------
function Initialize-TlsBypass {
    if (-not $SkipCertificateCheck) { return }
    if ($PSVersionTable.PSVersion.Major -ge 7) { return }

    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
        Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) { return true; }
}
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    }
    try {
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.SecurityProtocolType]::Tls12 -bor
            [System.Net.SecurityProtocolType]::Tls11 -bor
            [System.Net.SecurityProtocolType]::Tls
    } catch {
        [System.Net.ServicePointManager]::SecurityProtocol = 3072  # Tls12 numeric value
    }
}

# ---------------------------------------------------------------------------
# Core API call
# ---------------------------------------------------------------------------
function Invoke-FgApi {
    param (
        [string]$Path,
        [hashtable]$Query
    )
    if (-not $Query) { $Query = @{} }
    $Query['vdom'] = $Vdom

    $qParts = @()
    foreach ($k in $Query.Keys) {
        $qParts += ($k + '=' + $Query[$k])
    }
    $queryString = $qParts -join '&'
    $uri = 'https://' + $FortiGateHost + ':' + $Port + '/api/v2' + $Path + '?' + $queryString

    $headers = @{}
    if ($PSCmdlet.ParameterSetName -eq 'Token') {
        $headers['Authorization'] = 'Bearer ' + $ApiToken
    }

    $splat = @{
        Uri     = $uri
        Method  = 'GET'
        Headers = $headers
    }
    if ($PSCmdlet.ParameterSetName -eq 'Credential') {
        $splat['WebSession'] = $script:FgSession
    }
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 7) {
        $splat['SkipCertificateCheck'] = $true
    }

    try {
        $response = Invoke-RestMethod @splat
        return $response.results
    } catch {
        $statusCode = 'N/A'
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        Write-Warning ('  [HTTP ' + $statusCode + '] GET ' + $Path + ' - ' + $_.Exception.Message)
        return $null
    }
}

# ---------------------------------------------------------------------------
# Credential-based login
# ---------------------------------------------------------------------------
function Connect-FortiGate {
    $loginUri    = 'https://' + $FortiGateHost + ':' + $Port + '/logincheck'
    $encodedUser = [uri]::EscapeDataString($Credential.UserName)
    $encodedPass = [uri]::EscapeDataString($Credential.GetNetworkCredential().Password)
    $body        = 'username=' + $encodedUser + '&secretkey=' + $encodedPass

    $splat = @{
        Uri             = $loginUri
        Method          = 'POST'
        Body            = $body
        ContentType     = 'application/x-www-form-urlencoded'
        SessionVariable = 'FgSessionVar'
    }
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 7) {
        $splat['SkipCertificateCheck'] = $true
    }

    try {
        Invoke-RestMethod @splat | Out-Null
        $script:FgSession = $FgSessionVar
        Write-Host ('  Authenticated as: ' + $Credential.UserName) -ForegroundColor Cyan
    } catch {
        Write-Warning ('  Login failed: ' + $_.Exception.Message)
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Connection test - verify we can reach the firewall before proceeding
# ---------------------------------------------------------------------------
function Test-FortiGateConnection {
    Write-Host "`nTesting connection to $FortiGateHost`:$Port ..." -ForegroundColor Cyan

    $uri = 'https://' + $FortiGateHost + ':' + $Port + '/api/v2/monitor/system/status?vdom=' + $Vdom
    $headers = @{}
    if ($PSCmdlet.ParameterSetName -eq 'Token') {
        $headers['Authorization'] = 'Bearer ' + $ApiToken
    }

    $splat = @{
        Uri     = $uri
        Method  = 'GET'
        Headers = $headers
    }
    if ($PSCmdlet.ParameterSetName -eq 'Credential') {
        $splat['WebSession'] = $script:FgSession
    }
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 7) {
        $splat['SkipCertificateCheck'] = $true
    }

    try {
        $resp = Invoke-RestMethod @splat
        $ver  = ''
        if ($resp.version)  { $ver = $resp.version }
        if ($resp.results -and $resp.results.version) { $ver = $resp.results.version }
        Write-Host ('  Connected OK. FortiOS version: ' + $ver) -ForegroundColor Green
        return $true
    } catch {
        $statusCode = 'N/A'
        $msg        = $_.Exception.Message
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        Write-Host '' 
        Write-Host '  CONNECTION FAILED' -ForegroundColor Red
        Write-Host ('  HTTP Status : ' + $statusCode) -ForegroundColor Red
        Write-Host ('  Error       : ' + $msg) -ForegroundColor Red
        Write-Host ''
        Write-Host '  Troubleshooting checklist:' -ForegroundColor Yellow
        Write-Host ('  1. Can you reach https://' + $FortiGateHost + ':' + $Port + ' in a browser?') -ForegroundColor Yellow
        Write-Host  '  2. Is the API token correct? (regenerate under System > Administrators)' -ForegroundColor Yellow
        Write-Host  '  3. Does the API admin have your IP in Trusted Hosts?' -ForegroundColor Yellow
        Write-Host ('  4. If using a self-signed cert, re-run with -SkipCertificateCheck') -ForegroundColor Yellow
        Write-Host  '  5. Is the management interface accessible on this port?' -ForegroundColor Yellow
        if ($statusCode -eq 401) {
            Write-Host '  >> HTTP 401: Token is invalid or expired - regenerate it.' -ForegroundColor Red
        }
        if ($statusCode -eq 403) {
            Write-Host '  >> HTTP 403: Your source IP is not in the Trusted Hosts list.' -ForegroundColor Red
        }
        return $false
    }
}

# ---------------------------------------------------------------------------
# Helper: convert dotted subnet mask to CIDR prefix length
# ---------------------------------------------------------------------------
function ConvertTo-CidrMask {
    param([string]$DottedMask)
    if ([string]::IsNullOrEmpty($DottedMask) -or $DottedMask -eq '0.0.0.0') { return $null }
    try {
        $bytes  = ([System.Net.IPAddress]$DottedMask).GetAddressBytes()
        $binary = ''
        foreach ($b in $bytes) {
            $binary += [Convert]::ToString($b, 2).PadLeft(8, '0')
        }
        $count = 0
        foreach ($c in $binary.ToCharArray()) {
            if ($c -eq '1') { $count++ }
        }
        return $count
    } catch {
        return $null
    }
}

# ---------------------------------------------------------------------------
# Helper: format IP + mask as CIDR notation
# ---------------------------------------------------------------------------
function Format-IpCidr {
    param([string]$Ip, [string]$Mask)
    if ([string]::IsNullOrEmpty($Ip) -or $Ip -eq '0.0.0.0') { return $null }
    $cidr = ConvertTo-CidrMask -DottedMask $Mask
    if ($cidr -ne $null) {
        return ($Ip + '/' + $cidr)
    }
    return $Ip
}

# ---------------------------------------------------------------------------
# Helper: safely get array count without crashing on $null
# ---------------------------------------------------------------------------
function Get-SafeCount {
    param($Collection)
    if ($null -eq $Collection) { return 0 }
    return @($Collection).Count
}

# ---------------------------------------------------------------------------
# Collect System Information
# ---------------------------------------------------------------------------
function Get-SystemInfo {
    Write-Host "`n[1/13] Collecting system information..." -ForegroundColor Yellow

    # /monitor/system/status returns data as TOP-LEVEL properties on the response
    # object (not inside .results like CMDB endpoints do). We must call
    # Invoke-RestMethod directly and read from the root of the response.
    $mon = $null
    try {
        $uri     = 'https://' + $FortiGateHost + ':' + $Port + '/api/v2/monitor/system/status?vdom=' + $Vdom
        $headers = @{}
        if ($PSCmdlet.ParameterSetName -eq 'Token') { $headers['Authorization'] = 'Bearer ' + $ApiToken }
        $splat = @{ Uri = $uri; Method = 'GET'; Headers = $headers }
        if ($PSCmdlet.ParameterSetName -eq 'Credential') { $splat['WebSession'] = $script:FgSession }
        if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 7) { $splat['SkipCertificateCheck'] = $true }
        $mon = Invoke-RestMethod @splat
    } catch {
        Write-Warning ('  /monitor/system/status failed: ' + $_.Exception.Message)
    }

    # /cmdb/system/global supplies hostname, opmode, timezone
    $globalRaw = Invoke-FgApi -Path '/cmdb/system/global'
    $global = $null
    if ($globalRaw) {
        if ($globalRaw -is [array]) { $global = $globalRaw[0] } else { $global = $globalRaw }
    }

    # ---- Helper: read a value safely from an object by trying several key names
    function Read-Field {
        param($Obj, [string[]]$Keys)
        foreach ($k in $Keys) {
            if ($null -eq $Obj) { continue }
            $props = $Obj.PSObject.Properties.Name
            if ($props -contains $k) {
                $v = $Obj.$k
                if ($null -ne $v -and [string]$v -ne '') { return [string]$v }
            }
        }
        return ''
    }

    # ---- Pull from /monitor/system/status (top-level response properties)
    # These fields ARE present in the response (serial/version/build/hostname/uptime confirmed working)
    $serial    = Read-Field $mon @('serial')
    $firmware  = Read-Field $mon @('version')
    $buildNum  = Read-Field $mon @('build')
    $hostname  = Read-Field $mon @('hostname','host_name')
    $uptimeSec = Read-Field $mon @('uptime','sys_uptime')

    # model_name / system_time / op_mode are NOT present on all FortiOS versions
    # in the monitor endpoint - pull from cmdb/system/global and cmdb/system/status instead
    $model   = Read-Field $mon @('model_name','model','platform_id','platform_full_name')
    $sysTime = Read-Field $mon @('system_time','sys_time','current_time')
    $opModeRaw = Read-Field $mon @('op_mode','opmode','operation_mode')

    # Uptime -> human readable
    $uptimeStr = ''
    if ($uptimeSec -ne '') {
        try {
            $sec     = [int]$uptimeSec
            $days    = [math]::Floor($sec / 86400)
            $hours   = [math]::Floor(($sec % 86400) / 3600)
            $minutes = [math]::Floor(($sec % 3600) / 60)
            $uptimeStr = ($days.ToString() + 'd ' + $hours.ToString() + 'h ' + $minutes.ToString() + 'm')
        } catch {}
    }

    # ---- Fill gaps from /cmdb/system/global
    # hostname, opmode are reliably present here
    if ($global) {
        if ($hostname -eq '') { $hostname = Read-Field $global @('hostname') }
        if ($model    -eq '') { $model    = Read-Field $global @('model_name','alias') }
        if ($opModeRaw -eq '') { $opModeRaw = Read-Field $global @('opmode','operation-mode') }
    }

    # ---- System time fallback: use PowerShell to query SNMP-style or just use current
    # FortiOS cmdb/system/ntp or monitor/system/time
    if ($sysTime -eq '') {
        try {
            $timeUri = 'https://' + $FortiGateHost + ':' + $Port + '/api/v2/monitor/system/time?vdom=' + $Vdom
            $tHeaders = @{}
            if ($PSCmdlet.ParameterSetName -eq 'Token') { $tHeaders['Authorization'] = 'Bearer ' + $ApiToken }
            $tSplat = @{ Uri = $timeUri; Method = 'GET'; Headers = $tHeaders }
            if ($PSCmdlet.ParameterSetName -eq 'Credential') { $tSplat['WebSession'] = $script:FgSession }
            if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 7) { $tSplat['SkipCertificateCheck'] = $true }
            $timeRaw = Invoke-RestMethod @tSplat
            if ($timeRaw) {
                $sysTime = Read-Field $timeRaw @('time','datetime','current_time','system_time')
                if ($sysTime -eq '' -and $timeRaw.results) {
                    $sysTime = Read-Field $timeRaw.results @('time','datetime','current_time','system_time')
                }
            }
        } catch {}
    }

    # ---- Mode
    $mode = ''
    if     ($opModeRaw -eq '0' -or $opModeRaw -eq 'nat')         { $mode = 'NAT' }
    elseif ($opModeRaw -eq '1' -or $opModeRaw -eq 'transparent') { $mode = 'Transparent' }
    elseif ($opModeRaw -ne '')                                    { $mode = $opModeRaw }

    # ---- WAN IP: use already-collected interfaces (passed in) to avoid a second API call
    # Filter: must have a real non-zero IP, skip loopback/VLAN/tunnel types
    $wanIp = ''
    $allIfaces = Invoke-FgApi -Path '/cmdb/system/interface'
    if ($allIfaces) {
        $wanPriority = @()
        $wanFallback = @()
        foreach ($iface in $allIfaces) {
            $ifName = [string]$iface.name
            $ifRole = [string]$iface.role
            $ifType = [string]$iface.type
            $ifIp   = [string]$iface.ip
            $ifMask = [string]$iface.netmask

            # Skip if no real IP or loopback/tunnel/aggregate with no IP
            if ($ifIp -eq '' -or $ifIp -eq '0.0.0.0 0.0.0.0' -or $ifIp -eq '0.0.0.0') { continue }
            if ($ifType -eq 'loopback') { continue }

            # FortiOS stores ip as "x.x.x.x" and netmask separately
            # Some versions store as "x.x.x.x y.y.y.y" space-separated in one field
            $cleanIp = $ifIp
            if ($ifIp -match ' ') {
                $parts   = $ifIp -split ' '
                $cleanIp = $parts[0]
                if ($ifMask -eq '' -or $ifMask -eq '0.0.0.0') { $ifMask = $parts[1] }
            }
            if ($cleanIp -eq '0.0.0.0') { continue }

            $cidr     = ConvertTo-CidrMask -DottedMask $ifMask
            $ipWithCidr = $cleanIp + '/' + $cidr + ' (' + $ifName + ')'

            # Role=wan or name matches wan pattern = highest priority
            if ($ifRole -eq 'wan' -or $ifName -match '^wan') {
                $wanPriority += $ipWithCidr
            } elseif ($ifName -match '^(ppp|dialer|internet|INTERNET)' -or $ifType -eq 'pppoe') {
                $wanFallback += $ipWithCidr
            }
        }
        $allWan = $wanPriority + $wanFallback
        if ($allWan.Count -gt 0) { $wanIp = $allWan -join ' | ' }
    }

    $sysInfo = [PSCustomObject]@{
        Hostname     = $hostname
        SerialNumber = $serial
        Model        = $model
        Firmware     = $firmware
        BuildNumber  = $buildNum
        Mode         = $mode
        SystemTime   = $sysTime
        Uptime       = $uptimeStr
        WanIp        = $wanIp
        Vdom         = $Vdom
        CollectedAt  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }

    Write-Host ('  Hostname: ' + $hostname + '  Serial: ' + $serial + '  Firmware: ' + $firmware) -ForegroundColor Green
    return $sysInfo
}

# ---------------------------------------------------------------------------
# Collect interfaces and VLANs
# ---------------------------------------------------------------------------
function Get-Interfaces {
    Write-Host "`n[2/13] Collecting network interfaces..." -ForegroundColor Yellow
    $raw = Invoke-FgApi -Path '/cmdb/system/interface'

    $standard = @()
    $vlans    = @()

    if (-not $raw) {
        Write-Warning "  No interface data returned."
    } else {
        foreach ($iface in $raw) {
            $ipCidr = Format-IpCidr -Ip $iface.ip -Mask $iface.netmask

            $secIps = @()
            if ($iface.secondaryip) {
                foreach ($s in $iface.secondaryip) {
                    $secIps += Format-IpCidr -Ip $s.ip -Mask $s.netmask
                }
            }

            $obj = [PSCustomObject]@{
                Name            = $iface.name
                Alias           = $iface.alias
                Type            = $iface.type
                Status          = $iface.status
                IpAddress       = $iface.ip
                Netmask         = $iface.netmask
                IpCidr          = $ipCidr
                MacAddress      = $iface.macaddr
                Speed           = $iface.speed
                Mtu             = $iface.mtu
                Zone            = $iface.zone
                AllowAccess     = $iface.'allowaccess'
                Description     = $iface.description
                VlanId          = $iface.'vlanid'
                ParentInterface = $iface.'interface'
                SecondaryIps    = $secIps
            }

            if ($iface.type -eq 'vlan') {
                $vlans += $obj
            } else {
                $standard += $obj
            }
        }
        Write-Host ('  Found ' + $standard.Count + ' standard interface(s) and ' + $vlans.Count + ' VLAN(s).') -ForegroundColor Green
    }

    return [PSCustomObject]@{
        Standard = $standard
        Vlans    = $vlans
    }
}

# ---------------------------------------------------------------------------
# Collect IPsec VPN
# ---------------------------------------------------------------------------
function Get-IpsecVpn {
    Write-Host "`n[3/13] Collecting IPsec VPN configurations..." -ForegroundColor Yellow

    $ph1Raw = Invoke-FgApi -Path '/cmdb/vpn.ipsec/phase1-interface'
    $phase1 = @()
    if ($ph1Raw) {
        foreach ($p in $ph1Raw) {
            $phase1 += [PSCustomObject]@{
                Name             = $p.name
                Type             = $p.type
                Interface        = $p.interface
                IkeVersion       = $p.'ike-version'
                LocalGateway     = $p.'local-gw'
                RemoteGateway    = $p.'remote-gw'
                Proposal         = $p.'proposal'
                DhGroup          = $p.'dhgrp'
                AuthMethod       = $p.'authmethod'
                PeerType         = $p.'peertype'
                PeerId           = $p.'peerid'
                Mode             = $p.'mode'
                NatTraversal     = $p.'nattraversal'
                DpdRetryCount    = $p.'dpd-retrycount'
                DpdRetryInterval = $p.'dpd-retryinterval'
                Lifetime         = $p.'keylifeseconds'
                Comments         = $p.'comments'
            }
        }
    }

    $ph2Raw = Invoke-FgApi -Path '/cmdb/vpn.ipsec/phase2-interface'
    $phase2 = @()
    if ($ph2Raw) {
        foreach ($p in $ph2Raw) {
            $phase2 += [PSCustomObject]@{
                Name          = $p.name
                Phase1Name    = $p.'phase1name'
                Proposal      = $p.'proposal'
                DhGroup       = $p.'dhgrp'
                Lifetime      = $p.'keylifeseconds'
                AutoNegotiate = $p.'auto-negotiate'
                SrcAddrType   = $p.'src-addr-type'
                SrcSubnet     = $p.'src-subnet'
                DstAddrType   = $p.'dst-addr-type'
                DstSubnet     = $p.'dst-subnet'
                Comments      = $p.'comments'
            }
        }
    }

    Write-Host ('  Found ' + $phase1.Count + ' Phase-1 and ' + $phase2.Count + ' Phase-2 tunnel(s).') -ForegroundColor Green
    return [PSCustomObject]@{ Phase1 = $phase1; Phase2 = $phase2 }
}

# ---------------------------------------------------------------------------
# Collect SSL/OpenVPN
# ---------------------------------------------------------------------------
function Get-SslVpn {
    Write-Host "`n[4/13] Collecting SSL/OpenVPN configurations..." -ForegroundColor Yellow

    $settingsRaw = Invoke-FgApi -Path '/cmdb/vpn.ssl/settings'
    $settings    = $null
    if ($settingsRaw) {
        $s = $settingsRaw | Select-Object -First 1
        $listenIfaces = @()
        if ($s.'source-interface') {
            foreach ($i in $s.'source-interface') { $listenIfaces += $i.name }
        }
        $ipPools = @()
        if ($s.'tunnel-ip-pools') {
            foreach ($i in $s.'tunnel-ip-pools') { $ipPools += $i.name }
        }
        $settings = [PSCustomObject]@{
            Status          = $s.status
            ListenPort      = $s.'port'
            ListenInterface = $listenIfaces
            DnsServer1      = $s.'dns-server1'
            DnsServer2      = $s.'dns-server2'
            WinsServer1     = $s.'wins-server1'
            TunnelIpPools   = $ipPools
            AuthTimeout     = $s.'auth-timeout'
            IdleTimeout     = $s.'idle-timeout'
            DtlsEnable      = $s.'dtls-enable'
        }
    }

    $portalsRaw = Invoke-FgApi -Path '/cmdb/vpn.ssl/portal'
    $portals    = @()
    if ($portalsRaw) {
        foreach ($p in $portalsRaw) {
            $tunnelPools = @()
            if ($p.'tunnel-ip-pools') {
                foreach ($i in $p.'tunnel-ip-pools') { $tunnelPools += $i.name }
            }
            $portals += [PSCustomObject]@{
                Name           = $p.name
                TunnelMode     = $p.'tunnel-mode'
                WebMode        = $p.'web-mode'
                IpMode         = $p.'ip-mode'
                TunnelIpPool   = $tunnelPools
                DnsServer1     = $p.'dns-server1'
                DnsServer2     = $p.'dns-server2'
                SplitTunneling = $p.'split-tunneling'
            }
        }
    }

    $sslStatus = 'unknown'
    if ($settings -and $settings.Status) { $sslStatus = $settings.Status }
    Write-Host ('  SSL-VPN status: ' + $sslStatus + ' | ' + $portals.Count + ' portal(s).') -ForegroundColor Green
    return [PSCustomObject]@{ Settings = $settings; Portals = $portals }
}

# ---------------------------------------------------------------------------
# Collect Firewall Policies
# ---------------------------------------------------------------------------
function Get-FirewallPolicy {
    Write-Host "`n[5/13] Collecting firewall policies..." -ForegroundColor Yellow

    $raw = Invoke-FgApi -Path '/cmdb/firewall/policy'
    $policies = @()

    if ($raw) {
        foreach ($p in $raw) {
            $srcIntf = @()
            if ($p.'srcintf') { foreach ($i in $p.'srcintf') { $srcIntf += $i.name } }

            $dstIntf = @()
            if ($p.'dstintf') { foreach ($i in $p.'dstintf') { $dstIntf += $i.name } }

            $srcAddr = @()
            if ($p.'srcaddr') { foreach ($i in $p.'srcaddr') { $srcAddr += $i.name } }

            $dstAddr = @()
            if ($p.'dstaddr') { foreach ($i in $p.'dstaddr') { $dstAddr += $i.name } }

            $services = @()
            if ($p.'service') { foreach ($i in $p.'service') { $services += $i.name } }

            $profiles = @()
            if ($p.'profile-group')     { $profiles += ('Group: ' + $p.'profile-group') }
            if ($p.'av-profile')        { $profiles += ('AV: ' + $p.'av-profile') }
            if ($p.'ips-sensor')        { $profiles += ('IPS: ' + $p.'ips-sensor') }
            if ($p.'webfilter-profile') { $profiles += ('WebFilter: ' + $p.'webfilter-profile') }
            if ($p.'ssl-ssh-profile')   { $profiles += ('SSL: ' + $p.'ssl-ssh-profile') }

            $policies += [PSCustomObject]@{
                PolicyId        = $p.policyid
                Name            = $p.name
                Status          = $p.status
                Action          = $p.action
                SrcInterfaces   = $srcIntf -join '; '
                DstInterfaces   = $dstIntf -join '; '
                SrcAddresses    = $srcAddr -join '; '
                DstAddresses    = $dstAddr -join '; '
                Services        = $services -join '; '
                Schedule        = $p.schedule
                Nat             = $p.nat
                LogTraffic      = $p.'logtraffic'
                Comments        = $p.comments
                SecurityProfiles= $profiles -join '; '
            }
        }
        Write-Host ('  Found ' + $policies.Count + ' firewall policy/policies.') -ForegroundColor Green
    } else {
        Write-Warning '  No firewall policy data returned.'
    }

    return $policies
}

# ---------------------------------------------------------------------------
# Collect Virtual IPs (VIPs / DNAT)
# ---------------------------------------------------------------------------
function Get-VirtualIPs {
    Write-Host "`n[6/13] Collecting virtual IPs..." -ForegroundColor Yellow

    $raw  = Invoke-FgApi -Path '/cmdb/firewall/vip'
    $vips = @()

    if ($raw) {
        foreach ($v in $raw) {
            $mappedIps = @()
            if ($v.'mappedip') { foreach ($m in $v.'mappedip') { $mappedIps += $m.range } }

            $vips += [PSCustomObject]@{
                Name            = $v.name
                Comment         = $v.comment
                Type            = $v.type
                ExternalInterface = $v.'extintf'
                ExternalIp      = $v.'extip'
                MappedIp        = $mappedIps -join '; '
                ExternalPort    = $v.'extport'
                MappedPort      = $v.'mappedport'
                Protocol        = $v.'protocol'
                PortForward     = $v.'portforward'
                NatSourceVip    = $v.'nat-source-vip'
                ArpReply        = $v.'arp-reply'
            }
        }
        Write-Host ('  Found ' + $vips.Count + ' virtual IP(s).') -ForegroundColor Green
    } else {
        Write-Warning '  No virtual IP data returned.'
    }

    # Also collect VIP groups
    $grpRaw = Invoke-FgApi -Path '/cmdb/firewall/vipgrp'
    $vipGroups = @()
    if ($grpRaw) {
        foreach ($g in $grpRaw) {
            $members = @()
            if ($g.member) { foreach ($m in $g.member) { $members += $m.name } }
            $vipGroups += [PSCustomObject]@{
                Name      = $g.name
                Interface = $g.interface
                Members   = $members -join '; '
                Comments  = $g.comments
            }
        }
        Write-Host ('  Found ' + $vipGroups.Count + ' VIP group(s).') -ForegroundColor Green
    }

    return [PSCustomObject]@{ Vips = $vips; Groups = $vipGroups }
}

# ---------------------------------------------------------------------------
# Collect DNS configuration
# ---------------------------------------------------------------------------
function Get-DnsConfig {
    Write-Host "`n[7/13] Collecting DNS configuration..." -ForegroundColor Yellow

    # Global DNS settings
    $settingsRaw = Invoke-FgApi -Path '/cmdb/system/dns'
    $settings    = $null
    if ($settingsRaw) {
        $s = $settingsRaw | Select-Object -First 1
        $altPrimary   = ''
        $altSecondary = ''
        if ($s.'alt-primary')   { $altPrimary   = $s.'alt-primary' }
        if ($s.'alt-secondary') { $altSecondary = $s.'alt-secondary' }

        $settings = [PSCustomObject]@{
            Primary        = $s.primary
            Secondary      = $s.secondary
            AltPrimary     = $altPrimary
            AltSecondary   = $altSecondary
            Protocol       = $s.protocol
            DnsCacheLimit  = $s.'dns-cache-limit'
            DnsCacheTtl    = $s.'dns-cache-ttl'
            CacheNotfound  = $s.'cache-notfound-responses'
            SourceIp       = $s.'source-ip'
            Interface      = $s.interface
            Domain         = $s.domain
        }
        Write-Host '  Global DNS settings collected.' -ForegroundColor Green
    } else {
        Write-Warning '  No global DNS settings returned.'
    }

    # DNS servers (FortiGate acting as DNS server for zones)
    $dnsServersRaw = Invoke-FgApi -Path '/cmdb/system/dns-server'
    $dnsServers    = @()
    if ($dnsServersRaw) {
        foreach ($d in $dnsServersRaw) {
            $dnsServers += [PSCustomObject]@{
                Name      = $d.name
                Mode      = $d.mode
                Dnsfilter = $d.'dnsfilter-profile'
            }
        }
        Write-Host ('  Found ' + $dnsServers.Count + ' DNS server interface(s).') -ForegroundColor Green
    }

    # DNS database / local zones
    $zonesRaw = Invoke-FgApi -Path '/cmdb/system/dns-database'
    $zones    = @()
    if ($zonesRaw) {
        foreach ($z in $zonesRaw) {
            $zones += [PSCustomObject]@{
                Name        = $z.name
                Status      = $z.status
                Domain      = $z.domain
                Type        = $z.type
                View        = $z.view
                Ttl         = $z.ttl
                PrimaryDns  = $z.'primary-name'
                Contact     = $z.contact
                AllowTo     = $z.'allow-transfer'
                SourceIp    = $z.'source-ip'
            }
        }
        Write-Host ('  Found ' + $zones.Count + ' DNS zone(s).') -ForegroundColor Green
    }

    # Static DNS entries
    $staticRaw = Invoke-FgApi -Path '/cmdb/system/dns-entry'
    $static    = @()
    if ($staticRaw) {
        foreach ($e in $staticRaw) {
            $static += [PSCustomObject]@{
                Id       = $e.id
                Status   = $e.status
                Type     = $e.type
                Hostname = $e.hostname
                Ip       = $e.ip
                Ipv6     = $e.ipv6
                Ttl      = $e.ttl
                Zone     = $e.'dns-zone'
            }
        }
        Write-Host ('  Found ' + $static.Count + ' static DNS entry/entries.') -ForegroundColor Green
    }

    return [PSCustomObject]@{
        Settings    = $settings
        DnsServers  = $dnsServers
        Zones       = $zones
        StaticEntries = $static
    }
}

# ---------------------------------------------------------------------------
# Collect DHCP configuration
# ---------------------------------------------------------------------------
function Get-DhcpConfig {
    Write-Host "`n[8/13] Collecting DHCP configuration..." -ForegroundColor Yellow

    $raw     = Invoke-FgApi -Path '/cmdb/system.dhcp/server'
    $servers = @()
    $ranges  = @()
    $reservations = @()
    $options = @()

    if ($raw) {
        foreach ($s in $raw) {
            # DNS servers
            $dnsServers = @()
            if ($s.'dns-server1') { $dnsServers += $s.'dns-server1' }
            if ($s.'dns-server2') { $dnsServers += $s.'dns-server2' }
            if ($s.'dns-server3') { $dnsServers += $s.'dns-server3' }

            # WINS servers
            $winsServers = @()
            if ($s.'wins-server1') { $winsServers += $s.'wins-server1' }
            if ($s.'wins-server2') { $winsServers += $s.'wins-server2' }

            $servers += [PSCustomObject]@{
                Id              = $s.id
                Status          = $s.status
                Interface       = $s.interface
                Type            = $s.type
                Netmask         = $s.netmask
                Gateway         = $s.'default-gateway'
                Domain          = $s.domain
                LeaseTime       = $s.'lease-time'
                DnsService      = $s.'dns-service'
                DnsServers      = $dnsServers -join '; '
                WinsServers     = $winsServers -join '; '
                NtpServer1      = $s.'ntp-server1'
                NtpServer2      = $s.'ntp-server2'
                NtpService      = $s.'ntp-service'
                Timezone        = $s.'timezone'
                TimezoneOption  = $s.'timezone-option'
                NextServer      = $s.'next-server'
                Filename        = $s.filename
                VciMatch        = $s.'vci-match'
            }

            # IP ranges per server
            if ($s.'ip-range') {
                foreach ($r in $s.'ip-range') {
                    $ranges += [PSCustomObject]@{
                        ServerId        = $s.id
                        ServerInterface = $s.interface
                        RangeId         = $r.id
                        StartIp         = $r.'start-ip'
                        EndIp           = $r.'end-ip'
                    }
                }
            }

            # Reserved addresses (MAC-to-IP)
            if ($s.'reserved-address') {
                foreach ($res in $s.'reserved-address') {
                    $reservations += [PSCustomObject]@{
                        ServerId        = $s.id
                        ServerInterface = $s.interface
                        ReservationId   = $res.id
                        Type            = $res.type
                        Ip              = $res.ip
                        Mac             = $res.mac
                        CircuitId       = $res.'circuit-id'
                        RemoteId        = $res.'remote-id'
                        Description     = $res.description
                        Action          = $res.action
                    }
                }
            }

            # Custom DHCP options
            if ($s.'options') {
                foreach ($o in $s.'options') {
                    $options += [PSCustomObject]@{
                        ServerId        = $s.id
                        ServerInterface = $s.interface
                        OptionId        = $o.id
                        Code            = $o.code
                        Type            = $o.type
                        Value           = $o.value
                        Ip              = $o.ip -join '; '
                    }
                }
            }
        }

        Write-Host ('  Found ' + $servers.Count + ' DHCP server(s), ' +
                    $ranges.Count + ' range(s), ' +
                    $reservations.Count + ' reservation(s).') -ForegroundColor Green
    } else {
        Write-Warning '  No DHCP server data returned.'
    }

    return [PSCustomObject]@{
        Servers      = $servers
        Ranges       = $ranges
        Reservations = $reservations
        Options      = $options
    }
}

# ---------------------------------------------------------------------------
# Collect User Definitions
# ---------------------------------------------------------------------------
function Get-UserDefinitions {
    Write-Host "`n[9/13] Collecting user definitions..." -ForegroundColor Yellow

    # Local users
    $localRaw = Invoke-FgApi -Path '/cmdb/user/local'
    $local    = @()
    if ($localRaw) {
        foreach ($u in $localRaw) {
            $local += [PSCustomObject]@{
                Name          = $u.name
                Status        = $u.status
                Type          = $u.type
                EmailTo       = $u.'email-to'
                MobileNumber  = $u.'sms-phone'
                TwoFactor     = $u.'two-factor'
                TwoFactorAuth = $u.'two-factor-authentication'
                RadiusServer  = $u.'radius-server'
                LdapServer    = $u.'ldap-server'
                TacacsServer  = $u.'tacacs+-server'
                Fortitoken    = $u.fortitoken
                PasswdPolicy  = $u.'passwd-policy'
                PasswdTime    = $u.'passwd-time'
                AuthConcurrent = $u.'authtimeout'
            }
        }
        Write-Host ('  Found ' + $local.Count + ' local user(s).') -ForegroundColor Green
    } else {
        Write-Warning '  No local user data returned.'
    }

    # LDAP users
    $ldapRaw = Invoke-FgApi -Path '/cmdb/user/ldap'
    $ldap    = @()
    if ($ldapRaw) {
        foreach ($u in $ldapRaw) {
            $ldap += [PSCustomObject]@{
                Name           = $u.name
                Server         = $u.server
                SecondaryServer = $u.'secondary-server'
                TertiaryServer = $u.'tertiary-server'
                Port           = $u.port
                CnId           = $u.'cnid'
                Dn             = $u.dn
                Type           = $u.type
                Username       = $u.username
                Secure         = $u.secure
                CaCert         = $u.'ca-cert'
                SearchType     = $u.'search-type'
                GroupMemberCheck = $u.'group-member-check'
                GroupFilter    = $u.'group-filter'
                GroupObjectFilter = $u.'group-object-filter'
            }
        }
        Write-Host ('  Found ' + $ldap.Count + ' LDAP server definition(s).') -ForegroundColor Green
    }

    # TACACS+ users
    $tacacsRaw = Invoke-FgApi -Path '/cmdb/user/tacacs+'
    $tacacs    = @()
    if ($tacacsRaw) {
        foreach ($u in $tacacsRaw) {
            $tacacs += [PSCustomObject]@{
                Name            = $u.name
                Server          = $u.server
                SecondaryServer = $u.'secondary-server'
                TertiaryServer  = $u.'tertiary-server'
                Port            = $u.port
                Authen          = $u.authen
                Authorization   = $u.authorization
                Accounting      = $u.accounting
                KeySet          = if ($u.key) { 'Yes (set)' } else { 'No' }
            }
        }
        Write-Host ('  Found ' + $tacacs.Count + ' TACACS+ server definition(s).') -ForegroundColor Green
    }

    return [PSCustomObject]@{
        LocalUsers  = $local
        LdapServers = $ldap
        TacacsServers = $tacacs
    }
}

# ---------------------------------------------------------------------------
# Collect User Groups
# ---------------------------------------------------------------------------
function Get-UserGroups {
    Write-Host "`n[10/13] Collecting user groups..." -ForegroundColor Yellow

    $raw    = Invoke-FgApi -Path '/cmdb/user/group'
    $groups = @()

    if ($raw) {
        foreach ($g in $raw) {
            # Members (local users, LDAP/RADIUS/TACACS refs)
            $members = @()
            if ($g.member) {
                foreach ($m in $g.member) { $members += $m.name }
            }

            # Match rules (used for RADIUS/LDAP group matching)
            $matchRules = @()
            if ($g.match) {
                foreach ($r in $g.match) {
                    $matchRules += ($r.'server-name' + ':' + $r.'group-name')
                }
            }

            $groups += [PSCustomObject]@{
                Name        = $g.name
                Type        = $g.'group-type'
                AuthTimeout = $g.authtimeout
                HttpDigest  = $g.'http-digest-realm'
                Members     = $members -join '; '
                MatchRules  = $matchRules -join '; '
            }
        }
        Write-Host ('  Found ' + $groups.Count + ' user group(s).') -ForegroundColor Green
    } else {
        Write-Warning '  No user group data returned.'
    }

    return $groups
}

# ---------------------------------------------------------------------------
# Collect RADIUS Servers
# ---------------------------------------------------------------------------
function Get-RadiusServers {
    Write-Host "`n[11/13] Collecting RADIUS servers..." -ForegroundColor Yellow

    $raw     = Invoke-FgApi -Path '/cmdb/user/radius'
    $servers = @()

    if ($raw) {
        foreach ($r in $raw) {
            # Secondary and tertiary servers
            $secondary = ''
            $tertiary  = ''
            if ($r.'secondary-server') { $secondary = $r.'secondary-server' }
            if ($r.'tertiary-server')  { $tertiary  = $r.'tertiary-server' }

            # Accounting servers
            $acctServers = @()
            if ($r.'acct-server') {
                foreach ($a in $r.'acct-server') {
                    $acctServers += ($a.server + ':' + $a.port)
                }
            }

            # Attribute entries
            $attributes = @()
            if ($r.'radius-attribute') {
                foreach ($a in $r.'radius-attribute') {
                    $attributes += ('Type:' + $a.type + '=' + $a.value)
                }
            }

            $servers += [PSCustomObject]@{
                Name              = $r.name
                Server            = $r.server
                SecondaryServer   = $secondary
                TertiaryServer    = $tertiary
                Port              = $r.'auth-type'
                AuthType          = $r.'auth-type'
                SecretSet         = if ($r.secret) { 'Yes (set)' } else { 'No' }
                Timeout           = $r.timeout
                Retransmit        = $r.retransmit
                NasIp             = $r.'nas-ip'
                NasId             = $r.'nas-id'
                NasIdType         = $r.'nas-id-type'
                AcctAllServers    = $r.'acct-all-servers'
                AccountingServers = $acctServers -join '; '
                Attributes        = $attributes -join '; '
                SsoAttributeKey   = $r.'sso-attribute-key'
                SsoAttributeValue = $r.'sso-attribute-value-override'
                RssoEndpointBlock = $r.'rsso-endpoint-block'
            }
        }
        Write-Host ('  Found ' + $servers.Count + ' RADIUS server(s).') -ForegroundColor Green
    } else {
        Write-Warning '  No RADIUS server data returned.'
    }

    return $servers
}

# ---------------------------------------------------------------------------
# Collect Connected Devices (ARP, DHCP leases, active clients)
# ---------------------------------------------------------------------------
function Get-ConnectedDevices {
    Write-Host "`n[13/13] Collecting connected devices..." -ForegroundColor Yellow

    # ARP table - layer 2 to layer 3 mappings seen by the firewall
    $arpRaw = Invoke-FgApi -Path '/monitor/network/arp'
    $arp    = @()
    if ($arpRaw) {
        foreach ($a in $arpRaw) {
            $arp += [PSCustomObject]@{
                IpAddress   = $a.ip
                MacAddress  = $a.mac
                Interface   = $a.interface
                Type        = $a.type
                Status      = $a.status
            }
        }
        Write-Host ('  Found ' + $arp.Count + ' ARP entry/entries.') -ForegroundColor Green
    } else {
        Write-Warning '  No ARP data returned.'
    }

    # Active DHCP leases - devices currently holding a lease
    $leasesRaw = Invoke-FgApi -Path '/monitor/system/dhcp'
    $leases    = @()
    if ($leasesRaw) {
        foreach ($l in $leasesRaw) {
            $leases += [PSCustomObject]@{
                IpAddress   = $l.ip
                MacAddress  = $l.mac
                Hostname    = $l.hostname
                Interface   = $l.interface
                VlanId      = $l.'vci'
                Status      = $l.status
                ExpireTime  = $l.'expire-time'
                ServerName  = $l.'dhcp-server-name'
            }
        }
        Write-Host ('  Found ' + $leases.Count + ' active DHCP lease(s).') -ForegroundColor Green
    } else {
        Write-Warning '  No DHCP lease data returned.'
    }

    # Device table - FortiGate detected/learned device inventory
    $devRaw = Invoke-FgApi -Path '/monitor/user/device'
    $devices = @()
    if ($devRaw) {
        foreach ($d in $devRaw) {
            $ipList = @()
            if ($d.'ipv4-address') { $ipList += $d.'ipv4-address' }
            if ($d.'ipv6-address') { $ipList += $d.'ipv6-address' }

            $devices += [PSCustomObject]@{
                MacAddress    = $d.mac
                Hostname      = $d.hostname
                IpAddresses   = $ipList -join '; '
                Interface     = $d.interface
                VlanId        = $d.vlan
                OsName        = $d.'os-name'
                OsVersion     = $d.'os-version'
                DeviceType    = $d.'device-type'
                Vendor        = $d.vendor
                Category      = $d.category
                FirstSeen     = $d.'first-seen'
                LastSeen      = $d.'last-seen'
                MasterDevice  = $d.'master-mac'
                IsOnline      = $d.'is-online'
            }
        }
        Write-Host ('  Found ' + $devices.Count + ' detected device(s).') -ForegroundColor Green
    } else {
        Write-Warning '  No device inventory data returned.'
    }

    # Firewall sessions summary per source IP (connected/active traffic)
    $sessRaw = Invoke-FgApi -Path '/monitor/firewall/session'
    $sessions = @()
    if ($sessRaw) {
        # Aggregate by source IP to avoid thousands of individual session rows
        $grouped = @{}
        foreach ($s in $sessRaw) {
            $srcIp = $s.'srcip'
            if ([string]::IsNullOrEmpty($srcIp)) { continue }
            if (-not $grouped.ContainsKey($srcIp)) {
                $grouped[$srcIp] = [PSCustomObject]@{
                    SourceIp      = $srcIp
                    SrcInterface  = $s.'src_intf'
                    DstInterface  = $s.'dst_intf'
                    SessionCount  = 0
                    Protocols     = @{}
                }
            }
            $grouped[$srcIp].SessionCount++
            $proto = $s.'proto_name'
            if ($proto -and -not $grouped[$srcIp].Protocols.ContainsKey($proto)) {
                $grouped[$srcIp].Protocols[$proto] = 0
            }
            if ($proto) { $grouped[$srcIp].Protocols[$proto]++ }
        }
        foreach ($key in $grouped.Keys) {
            $row = $grouped[$key]
            $protoStr = @()
            foreach ($p in $row.Protocols.Keys) {
                $protoStr += ($p + '(' + $row.Protocols[$p] + ')')
            }
            $sessions += [PSCustomObject]@{
                SourceIp     = $row.SourceIp
                SrcInterface = $row.SrcInterface
                DstInterface = $row.DstInterface
                SessionCount = $row.SessionCount
                Protocols    = $protoStr -join '; '
            }
        }
        $sessions = $sessions | Sort-Object -Property SessionCount -Descending
        Write-Host ('  Found active sessions from ' + $sessions.Count + ' unique source IP(s).') -ForegroundColor Green
    } else {
        Write-Warning '  No session data returned (may require admin privileges).'
    }

    return [PSCustomObject]@{
        ArpTable   = $arp
        DhcpLeases = $leases
        Devices    = $devices
        Sessions   = $sessions
    }
}

# ---------------------------------------------------------------------------
# Collect License Information
# ---------------------------------------------------------------------------
function Get-Licenses {
    Write-Host "`n[12/13] Collecting license information..." -ForegroundColor Yellow

    $licenses = @()

    $licRaw = $null
    try {
        $uri     = 'https://' + $FortiGateHost + ':' + $Port + '/api/v2/monitor/license/status?vdom=' + $Vdom
        $headers = @{}
        if ($PSCmdlet.ParameterSetName -eq 'Token') { $headers['Authorization'] = 'Bearer ' + $ApiToken }
        $splat = @{ Uri = $uri; Method = 'GET'; Headers = $headers }
        if ($PSCmdlet.ParameterSetName -eq 'Credential') { $splat['WebSession'] = $script:FgSession }
        if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 7) { $splat['SkipCertificateCheck'] = $true }
        $licRaw = Invoke-RestMethod @splat
    } catch {
        Write-Warning ('  /monitor/license/status failed: ' + $_.Exception.Message)
    }

    if ($licRaw) {
        $src = $licRaw
        if ($licRaw.PSObject.Properties.Name -contains 'results') { $src = $licRaw.results }

        $licenseKeys = @(
            'forticare', 'av', 'ips', 'appctrl', 'web_filtering', 'antispam',
            'voip', 'mobile_malware', 'forticloud', 'fortianalyzer_cloud',
            'fortimanager_cloud', 'fortisandbox_cloud', 'sdn_connector',
            'ot_security', 'fortitoken_cloud', 'industrial_security',
            'security_rating', 'sdwan_manager', 'fortiems_cloud',
            'endpoint_control', 'dlp', 'nac', 'fortiguard', 'support'
        )

        foreach ($key in $licenseKeys) {
            if ($src.PSObject.Properties.Name -contains $key) {
                $lic = $src.$key
                if ($null -eq $lic) { continue }

                $expiryRaw  = ''
                $expiryDate = ''
                $daysLeft   = ''
                $status     = ''

                if ($lic.PSObject.Properties.Name -contains 'expires')     { $expiryRaw = [string]$lic.expires }
                if ($lic.PSObject.Properties.Name -contains 'expiry_date') { $expiryRaw = [string]$lic.expiry_date }
                if ($lic.PSObject.Properties.Name -contains 'status')      { $status    = [string]$lic.status }
                if ($status -eq '' -and $lic.PSObject.Properties.Name -contains 'type') { $status = [string]$lic.type }

                if ($expiryRaw -ne '' -and $expiryRaw -ne '0') {
                    try {
                        $epoch = [int64]$expiryRaw
                        if ($epoch -gt 1000000) {
                            $expiryDate = ([System.DateTimeOffset]::FromUnixTimeSeconds($epoch)).LocalDateTime.ToString('yyyy-MM-dd')
                            $days = ([System.DateTimeOffset]::FromUnixTimeSeconds($epoch).LocalDateTime - (Get-Date)).Days
                            $daysLeft = $days.ToString()
                        }
                    } catch {
                        $expiryDate = $expiryRaw
                        try {
                            $days = ([datetime]::Parse($expiryRaw) - (Get-Date)).Days
                            $daysLeft = $days.ToString()
                        } catch {}
                    }
                }

                $version = ''
                $serial  = ''
                $account = ''
                if ($lic.PSObject.Properties.Name -contains 'version') { $version = [string]$lic.version }
                if ($lic.PSObject.Properties.Name -contains 'serial')  { $serial  = [string]$lic.serial }
                if ($lic.PSObject.Properties.Name -contains 'account') { $account = [string]$lic.account }

                $licenses += [PSCustomObject]@{
                    LicenseType   = $key.Replace('_',' ').ToUpper()
                    Status        = $status
                    ExpiryDate    = $expiryDate
                    DaysRemaining = $daysLeft
                    Version       = $version
                    Serial        = $serial
                    Account       = $account
                }
            }
        }

        # Capture any additional unlisted license keys dynamically
        foreach ($prop in $src.PSObject.Properties) {
            $key = $prop.Name
            if ($licenseKeys -contains $key) { continue }
            if ($key -in @('status','http_method','revision','vdom','path','name','action','serial','build','version')) { continue }
            $lic = $prop.Value
            if ($null -eq $lic -or $lic -isnot [System.Management.Automation.PSCustomObject]) { continue }

            $expiryRaw  = ''
            $expiryDate = ''
            $daysLeft   = ''
            $licStatus  = ''

            if ($lic.PSObject.Properties.Name -contains 'expires')     { $expiryRaw = [string]$lic.expires }
            if ($lic.PSObject.Properties.Name -contains 'expiry_date') { $expiryRaw = [string]$lic.expiry_date }
            if ($lic.PSObject.Properties.Name -contains 'status')      { $licStatus = [string]$lic.status }

            if ($expiryRaw -ne '' -and $expiryRaw -ne '0') {
                try {
                    $epoch = [int64]$expiryRaw
                    if ($epoch -gt 1000000) {
                        $expiryDate = ([System.DateTimeOffset]::FromUnixTimeSeconds($epoch)).LocalDateTime.ToString('yyyy-MM-dd')
                        $days = ([System.DateTimeOffset]::FromUnixTimeSeconds($epoch).LocalDateTime - (Get-Date)).Days
                        $daysLeft = $days.ToString()
                    }
                } catch {
                    $expiryDate = $expiryRaw
                    try {
                        $days = ([datetime]::Parse($expiryRaw) - (Get-Date)).Days
                        $daysLeft = $days.ToString()
                    } catch {}
                }
            }

            $licenses += [PSCustomObject]@{
                LicenseType   = $key.Replace('_',' ').ToUpper()
                Status        = $licStatus
                ExpiryDate    = $expiryDate
                DaysRemaining = $daysLeft
                Version       = ''
                Serial        = ''
                Account       = ''
            }
        }
    } else {
        Write-Warning '  No license data returned.'
    }

    if ($licenses.Count -gt 0) {
        Write-Host ('  Found ' + $licenses.Count + ' license(s).') -ForegroundColor Green
        foreach ($lic in $licenses) {
            if ($lic.DaysRemaining -ne '' -and [int]$lic.DaysRemaining -lt 30 -and [int]$lic.DaysRemaining -ge 0) {
                Write-Warning ('  WARNING: ' + $lic.LicenseType + ' expires in ' + $lic.DaysRemaining + ' day(s) on ' + $lic.ExpiryDate)
            }
            if ($lic.DaysRemaining -ne '' -and [int]$lic.DaysRemaining -lt 0) {
                Write-Warning ('  EXPIRED:  ' + $lic.LicenseType + ' expired on ' + $lic.ExpiryDate)
            }
        }
    }

    return $licenses
}

# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------
function Show-Section {
    param([string]$Title)
    Write-Host ("`n== " + $Title + " ==") -ForegroundColor Cyan
}

function Show-InterfacesTable {
    param($Interfaces, [string]$Title)
    Show-Section -Title $Title
    $count = Get-SafeCount -Collection $Interfaces
    if ($count -eq 0) { Write-Host "  (none)"; return }
    $Interfaces | Format-Table -AutoSize -Property Name, Alias, Status, IpCidr, MacAddress, ParentInterface, VlanId, Description
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  FortiGate Configuration Collector" -ForegroundColor Magenta
Write-Host ("  Target : " + $FortiGateHost + "  |  VDOM: " + $Vdom) -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

Initialize-TlsBypass

if ($PSCmdlet.ParameterSetName -eq 'Credential') {
    Write-Host "`nAuthenticating with credentials..." -ForegroundColor Cyan
    Connect-FortiGate
}

# Test connectivity before attempting all endpoints
$connected = Test-FortiGateConnection
if (-not $connected) {
    Write-Host "`nExiting - please fix the connection issue and re-run." -ForegroundColor Red
    exit 1
}

# Collect
$sysInfo      = Get-SystemInfo
$ifaceResult  = Get-Interfaces
$ipsec        = Get-IpsecVpn
$sslvpn       = Get-SslVpn
$fwPolicy     = Get-FirewallPolicy
$vipResult    = Get-VirtualIPs
$dnsResult    = Get-DnsConfig
$dhcpResult   = Get-DhcpConfig
$userResult   = Get-UserDefinitions
$userGroups   = Get-UserGroups
$radiusResult    = Get-RadiusServers
$licenseResult   = Get-Licenses
$connectedResult = Get-ConnectedDevices

# Display
Show-Section -Title 'System Information'
if ($null -eq $sysInfo) { Write-Host "  (none)" }
else { $sysInfo | Format-List }

Show-Section -Title 'Licenses'
$licCount = Get-SafeCount -Collection $licenseResult
if ($licCount -eq 0) { Write-Host "  (none)" }
else { $licenseResult | Format-Table -AutoSize LicenseType, Status, ExpiryDate, DaysRemaining, Version, Account }

Show-InterfacesTable -Interfaces $ifaceResult.Standard -Title 'Standard Network Interfaces'
Show-InterfacesTable -Interfaces $ifaceResult.Vlans    -Title 'VLAN Interfaces'

Show-Section -Title 'IPsec VPN - Phase 1 Tunnels'
$ph1Count = Get-SafeCount -Collection $ipsec.Phase1
if ($ph1Count -eq 0) { Write-Host "  (none)" }
else { $ipsec.Phase1 | Format-Table -AutoSize Name, Type, Interface, IkeVersion, RemoteGateway, Proposal, DhGroup, AuthMethod }

Show-Section -Title 'IPsec VPN - Phase 2 Selectors'
$ph2Count = Get-SafeCount -Collection $ipsec.Phase2
if ($ph2Count -eq 0) { Write-Host "  (none)" }
else { $ipsec.Phase2 | Format-Table -AutoSize Name, Phase1Name, Proposal, DhGroup, SrcSubnet, DstSubnet }

Show-Section -Title 'SSL/OpenVPN - Global Settings'
if ($null -eq $sslvpn.Settings) { Write-Host "  (not configured)" }
else { $sslvpn.Settings | Format-List }

Show-Section -Title 'SSL/OpenVPN - Portals'
$portalCount = Get-SafeCount -Collection $sslvpn.Portals
if ($portalCount -eq 0) { Write-Host "  (none)" }
else { $sslvpn.Portals | Format-Table -AutoSize Name, TunnelMode, WebMode, IpMode, DnsServer1, SplitTunneling }

Show-Section -Title 'Firewall Policies'
$fwCount = Get-SafeCount -Collection $fwPolicy
if ($fwCount -eq 0) { Write-Host "  (none)" }
else { $fwPolicy | Format-Table -AutoSize PolicyId, Name, Status, Action, SrcInterfaces, DstInterfaces, SrcAddresses, DstAddresses, Services, Nat }

Show-Section -Title 'Virtual IPs (DNAT)'
$vipCount = Get-SafeCount -Collection $vipResult.Vips
if ($vipCount -eq 0) { Write-Host "  (none)" }
else { $vipResult.Vips | Format-Table -AutoSize Name, Type, ExternalInterface, ExternalIp, MappedIp, ExternalPort, MappedPort, PortForward }

Show-Section -Title 'VIP Groups'
$vipGrpCount = Get-SafeCount -Collection $vipResult.Groups
if ($vipGrpCount -eq 0) { Write-Host "  (none)" }
else { $vipResult.Groups | Format-Table -AutoSize Name, Interface, Members, Comments }

Show-Section -Title 'DNS - Global Settings'
if ($null -eq $dnsResult.Settings) { Write-Host "  (not configured)" }
else { $dnsResult.Settings | Format-List }

Show-Section -Title 'DNS - Server Interfaces'
$dnsSrvCount = Get-SafeCount -Collection $dnsResult.DnsServers
if ($dnsSrvCount -eq 0) { Write-Host "  (none)" }
else { $dnsResult.DnsServers | Format-Table -AutoSize Name, Mode, Dnsfilter }

Show-Section -Title 'DNS - Zones'
$zoneCount = Get-SafeCount -Collection $dnsResult.Zones
if ($zoneCount -eq 0) { Write-Host "  (none)" }
else { $dnsResult.Zones | Format-Table -AutoSize Name, Status, Domain, Type, View, Ttl, PrimaryDns }

Show-Section -Title 'DNS - Static Entries'
$staticCount = Get-SafeCount -Collection $dnsResult.StaticEntries
if ($staticCount -eq 0) { Write-Host "  (none)" }
else { $dnsResult.StaticEntries | Format-Table -AutoSize Id, Status, Type, Hostname, Ip, Ttl, Zone }

Show-Section -Title 'DHCP Servers'
$dhcpSrvCount = Get-SafeCount -Collection $dhcpResult.Servers
if ($dhcpSrvCount -eq 0) { Write-Host "  (none)" }
else { $dhcpResult.Servers | Format-Table -AutoSize Id, Status, Interface, Gateway, Netmask, LeaseTime, DnsService, DnsServers, Domain }

Show-Section -Title 'DHCP IP Ranges'
$dhcpRngCount = Get-SafeCount -Collection $dhcpResult.Ranges
if ($dhcpRngCount -eq 0) { Write-Host "  (none)" }
else { $dhcpResult.Ranges | Format-Table -AutoSize ServerId, ServerInterface, RangeId, StartIp, EndIp }

Show-Section -Title 'DHCP Reservations (MAC-to-IP)'
$dhcpResCount = Get-SafeCount -Collection $dhcpResult.Reservations
if ($dhcpResCount -eq 0) { Write-Host "  (none)" }
else { $dhcpResult.Reservations | Format-Table -AutoSize ServerId, ServerInterface, Ip, Mac, Description, Action }

Show-Section -Title 'DHCP Custom Options'
$dhcpOptCount = Get-SafeCount -Collection $dhcpResult.Options
if ($dhcpOptCount -eq 0) { Write-Host "  (none)" }
else { $dhcpResult.Options | Format-Table -AutoSize ServerId, ServerInterface, Code, Type, Value }

Show-Section -Title 'Users - Local'
$localUserCount = Get-SafeCount -Collection $userResult.LocalUsers
if ($localUserCount -eq 0) { Write-Host "  (none)" }
else { $userResult.LocalUsers | Format-Table -AutoSize Name, Status, Type, TwoFactor, RadiusServer, LdapServer, EmailTo }

Show-Section -Title 'Users - LDAP Servers'
$ldapCount = Get-SafeCount -Collection $userResult.LdapServers
if ($ldapCount -eq 0) { Write-Host "  (none)" }
else { $userResult.LdapServers | Format-Table -AutoSize Name, Server, Port, Dn, Type, Secure, GroupMemberCheck }

Show-Section -Title 'Users - TACACS+ Servers'
$tacacsCount = Get-SafeCount -Collection $userResult.TacacsServers
if ($tacacsCount -eq 0) { Write-Host "  (none)" }
else { $userResult.TacacsServers | Format-Table -AutoSize Name, Server, Port, Authen, Authorization, Accounting, KeySet }

Show-Section -Title 'User Groups'
$groupCount = Get-SafeCount -Collection $userGroups
if ($groupCount -eq 0) { Write-Host "  (none)" }
else { $userGroups | Format-Table -AutoSize Name, Type, AuthTimeout, Members, MatchRules }

Show-Section -Title 'RADIUS Servers'
$radiusCount = Get-SafeCount -Collection $radiusResult
if ($radiusCount -eq 0) { Write-Host "  (none)" }
else { $radiusResult | Format-Table -AutoSize Name, Server, SecondaryServer, Port, AuthType, SecretSet, Timeout, NasIp, AccountingServers }

Show-Section -Title 'Connected Devices - ARP Table'
$arpCount = Get-SafeCount -Collection $connectedResult.ArpTable
if ($arpCount -eq 0) { Write-Host "  (none)" }
else { $connectedResult.ArpTable | Format-Table -AutoSize IpAddress, MacAddress, Interface, Type, Status }

Show-Section -Title 'Connected Devices - DHCP Leases'
$leaseCount = Get-SafeCount -Collection $connectedResult.DhcpLeases
if ($leaseCount -eq 0) { Write-Host "  (none)" }
else { $connectedResult.DhcpLeases | Format-Table -AutoSize IpAddress, MacAddress, Hostname, Interface, Status, ExpireTime }

Show-Section -Title 'Connected Devices - Device Inventory'
$devCount = Get-SafeCount -Collection $connectedResult.Devices
if ($devCount -eq 0) { Write-Host "  (none)" }
else { $connectedResult.Devices | Format-Table -AutoSize MacAddress, Hostname, IpAddresses, Interface, OsName, DeviceType, Vendor, IsOnline, LastSeen }

Show-Section -Title 'Connected Devices - Active Sessions by Source IP'
$sessCount = Get-SafeCount -Collection $connectedResult.Sessions
if ($sessCount -eq 0) { Write-Host "  (none)" }
else { $connectedResult.Sessions | Format-Table -AutoSize SourceIp, SrcInterface, DstInterface, SessionCount, Protocols }

# ---------------------------------------------------------------------------
# CSV Export - one file per section in C:\Temp
# ---------------------------------------------------------------------------
$exportDir  = 'C:\Temp'
$datestamp  = Get-Date -Format 'yyyyMMdd'
$safeHost   = $FortiGateHost -replace '[^a-zA-Z0-9\-\.]', '_'
$fileSuffix = '_FG_' + $safeHost + '_' + $datestamp

if (-not (Test-Path -Path $exportDir)) {
    New-Item -ItemType Directory -Path $exportDir | Out-Null
    Write-Host ("`nCreated export directory: " + $exportDir) -ForegroundColor Cyan
}

Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "  Exporting CSV files to $exportDir" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

# ---------------------------------------------------------------------------
# Helper: flatten nested arrays to semicolon-separated strings then export
# ---------------------------------------------------------------------------
function Export-ToCsv {
    param($Data, [string]$Label, [string]$FilePath)
    $count = Get-SafeCount -Collection $Data
    if ($count -eq 0) {
        Write-Host ('  [SKIP] ' + $Label + ' - no data') -ForegroundColor DarkGray
        return
    }
    $flat = @()
    foreach ($row in $Data) {
        $props = [ordered]@{}
        foreach ($prop in $row.PSObject.Properties) {
            $val = $prop.Value
            if ($null -eq $val) {
                $props[$prop.Name] = ''
            } elseif ($val -is [array] -or $val -is [System.Collections.Generic.List[object]]) {
                $props[$prop.Name] = $val -join '; '
            } else {
                $props[$prop.Name] = $val
            }
        }
        $flat += [PSCustomObject]$props
    }
    $flat | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
    Write-Host ('  [OK]   ' + $Label + ' -> ' + $FilePath) -ForegroundColor Green
}

# System Info
Export-ToCsv -Data @($sysInfo) `
             -Label 'System Info' `
             -FilePath ($exportDir + '\' + 'system_info' + $fileSuffix + '.csv')

# Licenses
Export-ToCsv -Data $licenseResult `
             -Label 'Licenses' `
             -FilePath ($exportDir + '\' + 'licenses' + $fileSuffix + '.csv')

# Standard Interfaces
Export-ToCsv -Data $ifaceResult.Standard `
             -Label 'Standard Interfaces' `
             -FilePath ($exportDir + '\' + 'interfaces' + $fileSuffix + '.csv')

# VLANs
Export-ToCsv -Data $ifaceResult.Vlans `
             -Label 'VLANs' `
             -FilePath ($exportDir + '\' + 'vlans' + $fileSuffix + '.csv')

# IPsec Phase 1
Export-ToCsv -Data $ipsec.Phase1 `
             -Label 'IPsec Phase 1' `
             -FilePath ($exportDir + '\' + 'ipsec_phase1' + $fileSuffix + '.csv')

# IPsec Phase 2
Export-ToCsv -Data $ipsec.Phase2 `
             -Label 'IPsec Phase 2' `
             -FilePath ($exportDir + '\' + 'ipsec_phase2' + $fileSuffix + '.csv')

# SSL-VPN Settings
if ($null -ne $sslvpn.Settings) {
    Export-ToCsv -Data @($sslvpn.Settings) `
                 -Label 'SSL-VPN Settings' `
                 -FilePath ($exportDir + '\' + 'sslvpn_settings' + $fileSuffix + '.csv')
} else {
    Write-Host '  [SKIP] SSL-VPN Settings - not configured' -ForegroundColor DarkGray
}

# SSL-VPN Portals
Export-ToCsv -Data $sslvpn.Portals `
             -Label 'SSL-VPN Portals' `
             -FilePath ($exportDir + '\' + 'sslvpn_portals' + $fileSuffix + '.csv')

# Firewall Policies
Export-ToCsv -Data $fwPolicy `
             -Label 'Firewall Policies' `
             -FilePath ($exportDir + '\' + 'fw_policies' + $fileSuffix + '.csv')

# Virtual IPs
Export-ToCsv -Data $vipResult.Vips `
             -Label 'Virtual IPs' `
             -FilePath ($exportDir + '\' + 'vips' + $fileSuffix + '.csv')

# VIP Groups
Export-ToCsv -Data $vipResult.Groups `
             -Label 'VIP Groups' `
             -FilePath ($exportDir + '\' + 'vip_groups' + $fileSuffix + '.csv')

# DNS Global Settings
if ($null -ne $dnsResult.Settings) {
    Export-ToCsv -Data @($dnsResult.Settings) `
                 -Label 'DNS Global Settings' `
                 -FilePath ($exportDir + '\' + 'dns_settings' + $fileSuffix + '.csv')
} else {
    Write-Host '  [SKIP] DNS Global Settings - not configured' -ForegroundColor DarkGray
}

# DNS Server Interfaces
Export-ToCsv -Data $dnsResult.DnsServers `
             -Label 'DNS Server Interfaces' `
             -FilePath ($exportDir + '\' + 'dns_servers' + $fileSuffix + '.csv')

# DNS Zones
Export-ToCsv -Data $dnsResult.Zones `
             -Label 'DNS Zones' `
             -FilePath ($exportDir + '\' + 'dns_zones' + $fileSuffix + '.csv')

# DNS Static Entries
Export-ToCsv -Data $dnsResult.StaticEntries `
             -Label 'DNS Static Entries' `
             -FilePath ($exportDir + '\' + 'dns_static' + $fileSuffix + '.csv')

# DHCP Servers
Export-ToCsv -Data $dhcpResult.Servers `
             -Label 'DHCP Servers' `
             -FilePath ($exportDir + '\' + 'dhcp_servers' + $fileSuffix + '.csv')

# DHCP IP Ranges
Export-ToCsv -Data $dhcpResult.Ranges `
             -Label 'DHCP IP Ranges' `
             -FilePath ($exportDir + '\' + 'dhcp_ranges' + $fileSuffix + '.csv')

# DHCP Reservations
Export-ToCsv -Data $dhcpResult.Reservations `
             -Label 'DHCP Reservations' `
             -FilePath ($exportDir + '\' + 'dhcp_reservations' + $fileSuffix + '.csv')

# DHCP Custom Options
Export-ToCsv -Data $dhcpResult.Options `
             -Label 'DHCP Custom Options' `
             -FilePath ($exportDir + '\' + 'dhcp_options' + $fileSuffix + '.csv')

# Local Users
Export-ToCsv -Data $userResult.LocalUsers `
             -Label 'Local Users' `
             -FilePath ($exportDir + '\' + 'users_local' + $fileSuffix + '.csv')

# LDAP Servers
Export-ToCsv -Data $userResult.LdapServers `
             -Label 'LDAP Servers' `
             -FilePath ($exportDir + '\' + 'users_ldap' + $fileSuffix + '.csv')

# TACACS+ Servers
Export-ToCsv -Data $userResult.TacacsServers `
             -Label 'TACACS+ Servers' `
             -FilePath ($exportDir + '\' + 'users_tacacs' + $fileSuffix + '.csv')

# User Groups
Export-ToCsv -Data $userGroups `
             -Label 'User Groups' `
             -FilePath ($exportDir + '\' + 'user_groups' + $fileSuffix + '.csv')

# RADIUS Servers
Export-ToCsv -Data $radiusResult `
             -Label 'RADIUS Servers' `
             -FilePath ($exportDir + '\' + 'radius_servers' + $fileSuffix + '.csv')

# ARP Table
Export-ToCsv -Data $connectedResult.ArpTable `
             -Label 'ARP Table' `
             -FilePath ($exportDir + '\' + 'arp_table' + $fileSuffix + '.csv')

# DHCP Leases
Export-ToCsv -Data $connectedResult.DhcpLeases `
             -Label 'DHCP Leases' `
             -FilePath ($exportDir + '\' + 'dhcp_leases' + $fileSuffix + '.csv')

# Device Inventory
Export-ToCsv -Data $connectedResult.Devices `
             -Label 'Device Inventory' `
             -FilePath ($exportDir + '\' + 'device_inventory' + $fileSuffix + '.csv')

# Active Sessions
Export-ToCsv -Data $connectedResult.Sessions `
             -Label 'Active Sessions' `
             -FilePath ($exportDir + '\' + 'active_sessions' + $fileSuffix + '.csv')

Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "  Collection complete. Files saved to: $exportDir" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta
