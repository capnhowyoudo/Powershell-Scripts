#Requires -Version 5.1
<#
.SYNOPSIS
    Retrieves network interfaces, VLANs, and VPN configurations from a FortiGate firewall.

.DESCRIPTION
    Connects to the FortiGate REST API and collects:
      - Standard network interfaces (IP, subnet, parent interface)
      - VLANs (tag, description, parent interface, IP/subnet)
      - IPsec VPN Phase 1 and Phase 2 configurations
      - SSL/OpenVPN server configurations
      - WireGuard peer configurations
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
    .\Get-FortiGateConfig.ps1 -FortiGateHost "192.168.1.1" -ApiToken "YourApiTokenHere"

.EXAMPLE
    # Self-signed cert (most common for on-prem FortiGates)
    .\Get-FortiGateConfig.ps1 -FortiGateHost "192.168.1.1" -ApiToken "YourApiTokenHere" -SkipCertificateCheck

.EXAMPLE
    # Non-standard management port
    .\Get-FortiGateConfig.ps1 -FortiGateHost "192.168.1.1" -ApiToken "YourApiTokenHere" -Port 8443 -SkipCertificateCheck

.EXAMPLE
    # Username and password instead of API token
    .\Get-FortiGateConfig.ps1 -FortiGateHost "192.168.1.1" -Credential (Get-Credential) -SkipCertificateCheck

