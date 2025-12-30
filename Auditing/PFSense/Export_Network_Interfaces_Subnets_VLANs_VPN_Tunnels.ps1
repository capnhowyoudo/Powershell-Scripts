<#
.SYNOPSIS
Generates a consolidated network and VPN inventory from a pfSense configuration XML and exports it to a CSV file.

.DESCRIPTION
This PowerShell script parses a pfSense configuration file (config.xml) and extracts detailed information for:
- Standard network interfaces (IP addresses, subnets, physical parent interface)
- VLANs (tags, descriptions, parent interfaces)
- VPN configurations including IPsec (Phase 1 & Phase 2), OpenVPN (servers and clients), and WireGuard peers
For each entry, the script collects descriptive metadata and network information and produces a single CSV file suitable for documentation, auditing, or network management purposes.

.NOTES
1. Download config.xml from pfSense:
   - Login to pfSense web GUI
   - Navigate to Diagnostics → Backup/Restore
   - Click "Download configuration"
   - Save the file locally, e.g., C:\path\to\your\config.xml
2. Ensure PowerShell has permission to read the XML and write the CSV.
3. Adjust `$xmlPath` and `$csvPath` variables to match your environment.
4. The CSV columns include: Category, Type, ID, Description, Remote_Gateway, Local_Network, Remote_Network, Parent_Phys.
5. This script supports IPsec, OpenVPN, and WireGuard; other VPN types can be added by extending the parsing logic.
#>

# Define the path to your config.xml and the desired output CSV
$xmlPath = "C:\path\to\your\config.xml"
$csvPath = "C:\Temp\pfsense_interfaces.csv"

# Load the XML file
[xml]$pfConfig = Get-Content -Path $xmlPath
$report = New-Object System.Collections.Generic.List[PSObject]

# --- 1. Standard Interfaces ---
foreach ($ifNode in $pfConfig.pfsense.interfaces.ChildNodes) {
    $report.Add([PSCustomObject]@{
        Category       = "Network"
        Type           = "Interface"
        ID             = $ifNode.LocalName
        Description    = $ifNode.descr.'#cdata-section'
        Remote_Gateway = "N/A (Local)"
        Local_Network  = if ($ifNode.ipaddr) { "$($ifNode.ipaddr)/$($ifNode.subnet)" } else { "DHCP/None" }
        Remote_Network = "N/A"
        Parent_Phys    = $ifNode.if
    })
}

# --- 2. VLANs ---
foreach ($vlan in $pfConfig.pfsense.vlans.vlan) {
    $report.Add([PSCustomObject]@{
        Category       = "Network"
        Type           = "VLAN"
        ID             = "Tag: $($vlan.tag)"
        Description    = $vlan.descr.'#cdata-section'
        Remote_Gateway = "N/A"
        Local_Network  = "VLAN Tag $($vlan.tag)"
        Remote_Network = "N/A"
        Parent_Phys    = $vlan.if
    })
}

# --- 3. IPsec (Phase 1 & Phase 2) ---
foreach ($p1 in $pfConfig.pfsense.ipsec.phase1) {
    $ikeid = $p1.ikeid
    $p2Entries = $pfConfig.pfsense.ipsec.phase2 | Where-Object { $_.ikeid -eq $ikeid }
    
    foreach ($p2 in $p2Entries) {
        $report.Add([PSCustomObject]@{
            Category       = "VPN"
            Type           = "IPsec"
            ID             = "IKE:$($p1.ikeid)"
            Description    = $p1.descr.'#cdata-section'
            Remote_Gateway = $p1.remote_gateway
            Local_Network  = "$($p2.localid.address)/$($p2.localid.netbits)"
            Remote_Network = "$($p2.remoteid.address)/$($p2.remoteid.netbits)"
            Parent_Phys    = $p1.interface
        })
    }
}

# --- 4. OpenVPN (Servers & Clients) ---
$ovpnNodes = @($pfConfig.pfsense.openvpn.'openvpn-server'; $pfConfig.pfsense.openvpn.'openvpn-client')
foreach ($ovpn in $ovpnNodes) {
    if ($ovpn) {
        $report.Add([PSCustomObject]@{
            Category       = "VPN"
            Type           = "OpenVPN ($($ovpn.mode))"
            ID             = "VPNID:$($ovpn.vpnid)"
            Description    = $ovpn.description.'#cdata-section'
            Remote_Gateway = if ($ovpn.remote_host) { $ovpn.remote_host } else { "Listening" }
            Local_Network  = "Tunnel: $($ovpn.tunnel_network)"
            Remote_Network = if ($ovpn.remote_network) { $ovpn.remote_network } else { "Dynamic" }
            Parent_Phys    = $ovpn.interface
        })
    }
}

# --- 5. WireGuard (Peers & Tunnels) ---
foreach ($peer in $pfConfig.pfsense.wireguard.peer) {
    $report.Add([PSCustomObject]@{
        Category       = "VPN"
        Type           = "WireGuard"
        ID             = "Peer"
        Description    = $peer.descr.'#cdata-section'
        Remote_Gateway = if ($peer.endpoint) { $peer.endpoint } else { "Dynamic" }
        Local_Network  = "IF: $($peer.tun)"
        Remote_Network = $peer.allowedips
        Parent_Phys    = $peer.tun
    })
}

# Export to CSV
$report | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "Consolidated Export complete! File saved to: $csvPath" -ForegroundColor Green
