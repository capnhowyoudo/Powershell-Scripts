<#
.SYNOPSIS
    Identifies all servers in the domain with the Remote Desktop Services role installed.
.DESCRIPTION
    This script utilizes WMI to check the Win32_ServerFeature class on all domain servers
    for the presence of the Remote Desktop Session Host (RDSH) feature (FeatureID 24).
.NOTES
    - Requires the ActiveDirectory PowerShell module (RSAT).
    - Requires a domain account with local administrator or remote management rights on 
      all potential servers for the WMI query to succeed.
#>

# Define the output path for the CSV report
$ExportPath = "C:\Temp\RemoteDesktopServers.csv"

# Array to store all the collected server data
$ReportData = @()

# The FeatureID for the Remote Desktop Session Host (RDSH) role on Windows Server 2008 R2 and later.
# This ID is reliable for identifying dedicated terminal servers.
$RDSH_FeatureID = 24 

# --- 1. Import and Server Discovery ---

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "✅ ActiveDirectory module loaded." -ForegroundColor Green
} catch {
    Write-Error "❌ Error: ActiveDirectory module is not installed or accessible. Aborting."
    exit 1
}

Write-Host "Searching Active Directory for Windows Servers..." -ForegroundColor Yellow

# Get a list of all enabled servers
$Servers = Get-ADComputer -Filter {Enabled -eq $True -and OperatingSystem -Like "Windows Server*"} -Properties Name | 
            Select-Object -ExpandProperty Name

Write-Host "Found $($Servers.Count) servers to check. Starting role verification..." -ForegroundColor Yellow

# --- 2. Iterate and Check for RDS Role (RDSH Feature) ---
foreach ($Server in $Servers) {
    Write-Host "Processing server: $($Server)" -ForegroundColor Cyan
    
    $ServerStatus = "Not Found"
    
    try {
        # Query the Win32_ServerFeature WMI class for the RDSH FeatureID (24)
        $RDSHRole = Get-CimInstance -ClassName Win32_ServerFeature -ComputerName $Server -ErrorAction Stop |
                    Where-Object { $_.ID -eq $RDSH_FeatureID }

        if ($RDSHRole) {
            $ServerStatus = "RDSH (Terminal Server)"
            
            # Get the server's IP address (for reference)
            $ServerIP = (Resolve-DnsName -Name $Server -ErrorAction SilentlyContinue).IPAddress | Select-Object -First 1
            
            # Create a custom object
            $ReportData += [PSCustomObject]@{
                ServerName       = $Server
                ServerIP         = $ServerIP
                RDSRole          = $ServerStatus
                FeatureName      = $RDSHRole.Name
                FeatureID        = $RDSHRole.ID
            }
            Write-Host "    ✅ Identified as: $($ServerStatus)" -ForegroundColor DarkGreen
        } else {
            Write-Host "    - RDSH Role not installed." -ForegroundColor DarkGray
        }

    }
    catch {
        Write-Host "    ❌ Connection Error (Check WinRM/Permissions): $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- 3. Export the final data to a CSV file ---
Write-Host ""
Write-Host "Exporting inventory to CSV..." -ForegroundColor Yellow

if ($ReportData.Count -gt 0) {
    $ReportData | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "✅ Export Complete! Total Terminal Servers found: $($ReportData.Count)" -ForegroundColor Green
    Write-Host "File saved at: $ExportPath" -ForegroundColor Cyan
} else {
    Write-Host "❌ No dedicated Remote Desktop Session Host servers were found." -ForegroundColor Red
}
