<#
.SYNOPSIS
    Gathers inventory of ALL servers in the domain (including DCs), including hosted printers.
.DESCRIPTION
    This script searches Active Directory for all enabled Windows Servers, 
    then connects to each one to list all shared printers and their IPv4 addresses.
.NOTES
    Requires the Active Directory and PrintManagement PowerShell modules.
    Must be run with a domain account that has read access to AD and local administrator access to the print servers.
#>

$ExportPath = "C:\Temp\FullPrintInventory.csv"
$ReportData = @()

# 1. Identify ALL Servers in Active Directory
Write-Host "Searching AD for ALL enabled servers (including DCs)..." -ForegroundColor Yellow

$Servers = Get-ADComputer -Filter {Enabled -eq $True} -Properties Name, OperatingSystem | 
           Where-Object { $_.OperatingSystem -like "*Windows Server*" } | 
           Select-Object -ExpandProperty Name

Write-Host "Found $($Servers.Count) servers. Starting inventory..." -ForegroundColor Yellow

# 2. Iterate through each server
foreach ($Server in $Servers) {
    Write-Host "Processing server: $($Server)" -NoNewline
    
    try {
        # Check if we are looking at the LOCAL machine
        if ($Server -eq $env:COMPUTERNAME) {
            Write-Host " (Local Host)" -ForegroundColor Cyan
            $Printers = Get-Printer | Where-Object { $_.Shared -eq $True }
            
            # Get Local IPv4 Address (Avoids ::1)
            $ServerIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*", "Wi-Fi*", "vEthernet*" | 
                         Where-Object { $_.IPAddress -notlike "169.*" } | 
                         Select-Object -First 1).IPAddress
        } else {
            Write-Host " (Remote)"
            $Printers = Get-Printer -ComputerName $Server -ErrorAction Stop | 
                        Where-Object { $_.Shared -eq $True }
            
            # Force Resolve to IPv4 for remote servers
            $ServerIP = (Resolve-DnsName -Name $Server -Type A -ErrorAction SilentlyContinue).IPAddress | Select-Object -First 1
        }
        
        if ($Printers) {
            Write-Host "    ✅ Found $($Printers.Count) shared printers." -ForegroundColor Green
            
            foreach ($Printer in $Printers) {
                $ReportData += [PSCustomObject]@{
                    PrintServerName = $Server
                    PrintServerIP   = if ($ServerIP) { $ServerIP } else { "Unknown" }
                    PrinterName     = $Printer.Name
                    PortName        = $Printer.PortName
                    DriverName      = $Printer.DriverName
                    Shared          = $Printer.Shared
                }
            }
        } else {
            Write-Host "    - No shared printers found." -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "    ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 3. Export
if ($ReportData.Count -gt 0) {
    if (!(Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" | Out-Null }
    $ReportData | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "`n✅ Export Complete! File saved at: $ExportPath" -ForegroundColor Green
} else {
    Write-Host "`n❌ Inventory empty. Ensure you are running as Administrator." -ForegroundColor Red
}
