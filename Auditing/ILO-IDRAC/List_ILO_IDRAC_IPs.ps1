<#
.SYNOPSIS
    Gathers the IP address of iLO (HPE) and iDRAC (Dell) management interfaces
    from a list of target servers.
.DESCRIPTION
    The script iterates through a list of servers, checks the manufacturer, and then
    uses vendor-specific WMI or registry paths to find the management interface IP.
.NOTES
    - Requires WinRM to be enabled and configured for remote access on target servers.
    - Requires a domain account with local administrator rights on the target servers.
    - Vendor management tools (like iLO Configuration Utility or Dell OpenManage) must be
      installed on the target server for WMI/registry queries to succeed.
#>

# Define the output path for the CSV report
$ExportPath = "C:\Temp\RemoteManagementIPs.csv"

# Array to store all the collected data
$ReportData = @()

# --- 1. Server Discovery ---

Write-Host "Searching Active Directory for Windows Servers..." -ForegroundColor Yellow

# Get a list of all enabled Windows servers (adjust filter as needed)
$Servers = Get-ADComputer -Filter {Enabled -eq $True -and OperatingSystem -Like "Windows Server*"} -Properties Name | 
            Select-Object -ExpandProperty Name

Write-Host "Found $($Servers.Count) servers to check. Starting inventory..." -ForegroundColor Yellow

# --- 2. Iterate through each server to identify and get management IP ---
foreach ($Server in $Servers) {
    Write-Host "Processing server: $($Server)" -ForegroundColor Cyan
    
    $ManagementIP = "N/A"
    $ManagementType = "None"
    
    try {
        # Get system information to identify the vendor (Manufacturer)
        $SystemInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $Server -ErrorAction Stop
        $Manufacturer = $SystemInfo.Manufacturer
        
        # --- HPE iLO Check ---
        if ($Manufacturer -like "*HPE*" -or $Manufacturer -like "*HP*") {
            $ManagementType = "iLO"
            
            # iLO IP is often stored in a specific WMI class created by HPE tools
            $iLO = Get-CimInstance -ClassName HP_SystemProLiantSystem -Namespace root\hpq -ComputerName $Server -ErrorAction SilentlyContinue
            
            if ($iLO -and $iLO.iLOIPAddress) {
                $ManagementIP = $iLO.iLOIPAddress
            }
        }
        
        # --- Dell iDRAC Check ---
        elseif ($Manufacturer -like "*Dell*") {
            $ManagementType = "iDRAC"
            
            # iDRAC IP is often found in the Win32_NetworkAdapterConfiguration WMI class
            # or in a specific Dell WMI class. We'll use the latter for better specificity.
            $iDRAC = Get-CimInstance -ClassName DCIM_iDRACCard -Namespace root\dell\sysmgmt -ComputerName $Server -ErrorAction SilentlyContinue
            
            if ($iDRAC -and $iDRAC.CurrentIPAddress) {
                $ManagementIP = $iDRAC.CurrentIPAddress
            }
            # Fallback for older Dell machines or different configurations (checking network adapters)
            elseif ($iDRAC -and -not $iDRAC.CurrentIPAddress) {
                $iDRAC_Adapter = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ComputerName $Server -ErrorAction SilentlyContinue | Where-Object { $_.Description -like "*iDRAC*" }
                if ($iDRAC_Adapter -and $iDRAC_Adapter.IPAddress) {
                    $ManagementIP = $iDRAC_Adapter.IPAddress[0]
                }
            }
        }
        
        # Report the result for the current server
        $Status = if ($ManagementIP -ne "N/A") { "FOUND" } else { "NOT FOUND / Unknown Vendor" }
        Write-Host "    $($Status): Type: $($ManagementType), IP: $($ManagementIP)" -ForegroundColor Yellow
        
        # Create a custom object
        $ReportEntry = [PSCustomObject]@{
            ServerName       = $Server
            Manufacturer     = $Manufacturer
            ManagementType   = $ManagementType
            ManagementIP     = $ManagementIP
            QueryStatus      = $Status
        }
        
        $ReportData += $ReportEntry

    }
    catch {
        Write-Host "    ❌ Connection Error: $($_.Exception.Message)" -ForegroundColor Red
        $ReportData += [PSCustomObject]@{
            ServerName       = $Server
            Manufacturer     = "N/A (Error)"
            ManagementType   = "N/A"
            ManagementIP     = "N/A"
            QueryStatus      = "CONNECTION ERROR"
        }
    }
}

# --- 3. Export the final data to a CSV file ---
Write-Host ""
Write-Host "Exporting inventory to CSV..." -ForegroundColor Yellow

if ($ReportData.Count -gt 0) {
    $ReportData | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "✅ Export Complete! Total servers checked: $($ReportData.Count)" -ForegroundColor Green
    Write-Host "File saved at: $ExportPath" -ForegroundColor Cyan
} else {
    Write-Host "❌ No server data was collected." -ForegroundColor Red
}
