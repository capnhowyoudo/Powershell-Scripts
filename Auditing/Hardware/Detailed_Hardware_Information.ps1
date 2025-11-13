<#
.SYNOPSIS
    Generates detailed hardware information reports (TXT + HTML) for a Windows server.
.DESCRIPTION
    Collects CPU, Memory, Disk, BIOS, Motherboard, Network, GPU, and OS details.
    Exports both a fully detailed text file and an HTML report to C:\Temp.
#>

# === Output Setup ===
$timestamp     = Get-Date -Format "yyyyMMdd_HHmmss"
$computerName  = $env:COMPUTERNAME
$OutputDir     = "C:\Temp"
$TxtReportPath = "$OutputDir\HardwareReport_${computerName}_$timestamp.txt"
$HtmlReportPath = "$OutputDir\HardwareReport_${computerName}_$timestamp.html"

if (!(Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory | Out-Null
}

# === Helper: Convert objects to TXT ===
function Append-Section {
    param($Title, $Data, [ref]$TextArray)
    $TextArray.Value += "`n" + ("#" * 80)
    $TextArray.Value += ("# " + $Title.ToUpper())
    $TextArray.Value += ("#" * 80)

    if ($null -eq $Data -or $Data.Count -eq 0) {
        $TextArray.Value += "No data found."
        return
    }

    foreach ($item in $Data) {
        foreach ($prop in $item.PSObject.Properties) {
            $value = $prop.Value
            # Handle arrays (like IP addresses, DNS)
            if ($value -is [System.Array]) { $value = $value -join ", " }
            $TextArray.Value += "{0,-25}: {1}" -f $prop.Name, $value
        }
        $TextArray.Value += ""  # blank line between objects
    }
}

# === Helper: Convert to HTML table ===
function Convert-ToHtmlTable {
    param([Parameter(Mandatory)][object]$Data, [string]$Title)
    if ($null -eq $Data) { return "<h3>$Title</h3><p><i>No data found.</i></p>" }
    $table = $Data | ConvertTo-Html -Fragment -PreContent "<h3>$Title</h3>"
    return $table
}

# === Data Collection ===
$CPUInfo = Get-CimInstance Win32_Processor | Select `
    Name, Manufacturer, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed

$MemoryInfo = Get-CimInstance Win32_PhysicalMemory | Select `
    Manufacturer, PartNumber,
    @{Name="Capacity(GB)";Expression={[math]::Round($_.Capacity / 1GB,2)}},
    Speed, DeviceLocator

$totalMem = [math]::Round(($MemoryInfo | Measure-Object -Property 'Capacity(GB)' -Sum).Sum, 2)

$DiskInfo = Get-CimInstance Win32_DiskDrive | Select `
    Model, InterfaceType, MediaType, SerialNumber,
    @{Name="Size(GB)";Expression={[math]::Round($_.Size / 1GB,2)}}

$LogicalDisks = Get-CimInstance Win32_LogicalDisk | Where-Object {$_.DriveType -eq 3} | Select `
    DeviceID, VolumeName, FileSystem,
    @{Name="Size(GB)";Expression={[math]::Round($_.Size / 1GB,2)}},
    @{Name="FreeSpace(GB)";Expression={[math]::Round($_.FreeSpace / 1GB,2)}}

$Motherboard = Get-CimInstance Win32_BaseBoard | Select Manufacturer, Product, SerialNumber

$BIOS = Get-CimInstance Win32_BIOS | Select Manufacturer, SMBIOSBIOSVersion, ReleaseDate, SerialNumber

$Network = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" | Select `
    Description, MACAddress,
    @{Name="IPv4";Expression={$_.IPAddress -join ', '}},
    @{Name="Gateway";Expression={$_.DefaultIPGateway -join ', '}},
    @{Name="DNS Servers";Expression={$_.DNSServerSearchOrder -join ', '}}

$GPU = Get-CimInstance Win32_VideoController | Select `
    Name,
    @{Name="VRAM(GB)";Expression={[math]::Round($_.AdapterRAM / 1GB,2)}},
    DriverVersion, VideoProcessor,
    @{Name="Resolution";Expression={"$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"}}

$OS = Get-CimInstance Win32_OperatingSystem | Select `
    Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime, SerialNumber, RegisteredUser

# === TEXT REPORT ===
$TextReport = @()
$TextReport += ("=" * 80)
$TextReport += "HARDWARE INVENTORY REPORT"
$TextReport += "Server Name : $computerName"
$TextReport += "Generated   : $(Get-Date)"
$TextReport += ("=" * 80)

Append-Section "CPU Information" $CPUInfo ([ref]$TextReport)
$TextReport += "`nTotal Installed Memory : $totalMem GB"
Append-Section "Memory (RAM) Information" $MemoryInfo ([ref]$TextReport)
Append-Section "Physical Disk Information" $DiskInfo ([ref]$TextReport)
Append-Section "Logical Volumes" $LogicalDisks ([ref]$TextReport)
Append-Section "Motherboard Information" $Motherboard ([ref]$TextReport)
Append-Section "BIOS Information" $BIOS ([ref]$TextReport)
Append-Section "Network Adapter Information" $Network ([ref]$TextReport)
Append-Section "GPU Information" $GPU ([ref]$TextReport)
Append-Section "Operating System Information" $OS ([ref]$TextReport)

$TextReport += "`n" + ("=" * 80)
$TextReport += "Hardware information collection completed successfully."
$TextReport += ("=" * 80)

$TextReport | Out-File -FilePath $TxtReportPath -Encoding UTF8

# === HTML REPORT ===
$HTMLHeader = @"
<html>
<head>
<title>Hardware Report - $computerName</title>
<style>
    body { font-family: Segoe UI, sans-serif; margin: 30px; background-color: #f8f9fa; color: #333; }
    h1 { color: #0d6efd; border-bottom: 3px solid #0d6efd; padding-bottom: 5px; }
    h3 { color: #212529; margin-top: 20px; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 25px; }
    th, td { border: 1px solid #dee2e6; padding: 8px; text-align: left; }
    th { background-color: #e9ecef; }
    tr:nth-child(even) { background-color: #f8f9fa; }
    .footer { text-align: center; font-size: 12px; color: #6c757d; margin-top: 40px; }
</style>
</head>
<body>
<h1>Hardware Inventory Report</h1>
<p><b>Server Name:</b> $computerName<br>
<b>Generated On:</b> $(Get-Date)</p>
"@

$HTMLBody = @(
    Convert-ToHtmlTable -Data $CPUInfo -Title "CPU Information"
    "<h3>Total Installed Memory: $totalMem GB</h3>"
    Convert-ToHtmlTable -Data $MemoryInfo -Title "Memory (RAM) Information"
    Convert-ToHtmlTable -Data $DiskInfo -Title "Physical Disk Information"
    Convert-ToHtmlTable -Data $LogicalDisks -Title "Logical Volumes"
    Convert-ToHtmlTable -Data $Motherboard -Title "Motherboard Information"
    Convert-ToHtmlTable -Data $BIOS -Title "BIOS Information"
    Convert-ToHtmlTable -Data $Network -Title "Network Adapter Information"
    Convert-ToHtmlTable -Data $GPU -Title "GPU Information"
    Convert-ToHtmlTable -Data $OS -Title "Operating System Information"
) -join "`n"

$HTMLFooter = @"
<div class='footer'>
<hr>
<p>Hardware information collection completed successfully.<br>
Generated by PowerShell on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
</div>
</body></html>
"@

$FullHTML = $HTMLHeader + $HTMLBody + $HTMLFooter
$FullHTML | Out-File -FilePath $HtmlReportPath -Encoding UTF8

# === Done ===
Write-Host "`nReports generated successfully!" -ForegroundColor Green
Write-Host "Text Report : $TxtReportPath" -ForegroundColor Yellow
Write-Host "HTML Report : $HtmlReportPath" -ForegroundColor Cyan
Start-Process $HtmlReportPath
