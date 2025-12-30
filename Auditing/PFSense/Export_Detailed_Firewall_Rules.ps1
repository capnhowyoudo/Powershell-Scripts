<#
.SYNOPSIS
Exports detailed pfSense firewall rules from the configuration XML to a CSV file.

.DESCRIPTION
This PowerShell script parses the pfSense configuration file (config.xml) to extract all firewall rules, including their:
- Status (enabled/disabled)
- Action (pass, block, reject)
- Interface and protocol
- Source and destination addresses and ports
- Gateway settings
- Logging and direction
- Description text  
It consolidates this information into a structured CSV file for documentation, auditing, or rule analysis. The script handles "Any" addresses and ports automatically and preserves descriptive comments for each rule.

.NOTES
1. Download config.xml from pfSense:
   - Login to pfSense web GUI
   - Go to Diagnostics → Backup/Restore
   - Click "Download configuration"
   - Save the file locally, e.g., C:\path\to\your\config.xml
2. Ensure PowerShell has permission to read the XML and write the CSV file.
3. Adjust `$xmlPath` and `$csvPath` variables to match your environment.
4. The CSV columns include: Tracker, Status, Action, Interface, Protocol, Source, SrcPort, Destination, DstPort, Gateway, Description, Log, Direction.
5. This script supports complex rule structures including custom gateways, logging, and descriptions. Any new or custom attributes in pfSense XML may require minor adjustments to the script.
#>

# Define paths
$xmlPath = "C:\path\to\your\config.xml"
$csvPath = "C:\temp\pfsense_firewall_rules_detailed.csv"

# Load the XML file
[xml]$pfConfig = Get-Content -Path $xmlPath
$ruleList = New-Object System.Collections.Generic.List[PSObject]

# Navigate to the filter node where rules are stored
$rules = $pfConfig.pfsense.filter.rule

foreach ($rule in $rules) {
    # Helper function to handle source/destination formatting
    function Get-Address {
        param($node)
        if ($node.network) { return $node.network }
        if ($node.address) { return $node.address }
        if ($node.any) { return "Any" }
        return "Unknown"
    }

    $ruleList.Add([PSCustomObject]@{
        Tracker      = $rule.tracker
        Status       = if ($rule.disabled -eq $null) { "Enabled" } else { "Disabled" }
        Action       = $rule.type # pass, block, or reject
        Interface    = $rule.interface
        Protocol     = if ($rule.protocol) { $rule.protocol } else { "Any" }
        
        # Source Details
        Source       = Get-Address $rule.source
        SrcPort      = if ($rule.source.port) { $rule.source.port } else { "Any" }
        
        # Destination Details
        Destination  = Get-Address $rule.destination
        DstPort      = if ($rule.destination.port) { $rule.destination.port } else { "Any" }
        
        # Advanced Features
        Gateway      = if ($rule.gateway) { $rule.gateway } else { "Default" }
        Description  = $rule.descr.'#cdata-section'
        Log          = if ($rule.log -ne $null) { "Yes" } else { "No" }
        Direction    = if ($rule.direction) { $rule.direction } else { "In" }
    })
}

# Export the results
$ruleList | Export-Csv -Path $csvPath -NoTypeInformation

Write-Host "Detailed Firewall Rules exported successfully to: $csvPath" -ForegroundColor Green
