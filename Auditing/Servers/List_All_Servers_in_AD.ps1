# PowerShell Script to Gather AD Server Inventory and VM Status

# --- Configuration ---
# Output file path for the results
$outputFile = "C:\Temp\AD_Server_Inventory_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

# Array to hold the results
$results = @()

# --- Step 1: Query Active Directory for a list of enabled servers ---
Write-Host "1. Querying Active Directory for all enabled servers..."

# Get all enabled computer objects where the OperatingSystem attribute contains 'Server'
# We request the 'OperatingSystem' and 'IPv4Address' properties from AD
$ADServers = Get-ADComputer -Filter 'OperatingSystem -like "*Server*" -and Enabled -eq $True' -Properties Name, OperatingSystem, IPv4Address, DNSHostName, LastLogonDate -ErrorAction Stop

Write-Host "Found $($ADServers.Count) enabled server objects in Active Directory."
Write-Host "---"

# --- Step 2: Query each server via WMI to determine VM Status ---

foreach ($server in $ADServers) {
    $serverName = $server.Name
    Write-Host "Processing server: $serverName..."

    # Use the IPv4Address property from AD as a potential connection target
    $ipAddress = $server.IPv4Address

    # Default values in case the WMI connection fails
    $isVirtual = $false
    $hostType = "N/A - Connection Error"

    # Test connection before attempting WMI/CIM, otherwise it can be slow
    if (Test-Connection -ComputerName $serverName -Count 1 -Quiet -ErrorAction SilentlyContinue) {
        try {
            # Use Get-CimInstance (modern replacement for Get-WmiObject)
            # The Win32_ComputerSystem class contains hardware model information
            $cim = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $serverName -ErrorAction Stop

            $manufacturer = $cim.Manufacturer
            $model = $cim.Model

            # Check Manufacturer/Model for common virtualization signatures
            if ($manufacturer -match "Microsoft|VMware|Bochs|QEMU|Xen" -or $model -match "Virtual Machine|VMware|Hyper-V|VirtualBox") {
                $isVirtual = $true
                
                if ($manufacturer -match "Microsoft") { $hostType = "Hyper-V" }
                elseif ($manufacturer -match "VMware") { $hostType = "VMware" }
                elseif ($manufacturer -match "Xen") { $hostType = "Xen/Citrix" }
                elseif ($manufacturer -match "Red Hat") { $hostType = "KVM" }
                else { $hostType = "Other VM" }
            } else {
                $hostType = "Physical"
            }
        }
        catch {
            $hostType = "WMI/CIM Error"
            Write-Warning "Could not query hardware info for $($serverName). Error: $($_.Exception.Message.Split("`n")[0])"
        }
    } else {
        Write-Warning "Server $($serverName) is not reachable via ping. Skipping WMI check."
    }

    # Create a custom object with the combined AD and WMI information
    $serverObject = [PSCustomObject]@{
        ServerName       = $serverName
        OperatingSystem  = $server.OperatingSystem
        IPv4Address_AD   = $ipAddress
        IsVirtualMachine = $isVirtual
        VirtualHostType  = $hostType
        LastLogonDate    = $server.LastLogonDate
    }

    # Add the object to the results array
    $results += $serverObject
}

# --- Step 3: Export the results ---
Write-Host "---"
Write-Host "3. Exporting results to CSV..."

$results | Export-Csv -Path $outputFile -NoTypeInformation

Write-Host "Script complete. Results saved to: $outputFile"
Write-Host "Total servers processed: $($ADServers.Count)"

