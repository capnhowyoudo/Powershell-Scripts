<#
.SYNOPSIS
    Lists all virtual machines (VMs) and their power state across multiple specified Hyper-V hosts.
.DESCRIPTION
    This script iterates through a list of host names, uses PowerShell Remoting (WinRM)
    to query VM details via Get-VM, and exports the combined results to a CSV file.
.NOTES
    - Requires a domain account with local administrator rights on ALL target Hyper-V hosts.
    - Requires PowerShell Remoting (WinRM) to be enabled on ALL target Hyper-V hosts.
#>

# --- Configuration ---

# &#128721; IMPORTANT: List ALL your Hyper-V Host Server names here
$HyperVHosts = @(
    "HVHOST01",
    "HVHOST02",
    "HVHOST-CLUSTER-NODE03",
    "ANOTHER_HYPERV_SERVER"
) 

# Define the output path for the CSV report
$ExportPath = "C:\Temp\MultiHost_VM_Inventory.csv"

# Array to store all the collected VM data
$ReportData = @()

# --- Main Script Logic ---
Write-Host "--- Starting VM Inventory Across $($HyperVHosts.Count) Hosts ---" -ForegroundColor Yellow

# Loop through each defined Hyper-V host
foreach ($HostName in $HyperVHosts) {
    Write-Host "Processing Host: $($HostName)" -ForegroundColor Cyan
    
    try {
        # 1. Use Invoke-Command to execute Get-VM on the remote host
        $VMs = Invoke-Command -ComputerName $HostName -ScriptBlock {
            # Get all VMs and select only the Name and State
            Get-VM | Select-Object Name, State
        } -ErrorAction Stop
        
        Write-Host "    ✅ Successfully connected. Found $($VMs.Count) virtual machines." -ForegroundColor DarkGreen
        
        # 2. Iterate through VMs and format the output
        foreach ($VM in $VMs) {
            # Determine a friendly power state
            $Status = switch ($VM.State) {
                "Running" { "On" }
                "Off"     { "Off" }
                "Saved"   { "Off (Saved State)" }
                default   { "Unknown / Other" }
            }
            
            $ReportData += [PSCustomObject]@{
                HyperVHost      = $HostName
                VMName          = $VM.Name
                PowerState      = $Status
                RawState        = $VM.State # Original state for debugging/reference
            }
        }

    }
    catch {
        Write-Host "    ❌ Error connecting to or querying $($HostName). Skipping this host." -ForegroundColor Red
        # Log a record for the failed host
        $ReportData += [PSCustomObject]@{
            HyperVHost      = $HostName
            VMName          = "CONNECTION ERROR"
            PowerState      = "FAILED"
            RawState        = $_.Exception.Message.Split("`n")[0] # Log the first line of the error message
        }
    }
}

# --- 3. Export the final data to a CSV file ---
Write-Host ""
Write-Host "Exporting inventory to CSV..." -ForegroundColor Yellow

if ($ReportData.Count -gt 0) {
    # Sort by HyperVHost then VMName for better readability
    $ReportData | Sort-Object HyperVHost, VMName | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "✅ Export Complete! Total entries listed: $($ReportData.Count)" -ForegroundColor Green
    Write-Host "File saved at: $ExportPath" -ForegroundColor Cyan
} else {
    Write-Host "❌ No data was successfully collected or exported." -ForegroundColor Red
}
