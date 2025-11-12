<#
.SYNOPSIS
    Gathers an inventory of all file servers and their configured SMB shares in the domain.
.DESCRIPTION
    This script searches Active Directory for server operating systems, then connects
    to each one to list all SMB shares, excluding default administrative shares.
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

Write-Host "Found $($Servers.Count) servers to check. Starting share enumeration..." -ForegroundColor Yellow

# 3. Iterate through each server to list SMB shares
foreach ($Server in $Servers) {
    Write-Host "Processing server: $($Server)" -ForegroundColor Cyan
    
    try {
        # Use Get-CimInstance to query the Win32_Share class remotely
        $Shares = Get-CimInstance -ClassName Win32_Share -ComputerName $Server -ErrorAction Stop |
                  Where-Object { 
                      # Exclude default administrative shares (like C$, IPC$, ADMIN$)
                      $_.Name -notlike "*$" 
                  }
        
        # If shares are found, process the details
        if ($Shares) {
            Write-Host "    ✅ Found $($Shares.Count) user-defined shares." -ForegroundColor DarkGreen
            
            # Get the IP address of the file server (for reference)
            $ServerIP = (Resolve-DnsName -Name $Server -ErrorAction SilentlyContinue).IPAddress | Select-Object -First 1
            
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
            Write-Host "    - No user-defined shares found. Skipping." -ForegroundColor DarkGray
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
    Write-Host "❌ No user-defined SMB shares were found on the identified servers." -ForegroundColor Red
}
