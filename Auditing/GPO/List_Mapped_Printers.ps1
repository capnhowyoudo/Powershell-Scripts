<#
.SYNOPSIS
    Gathers a list of all printers deployed via Group Policy Objects (GPO)
    using both Group Policy Preferences (GPP) and Deployed Printers.
.DESCRIPTION
    The script iterates through every GPO in the domain, searches the SYSVOL
    for the printer preference XML files, and also checks the GPO report XML
    for 'Deployed Printers' configuration.
.NOTES
    - Requires the GroupPolicy PowerShell module.
    - Must be run on a domain-joined machine with the Group Policy Management
      Tools (RSAT) installed, and with permissions to read all GPOs.
#>

# Define the output path for the CSV report
$ExportPath = "C:\Temp\GPO_Mapped_Printers_Report.csv"

# Array to store all the collected printer data
$ReportData = @()

# 1. Import the required module
try {
    Import-Module GroupPolicy -ErrorAction Stop
    Write-Host "✅ GroupPolicy module loaded." -ForegroundColor Green
} catch {
    Write-Error "❌ Error: GroupPolicy module is not installed or accessible. Aborting."
    exit 1
}

# 2. Get all GPOs in the domain
Write-Host "Searching for all Group Policy Objects..." -ForegroundColor Yellow
$GPOs = Get-GPO -All | Sort-Object DisplayName

Write-Host "Found $($GPOs.Count) GPOs. Starting printer extraction..." -ForegroundColor Yellow

# 3. Iterate through each GPO to find printer mappings
foreach ($Policy in $GPOs) {
    $GPOID = $Policy.Id
    $GPODom = $Policy.DomainName
    $GPODisp = $Policy.DisplayName
    
    Write-Host "-> Processing GPO: $($GPODisp)" -ForegroundColor Cyan
    
    # --- A. Check for Group Policy Preferences (GPP) Printers ---
    # GPP printers are stored in an XML file within the SYSVOL structure.
    $PrefPath = "\\$($GPODom)\SYSVOL\$($GPODom)\Policies\{$($GPOID)}\User\Preferences"
    $XMLPath = "$PrefPath\Printers\Printers.xml"
    
    if (Test-Path $XMLPath) {
        try {
            [xml]$PrintXML = Get-Content $XMLPath -ErrorAction Stop
            
            # Check for <SharedPrinter> nodes
            if ($PrintXML.Printers.SharedPrinter) {
                $SharedPrinters = @($PrintXML.Printers.SharedPrinter) # Ensure it's an array
                Write-Host "    Found $($SharedPrinters.Count) GPP Shared Printers." -ForegroundColor DarkGreen
                
                foreach ($Printer in $SharedPrinters) {
                    $ReportEntry = [PSCustomObject]@{
                        GPOName         = $GPODisp
                        GPOType         = "GPO Preferences (Shared Printer)"
                        PrinterPath     = $Printer.Properties.Path
                        Action          = $Printer.Properties.action.Replace("U", "Update").Replace("C", "Create").Replace("D", "Delete").Replace("R", "Replace")
                        IsDefault       = $Printer.Properties.default.Replace("0", "False").Replace("1", "True")
                        ItemLevelTargeting = if ($Printer.Filters.FilterGroup.Name) { $Printer.Filters.FilterGroup.Name } else { "None" }
                    }
                    $ReportData += $ReportEntry
                }
            }
        }
        catch {
            Write-Host "    ❌ Error reading GPP XML for $($GPODisp): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # --- B. Check for GPO Deployed Printers (Old Method) ---
    # Deployed Printers are found by generating an XML report of the GPO.
    try {
        $GPOReport = Get-GPOReport -Id $GPOID -ReportType xml -ErrorAction Stop
        
        # Look for the 'printerConnection' extension in User and Computer sections
        $UserConnections = $GPOReport.DocumentElement.User.ExtensionData.extension | Where-Object { $_.name -eq "Microsoft.GroupPolicy.Settings.PrintManagement" }
        $ComputerConnections = $GPOReport.DocumentElement.Computer.ExtensionData.extension | Where-Object { $_.name -eq "Microsoft.GroupPolicy.Settings.PrintManagement" }

        # User Configuration Deployed Printers
        foreach ($Conn in $UserConnections) {
            if ($Conn.printerConnection.path) {
                $ReportEntry = [PSCustomObject]@{
                    GPOName         = $GPODisp
                    GPOType         = "GPO Deployed Printer (User Config)"
                    PrinterPath     = $Conn.printerConnection.path
                    Action          = "Create"
                    IsDefault       = "N/A"
                    ItemLevelTargeting = "N/A"
                }
                $ReportData += $ReportEntry
            }
        }
        
        # Computer Configuration Deployed Printers
        foreach ($Conn in $ComputerConnections) {
            if ($Conn.printerConnection.path) {
                $ReportEntry = [PSCustomObject]@{
                    GPOName         = $GPODisp
                    GPOType         = "GPO Deployed Printer (Computer Config)"
                    PrinterPath     = $Conn.printerConnection.path
                    Action          = "Create"
                    IsDefault       = "N/A"
                    ItemLevelTargeting = "N/A"
                }
                $ReportData += $ReportEntry
            }
        }

    }
    catch {
        Write-Host "    ❌ Error generating XML report for $($GPODisp): $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 4. Export the final data to a CSV file
Write-Host ""
Write-Host "Exporting inventory to CSV..." -ForegroundColor Yellow

if ($ReportData.Count -gt 0) {
    # Sort data for better readability
    $ReportData | Sort-Object GPOName, PrinterPath | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "✅ Export Complete! Total GPO printers listed: $($ReportData.Count)" -ForegroundColor Green
    Write-Host "File saved at: $ExportPath" -ForegroundColor Cyan
} else {
    Write-Host "❌ No GPO mapped printers were found in the domain." -ForegroundColor Red
}
