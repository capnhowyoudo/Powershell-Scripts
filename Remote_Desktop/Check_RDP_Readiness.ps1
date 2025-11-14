<#
.SYNOPSIS
   Performs Remote Desktop (RDP) connectivity checks on one or more computers.

.DESCRIPTION
   This script checks DNS resolution, ping, RDP firewall port 3389, RDP services,
   RDP enable/disable status, and NLA configuration.
   Supports scanning one remote computer or multiple computers from a list file.
   Displays a color-coded summary table in the console and exports detailed results to CSV.

.NOTES
   Author: capnhowyoudo
   - Can be run as user, admin, or SYSTEM (RMM tools compatible)
   - Input list must contain one computer name per line
   - Exports full results to CSV in C:\Temp
   - Example text file format (computers.txt):

       PC01
       PC02
       Server01
       Server02
       Laptop-JSmith
       Laptop-ADoe

   - Usage with text file:
       .\Check_RDP_Readiness.ps1 -ComputerListPath "C:\Temp\computers.txt"
   - Usage with single computer:
       .\Check_RDP_Readiness.ps1 -SingleComputer PC01

.EXAMPLES
   # Scan a single computer (defaults to local computer)
   .\Check_RDP_Readiness.ps1

   # Scan a single remote computer
   .\Check_RDP_Readiness.ps1 -SingleComputer PC01

   # Scan multiple computers from a text file
   .\Check_RDP_Readiness.ps1 -ComputerListPath "C:\temp\computers.txt"
#>

[cmdletBinding()]
param(
    [string]$ComputerListPath,          # Path to text/CSV file with computer names
    [string]$SingleComputer = $env:COMPUTERNAME  # Used only if no list is supplied
)

# ----------------------------
# Set CSV output path
# ----------------------------
$OutputCSV = "C:\Temp\RDP_MultiCheck_Results.csv"

# Create folder if it does not exist
if (-not (Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" | Out-Null }

# ----------------------------
# Load list or single computer
# ----------------------------
if ($ComputerListPath) {
    if (-not (Test-Path $ComputerListPath)) {
        Write-Host "File not found: $ComputerListPath" -ForegroundColor Red
        exit
    }

    $Computers = Get-Content -Path $ComputerListPath | Where-Object { $_ -and $_.Trim() -ne "" }
}
else {
    $Computers = @($SingleComputer)
}

Write-Host "`nScanning $($Computers.Count) computer(s)...`n" -ForegroundColor Cyan

# Holds all results
$Results = @()

# Services to check
$RDPServices = @("TermService","UmRdpService")

# ----------------------------
# Start Scanning Each Computer
# ----------------------------
foreach ($Computer in $Computers) {

    Write-Host "Checking RDP Status on: $Computer" -ForegroundColor Green

    $Status = [ordered]@{
        Computer      = $Computer
        FQDN          = "Failed"
        Ping          = "Failed"
        RDPPort       = "Failed"
        RDPServices   = "Failed"
        RDPSettings   = "Disabled"
        RDPwithNLA    = "Enabled"
    }

    try {
        # DNS resolve
        try {
            $DNS = ([System.Net.Dns]::GetHostEntry($Computer)).HostName
            if ($DNS) {
                $Status["FQDN"] = "Ok"
                $Resolved = $DNS
            }
            else {
                $Resolved = $Computer
            }
        } catch {
            $Resolved = $Computer
        }

        # Ping
        if (Test-Connection -ComputerName $Resolved -Count 1 -Quiet) {

            $Status["Ping"] = "Ok"

            # Port check
            if (New-Object Net.Sockets.TcpClient($Resolved,3389)) {
                $Status["RDPPort"] = "Ok"
            }

            # RDP Services
            $Stopped = $RDPServices | ForEach-Object {
                Get-WmiObject Win32_Service -ComputerName $Resolved -Filter "Name = '$($_)' AND State = 'Stopped'"
            }

            if (-not $Stopped) {
                $Status["RDPServices"] = "Ok"
            }

            # RDP Enabled / Disabled
            $TS = Get-WmiObject -Class Win32_TerminalServiceSetting `
                    -Namespace root\CIMV2\TerminalServices `
                    -ComputerName $Resolved `
                    -Authentication 6

            if ($TS.AllowTSConnections -eq 1) {
                $Status["RDPSettings"] = "Enabled"
            }

            # NLA
            $TSGeneral = Get-WmiObject -class Win32_TSGeneralSetting `
                -Namespace root\cimv2\terminalservices `
                -ComputerName $Resolved `
                -Filter "TerminalName='RDP-tcp'" `
                -Authentication 6

            if ($TSGeneral.UserAuthenticationRequired -eq 0) {
                $Status["RDPwithNLA"] = "Disabled"
            }
        }
    }
    catch {
        Write-Host "Error scanning $Computer : $($_.Exception.Message)" -ForegroundColor Red
    }

    # Output detailed per-computer status
    foreach ($key in $Status.Keys) {
        Write-Host ("$($key): $($Status[$key])") -ForegroundColor Yellow
    }

    Write-Host "----------------------------------------`n"

    # Add to results array
    $Results += New-Object PSObject -Property $Status
}

# ----------------------------
# Export CSV to C:\Temp
# ----------------------------
$Results | Export-Csv -Path $OutputCSV -NoTypeInformation -Encoding UTF8
Write-Host "Results exported to: $OutputCSV" -ForegroundColor Cyan

# ----------------------------
# Summary Table
# ----------------------------
Write-Host "`nSUMMARY TABLE" -ForegroundColor Green
Write-Host ("Computer".PadRight(20) + "Ping".PadRight(10) + "RDPPort".PadRight(10) + "RDPServices".PadRight(15) + "RDPSettings".PadRight(12) + "NLA".PadRight(10))

foreach ($r in $Results) {
    $pingColor = if ($r.Ping -eq "Ok") { "Green" } else { "Red" }
    $portColor = if ($r.RDPPort -eq "Ok") { "Green" } else { "Red" }
    $serviceColor = if ($r.RDPServices -eq "Ok") { "Green" } else { "Red" }
    $settingColor = if ($r.RDPSettings -eq "Enabled") { "Green" } else { "Red" }
    $nlaColor = if ($r.RDPwithNLA -eq "Enabled") { "Green" } else { "Yellow" }

    Write-Host ($r.Computer.PadRight(20)) -NoNewline
    Write-Host ($r.Ping.PadRight(10)) -ForegroundColor $pingColor -NoNewline
    Write-Host ($r.RDPPort.PadRight(10)) -ForegroundColor $portColor -NoNewline
    Write-Host ($r.RDPServices.PadRight(15)) -ForegroundColor $serviceColor -NoNewline
    Write-Host ($r.RDPSettings.PadRight(12)) -ForegroundColor $settingColor -NoNewline
    Write-Host ($r.RDPwithNLA.PadRight(10)) -ForegroundColor $nlaColor
}
