<#
.SYNOPSIS
    MASTER GPO PRINTER INVENTORY

.DESCRIPTION
    Gathers printer configurations from all Group Policy Objects in the domain
    using three discovery methods:
        1. Group Policy Preferences (Printers.xml in SYSVOL)
        2. Printer Connection Policies stored in Active Directory (msPrint-ConnectionPolicy)
        3. Legacy Deployed Printers identified via GPO XML Report parsing

    The script compiles all discovered printer paths into a consolidated
    CSV report for auditing and documentation purposes.

.NOTES
    Requirements:
        - RSAT Group Policy module
        - RSAT ActiveDirectory module
        - Domain permissions sufficient to read GPOs and AD objects

    Output:
        C:\Temp\GPO_Master_Printers_Report.csv

    Ensure the C:\Temp directory exists or allow the script to create it.
#>

<#
.SYNOPSIS
    MASTER GPO PRINTER INVENTORY
    Gathers printers from GPP (XML), Deployed Printers (GPO Report), 
    and msPrint-ConnectionPolicy (AD Objects).
#>

# Define the output path
$ExportPath = "C:\Temp\GPO_Master_Printers_Report.csv"
$ReportData = @()

# 1. Load Modules
try {
    Import-Module GroupPolicy, ActiveDirectory -ErrorAction Stop
    Write-Host "✅ Modules loaded." -ForegroundColor Green
} catch {
    Write-Error "❌ Ensure RSAT (Group Policy & AD) is installed."
    exit 1
}

# 2. Setup AD Info
$DomainDN = (Get-ADDomain).DistinguishedName
$GPOs = Get-GPO -All | Sort-Object DisplayName

Write-Host "Searching $($GPOs.Count) GPOs using 3 different discovery methods..." -ForegroundColor Yellow

foreach ($Policy in $GPOs) {
    $GPOID = $Policy.Id
    $GPODom = $Policy.DomainName
    $GPODisp = $Policy.DisplayName
    Write-Host "-> Processing: $($GPODisp)" -ForegroundColor Cyan

    # --- METHOD 1: GPP Preferences (XML Files in SYSVOL) ---
    $ConfigTypes = @("User", "Machine")
    foreach ($Type in $ConfigTypes) {
        $XMLPath = "\\$($GPODom)\SYSVOL\$($GPODom)\Policies\{$($GPOID)}\$($Type)\Preferences\Printers\Printers.xml"
        if (Test-Path $XMLPath) {
            try {
                [xml]$PrintXML = Get-Content $XMLPath
                $Printers = $PrintXML.Printers.ChildNodes | Where-Object { $_.Name -in @("SharedPrinter", "IPPrinter", "LocalPrinter") }
                foreach ($P in $Printers) {
                    $ReportData += [PSCustomObject]@{
                        GPOName     = $GPODisp
                        Method      = "GPP Preference ($($P.Name))"
                        PrinterPath = if ($P.Name -eq "IPPrinter") { $P.Properties.ipAddress } else { $P.Properties.Path }
                        Type        = $Type
                    }
                }
            } catch {}
        }
    }

    # --- METHOD 2: Printer Connections (AD Objects / Print Management) ---
    $SearchBase = "CN={$GPOID},CN=Policies,CN=System,$DomainDN"
    try {
        $ADObjects = Get-ADObject -SearchBase $SearchBase -Filter {objectClass -eq "msPrint-ConnectionPolicy"} -Properties uNCName
        foreach ($Obj in $ADObjects) {
            $ReportData += [PSCustomObject]@{
                GPOName     = $GPODisp
                Method      = "Printer Connection (Print Management)"
                PrinterPath = $Obj.uNCName
                Type        = "User/Machine"
            }
        }
    } catch {}

    # --- METHOD 3: Legacy Deployed Printers (GPO XML Report) ---
    try {
        $GPOReport = [xml](Get-GPOReport -Id $GPOID -ReportType xml -ErrorAction SilentlyContinue)
        $NS = @{ gpo = "http://www.microsoft.com/GroupPolicy/Settings" }
        $Deployed = Select-Xml -Xml $GPOReport -XPath "//gpo:ExtensionData[gpo:Extension/gpo:Name='Microsoft.GroupPolicy.Settings.PrintManagement']" -Namespace $NS
        foreach ($Node in $Deployed) {
            $Path = $Node.Node.Extension.Custom.printerConnection.path
            if ($Path) {
                $ReportData += [PSCustomObject]@{
                    GPOName     = $GPODisp
                    Method      = "Deployed Printer (Legacy)"
                    PrinterPath = $Path
                    Type        = "Report-Based"
                }
            }
        }
    } catch {}
}

# 4. Final Export
if ($ReportData.Count -gt 0) {
    if (!(Test-Path "C:\Temp")) { New-Item -Path "C:\Temp" -ItemType Directory }
    $ReportData | Sort-Object GPOName | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "`n✅ Success! Found $($ReportData.Count) printers across all methods." -ForegroundColor Green
    Write-Host "File saved to: $ExportPath" -ForegroundColor Cyan
} else {
    Write-Host "`n❌ No printers found. Check your permissions or verify the GPO settings." -ForegroundColor Red
}
