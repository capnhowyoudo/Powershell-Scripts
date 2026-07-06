<#
.SYNOPSIS
    Gathers an inventory of all file servers and their configured SMB shares in the domain.
.DESCRIPTION
    This script searches Active Directory for server operating systems, then connects
    to each one (plus the local machine) to list all SMB file shares — excluding
    printers, devices, IPC, and default administrative shares.
.NOTES
    - Requires the ActiveDirectory PowerShell module (RSAT).
    - Must be run with a domain account that has read access to AD and local administrator
      or remote management access to all potential file servers.
#>
# Define the output path for the CSV report
$ExportPath = "C:\Temp\FileShareInventory.csv"
# Array to store all the collected share data
$ReportData = @()
# 1. Import the required module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "✅ ActiveDirectory module loaded." -ForegroundColor Green
} catch {
    Write-Error "❌ Error: ActiveDirectory module is not installed or accessible. Aborting."
    exit 1
}
# 2. Identify potential File Servers in Active Directory
Write-Host "Searching Active Directory for potential File Servers..." -ForegroundColor Yellow
# Get a list of all enabled servers (excluding domain controllers and specific roles)
$Servers = Get-ADComputer -Filter {Enabled -eq $True -and OperatingSystem -Like "Windows Server*"} -Properties Name | 
            Where-Object { 
                $_.Name -notlike "*DC*" -and $_.Name -notlike "*EXCH*" -and $_.Name -notlike "*SQL*" 
            } | 
            Select-Object -ExpandProperty Name

# Include the local machine in the scan
$LocalHostName = $env:COMPUTERNAME
if ($Servers -notcontains $LocalHostName) {
    $Servers += $LocalHostName
    Write-Host "Added local machine ($LocalHostName) to the scan list." -ForegroundColor Yellow
}

Write-Host "Found $($Servers.Count) servers to check. Starting share enumeration..." -ForegroundColor Yellow
# 3. Iterate through each server to list SMB shares
foreach ($Server in $Servers) {
    Write-Host "Processing server: $($Server)" -ForegroundColor Cyan
    
    try {
        # Determine if this is the local machine
        $IsLocal = ($Server -eq $env:COMPUTERNAME)

        # Use Get-CimInstance to query the Win32_Share class (local or remote)
        # Type -eq 0 filters to Disk Drive shares only (excludes printers, devices, IPC)
        if ($IsLocal) {
            $Shares = Get-CimInstance -ClassName Win32_Share -ErrorAction Stop |
                      Where-Object { $_.Type -eq 0 -and $_.Name -notlike "*$" }
        } else {
            $Shares = Get-CimInstance -ClassName Win32_Share -ComputerName $Server -ErrorAction Stop |
                      Where-Object { $_.Type -eq 0 -and $_.Name -notlike "*$" }
        }
        
        # If shares are found, process the details
        if ($Shares) {
            Write-Host "    ✅ Found $($Shares.Count) SMB file shares." -ForegroundColor DarkGreen
            
            # Get the IP address of the file server (for reference)
            if ($IsLocal) {
                $ServerIP = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                             Where-Object { $_.IPAddress -ne "127.0.0.1" } |
                             Select-Object -First 1).IPAddress
            } else {
                $ServerIP = (Resolve-DnsName -Name $Server -ErrorAction SilentlyContinue).IPAddress | Select-Object -First 1
            }
            
            foreach ($Share in $Shares) {
                # Create a custom object with the desired properties
                $ReportEntry = [PSCustomObject]@{
                    FileServerName  = $Server
                    FileServerIP    = $ServerIP
                    ShareName       = $Share.Name
                    Path            = $Share.Path
                    Description     = $Share.Description
                }
                
                # Add the entry to the report array
                $ReportData += $ReportEntry
            }
        }
        else {
            Write-Host "    - No SMB file shares found. Skipping." -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "    ❌ Error connecting to $($Server) or enumerating shares: $($_.Exception.Message)" -ForegroundColor Red
    }
}
# 4. Export the final data to a CSV file
Write-Host ""
Write-Host "Exporting inventory to CSV..." -ForegroundColor Yellow
if ($ReportData.Count -gt 0) {
    $ReportData | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "✅ Export Complete! Total shares listed: $($ReportData.Count)" -ForegroundColor Green
    Write-Host "File saved at: $ExportPath" -ForegroundColor Cyan
} else {
    Write-Host "❌ No SMB file shares were found on the identified servers." -ForegroundColor Red
}
