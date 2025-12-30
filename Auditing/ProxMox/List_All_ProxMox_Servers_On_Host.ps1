<#
.synopsis
Lists all Proxmox virtual machines and exports results to CSV.

.description
Connects to the Proxmox VE REST API using an API token and retrieves all nodes
and virtual machines. For each VM, it reports the VM name, power status,
host node, and IP address.
IP address resolution uses QEMU Guest Agent first, then Cloud-Init network
configuration as a fallback.
Results are exported to C:\Temp as a CSV file.

.notes
API TOKEN CREATION (Proxmox VE):
1. Log in to the Proxmox Web UI: https://<proxmox-host>:8006
2. Navigate to: Datacenter -> Permissions -> API Tokens
3. Click "Add"
4. User: root@pam (or delegated user)
5. Token ID: powershell
6. Enable "Privilege Separation"
7. Click "Add" and COPY the token secret (shown once)

ASSIGN PERMISSIONS:
1. Datacenter -> Permissions
2. Add -> API Token Permission
3. Path: /
4. User: root@pam!powershell
5. Role: PVEAuditor

TOKEN FORMAT:
PVEAPIToken=user@realm!tokenid=tokensecret

NOTES:
- QEMU Guest Agent provides live IP addresses
- Cloud-Init ipconfig values are used as a fallback
- DHCP-only VMs without Guest Agent will show Unavailable
- Self-signed SSL certificates are ignored by this script
- Be sure to Change lines 65 & 68 to match your IP and Token
#>

# ============================
# SSL / TLS TRUST FIX
# ============================

# cmdlet: Add-Type
Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@

# cmdlet: [System.Net.ServicePointManager]::CertificatePolicy
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# ============================
# PROXMOX CONNECTION SETTINGS
# ============================

# cmdlet: $ProxmoxHost
$ProxmoxHost = "https://proxmox.example.com:8006"

# cmdlet: $APIToken
$APIToken = "PVEAPIToken=user@pam!tokenid=tokenvalue"

# cmdlet: $Headers
$Headers = @{
    Authorization = $APIToken
}

# ============================
# CSV EXPORT SETTINGS
# ============================

# cmdlet: $ExportPath
$ExportPath = "C:\Temp"

# cmdlet: $CsvFile
$CsvFile = Join-Path $ExportPath "Proxmox-VM-Inventory.csv"

# cmdlet: Test-Path
if (-not (Test-Path $ExportPath)) {
    # cmdlet: New-Item
    New-Item -Path $ExportPath -ItemType Directory | Out-Null
}

# ============================
# QUERY PROXMOX
# ============================

# cmdlet: Invoke-RestMethod
$Nodes = Invoke-RestMethod `
    -Method Get `
    -Uri "$ProxmoxHost/api2/json/nodes" `
    -Headers $Headers

# cmdlet: $Results
$Results = @()

foreach ($Node in $Nodes.data) {

    # cmdlet: Invoke-RestMethod
    $VMs = Invoke-RestMethod `
        -Method Get `
        -Uri "$ProxmoxHost/api2/json/nodes/$($Node.node)/qemu" `
        -Headers $Headers

    foreach ($VM in $VMs.data) {

        # cmdlet: $IPAddress
        $IPAddress = "Unavailable"

        # ============================
        # 1. TRY QEMU GUEST AGENT
        # ============================
        try {
            # cmdlet: Invoke-RestMethod
            $AgentInfo = Invoke-RestMethod `
                -Method Get `
                -Uri "$ProxmoxHost/api2/json/nodes/$($Node.node)/qemu/$($VM.vmid)/agent/network-get-interfaces" `
                -Headers $Headers

            # cmdlet: $IPAddress
            $IPAddress = (
                $AgentInfo.data.result |
                ForEach-Object { $_."ip-addresses" } |
                Where-Object {
                    $_."ip-address-type" -eq "ipv4" -and
                    $_."ip-address" -ne "127.0.0.1"
                } |
                Select-Object -ExpandProperty "ip-address" -First 1
            )
        }
        catch {
            # Guest agent not available
        }

        # ============================
        # 2. FALLBACK: CLOUD-INIT CONFIG
        # ============================
        if (-not $IPAddress) {

            # cmdlet: Invoke-RestMethod
            $VMConfig = Invoke-RestMethod `
                -Method Get `
                -Uri "$ProxmoxHost/api2/json/nodes/$($Node.node)/qemu/$($VM.vmid)/config" `
                -Headers $Headers

            foreach ($Key in $VMConfig.data.Keys) {
                if ($Key -like "ipconfig*") {
                    if ($VMConfig.data[$Key] -match "ip=([^,\/]+)") {
                        # cmdlet: $IPAddress
                        $IPAddress = $Matches[1]
                        break
                    }
                }
            }
        }

        # ============================
        # ADD RESULT
        # ============================

        # cmdlet: [PSCustomObject]
        $Results += [PSCustomObject]@{
            VMID      = $VM.vmid
            Name      = $VM.name
            Status    = $VM.status
            HostNode  = $Node.node
            IPAddress = $IPAddress
        }
    }
}

# ============================
# EXPORT & OUTPUT
# ============================

# cmdlet: Export-Csv
$Results |
    Sort-Object HostNode, Name |
    Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8

# cmdlet: Format-Table
$Results |
    Sort-Object HostNode, Name |
    Format-Table -AutoSize
