<#
.SYNOPSIS
Generates a summarized audit of a pfSense system and exports it to a CSV file.

.DESCRIPTION
This PowerShell script parses the pfSense configuration file (config.xml) to produce a high-level summary audit of the system.  
It captures key information including:
- Hostname and domain
- Hardware make, model, and serial number
- Netgate device license or CE indicator
- pfSense OS version
- Physical MAC addresses for all interfaces (including MAC overrides)  

The output is consolidated into a CSV for reporting or inventory purposes. IP addresses and network-specific details are intentionally excluded to focus on system identity and hardware audit.

.NOTES
1. Download config.xml from pfSense:
   - Login to pfSense web GUI
   - Go to Diagnostics → Backup/Restore
   - Click "Download configuration"
   - Save locally, e.g., C:\path\to\your\config.xml
2. Ensure PowerShell has permission to read the XML and write the CSV.
3. Adjust `$xmlPath` and `$csvPath` variables to match your environment.
4. The CSV columns include: Hostname, Domain, Make, Model, Serial_Number, NDI_License, OS_Version, Physical_MACs.
5. This script is useful for inventory audits, compliance reporting, or tracking pfSense deployments without exposing network IP information.
#>

# Define paths
$xmlPath = "C:\path\to\your\config.xml"
$csvPath = "C:\temp\pfsense_summary_audit.csv"

# Load the XML file
[xml]$pfConfig = Get-Content -Path $xmlPath
$summaryInfo = New-Object System.Collections.Generic.List[PSObject]

# --- 1. Get System Identity ---
$sys = $pfConfig.pfsense.system

# --- 2. Extract Physical Hardware Identifiers (MACs Only) ---
$macDetails = New-Object System.Collections.Generic.List[string]
$interfaces = $pfConfig.pfsense.interfaces.ChildNodes

foreach ($if in $interfaces) {
    $ifName = $if.LocalName.ToUpper()
    # Capture the MAC override if it exists, otherwise note it uses the hardware default
    $mac = if ($if.mac) { $if.mac } else { "Hardware Default" }
    $macDetails.Add("$ifName`[$mac]")
}

# --- 3. Construct the Summary Object ---
$obj = [PSCustomObject]@{
    Hostname       = $sys.hostname
    Domain         = $sys.domain
    Make           = if ($sys.netgate_device_id) { "Netgate" } else { "Generic/DIY" }
    Model          = if ($sys.external_model) { $sys.external_model } else { "Standard/Whitebox" }
    Serial_Number  = if ($sys.external_serial) { $sys.external_serial } else { "N/A" }
    NDI_License    = if ($sys.netgate_device_id) { $sys.netgate_device_id } else { "pfSense CE" }
    OS_Version     = $pfConfig.pfsense.version
    Physical_MACs  = $macDetails -join " | "
}

$summaryInfo.Add($obj)

# --- 4. Export to CSV ---
$summaryInfo | Export-Csv -Path $csvPath -NoTypeInformation

Write-Host "Summary Audit complete (IPs excluded)! File saved to: $csvPath" -ForegroundColor Green

# Display summary table to console
$obj | Format-Table -AutoSize
