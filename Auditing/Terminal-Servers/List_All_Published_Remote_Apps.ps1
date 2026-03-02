<#
.SYNOPSIS
    Gathers a domain-wide inventory of all published RemoteApps across all Windows Servers.

.DESCRIPTION
    This script performs the following actions:
    1. Queries Active Directory for all enabled computer objects running a Windows Server OS.
    2. Includes Domain Controllers and the local host in the search.
    3. Pings each server to verify connectivity before attempting a connection.
    4. Uses Invoke-Command to remotely query the RDS Publishing registry keys.
    5. Collects the App Name, Alias, Executable Path, and Command Line Arguments.
    6. Exports the gathered data to a CSV file and displays a sortable grid view.

.NOTES
    - Requirements: Active Directory PowerShell module.
    - Permissions: Must be run as a Domain Administrator or with equivalent "Remote Management" rights.
    - Network: WinRM (Windows Remote Management) must be enabled on target servers.
    - Output: Default save location is C:\Temp\RemoteAppInventory.csv.
#>

# Define the output path
$ExportPath = "C:\Temp\RemoteAppInventory.csv"
$ReportData = @()

# 1. Identify ALL Servers in Active Directory
Write-Host "Searching AD for all enabled servers (including DCs)..." -ForegroundColor Yellow
$Servers = Get-ADComputer -Filter {Enabled -eq $True} -Properties Name, OperatingSystem | 
           Where-Object { $_.OperatingSystem -like "*Windows Server*" } | 
           Select-Object -ExpandProperty Name

Write-Host "Found $($Servers.Count) servers. Checking for RemoteApp configurations..." -ForegroundColor Yellow

# 2. Iterate through each server
foreach ($Server in $Servers) {
    Write-Host "Checking: $Server " -NoNewline
    
    # Quick Ping check to avoid long timeouts
    if (Test-Connection -ComputerName $Server -Count 1 -Quiet) {
        
        try {
            # Remote registry query for published apps
            $Apps = Invoke-Command -ComputerName $Server -ErrorAction Stop -ScriptBlock {
                $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\CentralPublishing\Config\PublicShellApps"
                if (Test-Path $RegPath) {
                    Get-ChildItem $RegPath | ForEach-Object {
                        [PSCustomObject]@{
                            AppName     = $_.GetValue("Name")
                            Alias       = $_.PSChildName
                            FilePath    = $_.GetValue("IconPath")
                            CommandLine = $_.GetValue("CommandLine")
                        }
                    }
                }
            }

            if ($Apps) {
                Write-Host "-> ✅ Found $($Apps.Count) RemoteApps" -ForegroundColor Green
                foreach ($App in $Apps) {
                    $ReportData += [PSCustomObject]@{
                        ServerName  = $Server
                        AppName     = $App.AppName
                        Alias       = $App.Alias
                        Executable  = $App.FilePath
                        Arguments   = $App.CommandLine
                        Timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm"
                    }
                }
            } else {
                Write-Host "-> (No RemoteApps)" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Host "-> ❌ Connection Error" -ForegroundColor Red
        }
    } else {
        Write-Host "-> ⚠️ Offline (Skipped)" -ForegroundColor Yellow
    }
}

# 3. Export and Display Results
if ($ReportData.Count -gt 0) {
    if (!(Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" | Out-Null }
    
    $ReportData | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "`n✅ Inventory complete! Saved to: $ExportPath" -ForegroundColor Green
    
    # Show the results in a pop-up window for immediate review
    $ReportData | Out-GridView -Title "Domain-Wide RemoteApp Inventory"
} else {
    Write-Host "`n❌ No RemoteApps were found on any reachable servers." -ForegroundColor Red
}