.EXAMPLE
    # Query a specific VDOM
    .\Get-FortiGateConfig.ps1 -FortiGateHost "192.168.1.1" -ApiToken "YourApiTokenHere" -Vdom "CORP" -SkipCertificateCheck

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
# Collect interfaces and VLANs
# ---------------------------------------------------------------------------
function Get-Interfaces {
    Write-Host "`n[1/11] Collecting network interfaces..." -ForegroundColor Yellow
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
    Write-Host "`n[2/11] Collecting IPsec VPN configurations..." -ForegroundColor Yellow

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
    Write-Host "`n[3/11] Collecting SSL/OpenVPN configurations..." -ForegroundColor Yellow

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
# Collect WireGuard
# ---------------------------------------------------------------------------
function Get-WireGuard {
    Write-Host "`n[4/11] Collecting WireGuard configurations..." -ForegroundColor Yellow

    $wgRaw = Invoke-FgApi -Path '/cmdb/vpn.wireguard/profile'

    if (-not $wgRaw) {
        Write-Warning "  No WireGuard API endpoint found (requires FortiOS 7.2+); checking interfaces..."
        $allIfaces = Invoke-FgApi -Path '/cmdb/system/interface'
        if ($allIfaces) {
            $wgRaw = @($allIfaces | Where-Object { $_.type -eq 'tunnel' -and $_.'tunnel-type' -eq 'wireguard' })
        }
    }

    $profiles = @()
    if ($wgRaw) {
        foreach ($w in $wgRaw) {
            $peers = @()
            if ($w.peers) {
                foreach ($peer in $w.peers) {
                    $psk = '(none)'
                    if ($peer.'preshared-key') { $psk = '*** (set)' }
                    $peers += [PSCustomObject]@{
                        Name                = $peer.name
                        PublicKey           = $peer.'public-key'
                        PresharedKey        = $psk
                        AllowedIps          = $peer.'allowed-ips'
                        Endpoint            = $peer.'endpoint'
                        PersistentKeepalive = $peer.'persistent-keepalive'
                    }
                }
            }
            $profiles += [PSCustomObject]@{
                Name       = $w.name
                ListenPort = $w.'listen-port'
                LocalIp    = $w.ip
                Peers      = $peers
            }
        }
    }

    Write-Host ('  Found ' + $profiles.Count + ' WireGuard profile(s).') -ForegroundColor Green
    return $profiles
}

# ---------------------------------------------------------------------------
# Collect Firewall Policies
# ---------------------------------------------------------------------------
function Get-FirewallPolicy {
    Write-Host "`n[5/11] Collecting firewall policies..." -ForegroundColor Yellow

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
    Write-Host "`n[6/11] Collecting virtual IPs..." -ForegroundColor Yellow

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
    Write-Host "`n[7/11] Collecting DNS configuration..." -ForegroundColor Yellow

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
    Write-Host "`n[8/11] Collecting DHCP configuration..." -ForegroundColor Yellow

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
    Write-Host "`n[9/11] Collecting user definitions..." -ForegroundColor Yellow

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
    Write-Host "`n[10/11] Collecting user groups..." -ForegroundColor Yellow

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
    Write-Host "`n[11/11] Collecting RADIUS servers..." -ForegroundColor Yellow

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
$ifaceResult  = Get-Interfaces
$ipsec        = Get-IpsecVpn
$sslvpn       = Get-SslVpn
$wireguard    = Get-WireGuard
$fwPolicy     = Get-FirewallPolicy
$vipResult    = Get-VirtualIPs
$dnsResult    = Get-DnsConfig
$dhcpResult   = Get-DhcpConfig
$userResult   = Get-UserDefinitions
$userGroups   = Get-UserGroups
$radiusResult = Get-RadiusServers

# Display
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

Show-Section -Title 'WireGuard Profiles and Peers'
$wgCount = Get-SafeCount -Collection $wireguard
if ($wgCount -eq 0) { Write-Host "  (none / not configured)" }
else {
    foreach ($profile in $wireguard) {
        Write-Host ("  Profile: " + $profile.Name + "  ListenPort: " + $profile.ListenPort + "  LocalIP: " + $profile.LocalIp) -ForegroundColor White
        $peerCount = Get-SafeCount -Collection $profile.Peers
        if ($peerCount -eq 0) { Write-Host "    (no peers)" }
        else { $profile.Peers | Format-Table -AutoSize Name, PublicKey, AllowedIps, Endpoint, PersistentKeepalive, PresharedKey }
    }
}

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

# ---------------------------------------------------------------------------
# CSV Export - one file per section in C:\Temp
# ---------------------------------------------------------------------------
$exportDir  = 'C:\Temp'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$safeHost   = $FortiGateHost -replace '[^a-zA-Z0-9\-\.]', '_'
$filePrefix = $exportDir + '\FG_' + $safeHost + '_' + $timestamp

if (-not (Test-Path -Path $exportDir)) {
    New-Item -ItemType Directory -Path $exportDir | Out-Null
    Write-Host ("`nCreated export directory: " + $exportDir) -ForegroundColor Cyan
}

Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "  Exporting CSV files to $exportDir" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

function Export-ToCsv {
    param($Data, [string]$Label, [string]$FilePath)
    $count = Get-SafeCount -Collection $Data
    if ($count -eq 0) {
        Write-Host ('  [SKIP] ' + $Label + ' - no data') -ForegroundColor DarkGray
        return
    }
    # Flatten any array-valued properties to semicolon-separated strings
    $flat = @()
    foreach ($row in $Data) {
        $props = [ordered]@{}
        foreach ($prop in $row.PSObject.Properties) {
            $val = $prop.Value
            if ($val -is [array] -or $val -is [System.Collections.Generic.List[object]]) {
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

# Standard interfaces
Export-ToCsv -Data $ifaceResult.Standard `
             -Label 'Standard Interfaces' `
             -FilePath ($filePrefix + '_interfaces.csv')

# VLANs
Export-ToCsv -Data $ifaceResult.Vlans `
             -Label 'VLANs' `
             -FilePath ($filePrefix + '_vlans.csv')

# IPsec Phase 1
Export-ToCsv -Data $ipsec.Phase1 `
             -Label 'IPsec Phase 1' `
             -FilePath ($filePrefix + '_ipsec_phase1.csv')

# IPsec Phase 2
Export-ToCsv -Data $ipsec.Phase2 `
             -Label 'IPsec Phase 2' `
             -FilePath ($filePrefix + '_ipsec_phase2.csv')

# SSL-VPN Settings (single row)
if ($null -ne $sslvpn.Settings) {
    Export-ToCsv -Data @($sslvpn.Settings) `
                 -Label 'SSL-VPN Settings' `
                 -FilePath ($filePrefix + '_sslvpn_settings.csv')
} else {
    Write-Host '  [SKIP] SSL-VPN Settings - not configured' -ForegroundColor DarkGray
}

# SSL-VPN Portals
Export-ToCsv -Data $sslvpn.Portals `
             -Label 'SSL-VPN Portals' `
             -FilePath ($filePrefix + '_sslvpn_portals.csv')

# WireGuard peers (flatten profiles + peers into one table)
$wgFlat = @()
foreach ($profile in $wireguard) {
    $peerCount = Get-SafeCount -Collection $profile.Peers
    if ($peerCount -eq 0) {
        $wgFlat += [PSCustomObject]@{
            ProfileName = $profile.Name
            ListenPort  = $profile.ListenPort
            LocalIp     = $profile.LocalIp
            PeerName    = ''
            PublicKey   = ''
            PresharedKey        = ''
            AllowedIps          = ''
            Endpoint            = ''
            PersistentKeepalive = ''
        }
    } else {
        foreach ($peer in $profile.Peers) {
            $wgFlat += [PSCustomObject]@{
                ProfileName         = $profile.Name
                ListenPort          = $profile.ListenPort
                LocalIp             = $profile.LocalIp
                PeerName            = $peer.Name
                PublicKey           = $peer.PublicKey
                PresharedKey        = $peer.PresharedKey
                AllowedIps          = $peer.AllowedIps
                Endpoint            = $peer.Endpoint
                PersistentKeepalive = $peer.PersistentKeepalive
            }
        }
    }
}
Export-ToCsv -Data $wgFlat `
             -Label 'WireGuard Peers' `
             -FilePath ($filePrefix + '_wireguard.csv')

# Firewall Policies
Export-ToCsv -Data $fwPolicy `
             -Label 'Firewall Policies' `
             -FilePath ($filePrefix + '_fw_policies.csv')

# Virtual IPs
Export-ToCsv -Data $vipResult.Vips `
             -Label 'Virtual IPs' `
             -FilePath ($filePrefix + '_vips.csv')

# VIP Groups
Export-ToCsv -Data $vipResult.Groups `
             -Label 'VIP Groups' `
             -FilePath ($filePrefix + '_vip_groups.csv')

# DNS Global Settings
if ($null -ne $dnsResult.Settings) {
    Export-ToCsv -Data @($dnsResult.Settings) `
                 -Label 'DNS Global Settings' `
                 -FilePath ($filePrefix + '_dns_settings.csv')
} else {
    Write-Host '  [SKIP] DNS Global Settings - not configured' -ForegroundColor DarkGray
}

# DNS Server Interfaces
Export-ToCsv -Data $dnsResult.DnsServers `
             -Label 'DNS Server Interfaces' `
             -FilePath ($filePrefix + '_dns_servers.csv')

# DNS Zones
Export-ToCsv -Data $dnsResult.Zones `
             -Label 'DNS Zones' `
             -FilePath ($filePrefix + '_dns_zones.csv')

# DNS Static Entries
Export-ToCsv -Data $dnsResult.StaticEntries `
             -Label 'DNS Static Entries' `
             -FilePath ($filePrefix + '_dns_static.csv')

# DHCP Servers
Export-ToCsv -Data $dhcpResult.Servers `
             -Label 'DHCP Servers' `
             -FilePath ($filePrefix + '_dhcp_servers.csv')

# DHCP IP Ranges
Export-ToCsv -Data $dhcpResult.Ranges `
             -Label 'DHCP IP Ranges' `
             -FilePath ($filePrefix + '_dhcp_ranges.csv')

# DHCP Reservations
Export-ToCsv -Data $dhcpResult.Reservations `
             -Label 'DHCP Reservations' `
             -FilePath ($filePrefix + '_dhcp_reservations.csv')

# DHCP Custom Options
Export-ToCsv -Data $dhcpResult.Options `
             -Label 'DHCP Custom Options' `
             -FilePath ($filePrefix + '_dhcp_options.csv')

# Local Users
Export-ToCsv -Data $userResult.LocalUsers `
             -Label 'Local Users' `
             -FilePath ($filePrefix + '_users_local.csv')

# LDAP Server Definitions
Export-ToCsv -Data $userResult.LdapServers `
             -Label 'LDAP Servers' `
             -FilePath ($filePrefix + '_users_ldap.csv')

# TACACS+ Server Definitions
Export-ToCsv -Data $userResult.TacacsServers `
             -Label 'TACACS+ Servers' `
             -FilePath ($filePrefix + '_users_tacacs.csv')

# User Groups
Export-ToCsv -Data $userGroups `
             -Label 'User Groups' `
             -FilePath ($filePrefix + '_user_groups.csv')

# RADIUS Servers
Export-ToCsv -Data $radiusResult `
             -Label 'RADIUS Servers' `
             -FilePath ($filePrefix + '_radius_servers.csv')

Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "  Collection complete." -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta
