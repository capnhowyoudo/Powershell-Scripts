<#
.SYNOPSIS
Exports all DHCP static mappings from a pfSense configuration XML to a CSV file.

.DESCRIPTION
This PowerShell script parses the pfSense configuration file (config.xml) to extract DHCP static mappings configured on all interfaces (e.g., LAN, OPT1, etc.).  
For each static mapping, the script collects:
- Interface name
- Hostname
- IP address
- MAC address
- Description (from pfSense)
- Whether the entry is a static ARP table entry  
It consolidates this information into a structured CSV file for documentation, auditing, or network management purposes.

.NOTES
1. Download config.xml from pfSense:
   - Login to pfSense web GUI
   - Navigate to Diagnostics → Backup/Restore
   - Click "Download configuration"
   - Save the file locally, e.g., C:\path\to\your\config.xml
2. Ensure PowerShell has permission to read the XML and write the CSV file.
3. Adjust `$xmlPath` and `$csvPath` variables to match your environment.
4. The CSV columns include: Interface, Hostname, IP_Address, MAC_Address, Description, ARP_Table_Static.
5. If no static mappings exist, the script will issue a warning instead of creating an empty CSV.
#>

# Define paths
$xmlPath = "C:\path\to\your\config.xml"
$csvPath = "C:\Temp\pfsense_dhcp_static_mappings.csv"

# Load the XML file
[xml]$pfConfig = Get-Content -Path $xmlPath
$staticLeases = New-Object System.Collections.Generic.List[PSObject]

# Navigate to the dhcpd section (DHCP Daemon)
# pfSense organizes this by interface (e.g., <lan>, <opt1>)
$dhcpInterfaces = $pfConfig.pfsense.dhcpd

foreach ($interface in $dhcpInterfaces.ChildNodes) {
    $interfaceName = $interface.LocalName
    
    # Check if this interface has any static mappings defined
    if ($interface.staticmap) {
        foreach ($mapping in $interface.staticmap) {
            $staticLeases.Add([PSCustomObject]@{
                Interface   = $interfaceName
                Hostname    = $mapping.hostname
                IP_Address  = $mapping.ipaddr
                MAC_Address = $mapping.mac
                Description = $mapping.descr.'#cdata-section'
                ARP_Table_Static = if ($mapping.arp_table_static_entry) { "Yes" } else { "No" }
            })
        }
    }
}

# Export to CSV
if ($staticLeases.Count -gt 0) {
    $staticLeases | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "Success! $($staticLeases.Count) DHCP mappings exported to $csvPath" -ForegroundColor Green
} else {
    Write-Warning "No static DHCP mappings were found in the provided config.xml."
}
