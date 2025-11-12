<#
.SYNOPSIS
    Lists all virtual machines (VMs) on a specified Hyper-V host, including their power state.
.DESCRIPTION
    This script uses the Hyper-V PowerShell module via Invoke-Command to query VM name and state, 
    then exports the details to a CSV file.
.NOTES
    - Requires a domain account with local administrator rights on the target Hyper-V host.
    - Requires PowerShell Remoting (WinRM) to be enabled on the target Hyper-V host.
#>

# --- Configuration ---

# &#128721; IMPORTANT: Define the name of your Hyper-V Host Server here
$HyperVHost = "YOUR_HYPERV_HOST_NAME" 

# Define the output path for the CSV report
$ExportPath = "C:\Temp\HyperV_VM_State_Report.csv"

# Array to store all the collected VM data
$ReportData = @()

# --- Main Script Logic ---
Write-Host "--- Starting VM State Inventory for Host: $($HyperVHost) ---" -ForegroundColor Yellow

try {
    # 1. Use Invoke-Command to execute Get-VM on the remote host
    $VMs = Invoke-Command -ComputerName $HyperVHost -ScriptBlock {
        # Get all VMs and select only the Name and State
        Get-VM | Select-Object Name, State
    } -ErrorAction Stop
    
    Write-Host "✅ Successfully connected to $($HyperVHost)." -ForegroundColor Green
    
    if ($VMs) {
        Write-Host "Found $($VMs.Count) virtual machines." -ForegroundColor DarkGreen
        
        # 2. Iterate through VMs and format the output
        foreach ($VM in $VMs) {
            # Use a friendly status based on the State property
            $Status = switch ($VM.State) {
                "Running" { "On" }
                "Off"     { "Off" }
                "Saved"   { "Off (Saved State)" }
                default   { "Unknown / Other" }
            }
            
            $ReportData += [PSCustomObject]@{
                HyperVHost      = $HyperVHost
                VMName          = $VM.Name
                PowerState      = $Status
                RawState        = $VM.State # Original state for reference
            }
        }
    } else {
        Write-Host "❌ No virtual machines found on the host." -ForegroundColor Red
    }

}
catch {
    Write-Host "❌ Error connecting to or querying $($HyperVHost). Check host name, firewall, and WinRM/permissions." -ForegroundColor Red
    Write-Error "Details: $($_.Exception.Message)"
    exit 1
}

# 3. Export the final data to a CSV file
Write-Host ""
Write-Host "Exporting inventory to CSV..." -ForegroundColor Yellow

if ($ReportData.Count -gt 0) {
    $ReportData | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "✅ Export Complete! Total VMs listed: $($ReportData.Count)" -ForegroundColor Green
    Write-Host "File saved at: $ExportPath" -ForegroundColor Cyan
} else {
    Write-Host "❌ No data to export." -ForegroundColor Red
}
