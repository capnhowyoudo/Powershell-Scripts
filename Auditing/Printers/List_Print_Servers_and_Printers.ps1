<#
.SYNOPSIS
    Gathers inventory of all Print Servers in the domain, including their hosted printers and IP addresses.
.DESCRIPTION
    This script searches Active Directory for servers that may host the Print Server role,
    then connects to each one to list all shared printers, their names, and IP addresses.
.NOTES
    Requires the Active Directory and PrintManagement PowerShell modules.
    Must be run with a domain account that has read access to AD and local administrator access to the print servers.
#>

# Define the output path for the CSV report
$ExportPath = "C:\Temp\PrintServerInventory.csv"

# Array to store all the collected printer data
$ReportData = @()

# 1. Identify potential Print Servers in Active Directory
Write-Host "Searching Active Directory for potential Print Servers..." -ForegroundColor Yellow

# Get a list of all enabled servers (excluding domain controllers)
$Servers = Get-ADComputer -Filter {Enabled -eq $True -and OperatingSystem -Like "Windows Server*"} -Properties Name | 
            Where-Object { $_.Name -notlike "*DC*" } | 
            Select-Object -ExpandProperty Name

Write-Host "Found $($Servers.Count) servers to check. Starting inventory..." -ForegroundColor Yellow

# 2. Iterate through each server to check for printers
foreach ($Server in $Servers) {
    Write-Host "Processing server: $($Server)"
    
    try {
        # Check if the Print Server role is active and get local printers
        # -ComputerName is used for remote connection
        $Printers = Get-Printer -ComputerName $Server -ErrorAction Stop | 
                    Where-Object { $_.Shared -eq $True }
        
        # If printers are found, process the details
        if ($Printers) {
            Write-Host "    ✅ Found $($Printers.Count) shared printers." -ForegroundColor Green
            
            foreach ($Printer in $Printers) {
                # Get the IP address of the print server
                $ServerIP = (Resolve-DnsName -Name $Server -ErrorAction SilentlyContinue).IPAddress | Select-Object -First 1
                
                # Create a custom object with the desired properties
                $ReportEntry = [PSCustomObject]@{
                    PrintServerName = $Server
                    PrintServerIP   = $ServerIP
                    PrinterName     = $Printer.Name
                    PortName        = $Printer.PortName
                    DriverName      = $Printer.DriverName
                    Shared          = $Printer.Shared
                }
                
                # Add the entry to the report array
                $ReportData += $ReportEntry
            }
        }
        else {
            Write-Host "    - No shared printers found. Skipping." -ForegroundColor DarkGray
        }

    }
    catch {
        Write-Host "    ❌ Error connecting to $($Server) or enumerating printers: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 3. Export the final data to a CSV file
Write-Host ""
Write-Host "Exporting inventory to CSV..." -ForegroundColor Yellow

if ($ReportData.Count -gt 0) {
    $ReportData | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "✅ Export Complete! Total printers listed: $($ReportData.Count)" -ForegroundColor Green
    Write-Host "File saved at: $ExportPath" -ForegroundColor Cyan
} else {
    Write-Host "❌ No shared printers were found in the domain." -ForegroundColor Red
}
