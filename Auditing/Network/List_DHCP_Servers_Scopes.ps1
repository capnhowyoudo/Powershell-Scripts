<#
.SYNOPSIS
    Gathers a list of all Domain Controllers (assumed to be primary DHCP servers)
    and lists the IPv4 DHCP scopes configured on them, exporting the data to CSV.
.DESCRIPTION
    The script finds all Domain Controllers in Active Directory, attempts to query 
    DHCP scope information from each server, and compiles the results.
.NOTES
    - Requires the ActiveDirectory and DHCPServer PowerShell modules.
    - Must be run with a domain account that has read access to AD and 
      read access to the DHCP configuration on the target servers.
#>

# Define the output path for the CSV report
$ExportPath = "C:\Temp\DHCP_Server_Scope_Inventory.csv"

# Array to store all the collected scope data
$ReportData = @()

# 1. Import the required modules
try {
    Import-Module ActiveDirectory, DHCPServer -ErrorAction Stop
    Write-Host "✅ Required modules (ActiveDirectory, DHCPServer) loaded." -ForegroundColor Green
} catch {
    Write-Error "❌ Error: Required modules are not installed or accessible. Aborting."
    exit 1
}

# 2. Identify Domain Controllers as potential DHCP Servers
Write-Host "Searching Active Directory for Domain Controllers..." -ForegroundColor Yellow
$Servers = Get-ADDomainController -Filter * | Select-Object -ExpandProperty Hostname

Write-Host "Found $($Servers.Count) potential DHCP servers to check. Starting inventory..." -ForegroundColor Yellow

# 3. Iterate through each server to check for DHCP scopes
foreach ($Server in $Servers) {
    Write-Host "Processing server: $($Server)" -ForegroundColor Cyan
    
    try {
        # Get all IPv4 scopes on the remote server
        $Scopes = Get-DhcpServerv4Scope -ComputerName $Server -ErrorAction Stop
        
        # If scopes are found, process the details
        if ($Scopes) {
            Write-Host "    ✅ Found $($Scopes.Count) DHCP scopes." -ForegroundColor DarkGreen
            
            foreach ($Scope in $Scopes) {
                # Get the IP address of the server (for reference)
                $ServerIP = (Resolve-DnsName -Name $Server -ErrorAction SilentlyContinue).IPAddress | Select-Object -First 1
                
                # Create a custom object with the desired properties
                $ReportEntry = [PSCustomObject]@{
                    DHCP_ServerName = $Server
                    ServerIP        = $ServerIP
                    ScopeID         = $Scope.ScopeId.ToString()
                    ScopeName       = $Scope.Name
                    StartRange      = $Scope.StartRange.ToString()
                    EndRange        = $Scope.EndRange.ToString()
                    SubnetMask      = $Scope.SubnetMask.ToString()
                    ScopeState      = $Scope.State
                    LeaseDuration   = $Scope.LeaseDuration.ToString()
                }
                
                # Add the entry to the report array
                $ReportData += $ReportEntry
            }
        }
        else {
            Write-Host "    - No DHCP scopes found on this server. Skipping." -ForegroundColor DarkGray
        }

    }
    catch {
        Write-Host "    ❌ Error connecting to $($Server) or enumerating scopes (Is DHCP role installed?): $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 4. Export the final data to a CSV file
Write-Host ""
Write-Host "Exporting inventory to CSV..." -ForegroundColor Yellow

if ($ReportData.Count -gt 0) {
    $ReportData | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "✅ Export Complete! Total scopes listed: $($ReportData.Count)" -ForegroundColor Green
    Write-Host "File saved at: $ExportPath" -ForegroundColor Cyan
} else {
    Write-Host "❌ No DHCP scopes were found on the identified servers." -ForegroundColor Red
}
