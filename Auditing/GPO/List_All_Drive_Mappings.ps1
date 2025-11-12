<#
.SYNOPSIS
    Gathers a list of all mapped drives deployed via Group Policy Preferences (GPP).
.DESCRIPTION
    This script iterates through every GPO in the domain, searches the SYSVOL for the
    Drive Mappings Preferences XML file, and extracts the drive letter and share path.
.NOTES
    - Requires the GroupPolicy PowerShell module (RSAT).
    - Must be run on a domain-joined machine with the Group Policy Management
      Tools installed, and with permissions to read all GPOs and the SYSVOL share.
#>

# Define the output path for the CSV report
$ExportPath = "C:\Temp\GPO_DriveMappings_Report.csv"

# Array to store all the collected drive mapping data
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

Write-Host "Found $($GPOs.Count) GPOs. Starting drive mapping extraction..." -ForegroundColor Yellow

# 3. Iterate through each GPO to find drive mappings
foreach ($Policy in $GPOs) {
    $GPOID = $Policy.Id
    $GPODom = $Policy.DomainName
    $GPODisp = $Policy.DisplayName
    
    Write-Host "-> Processing GPO: $($GPODisp)" -ForegroundColor Cyan
    
    # GPP drive mappings are stored in an XML file within the SYSVOL structure.
    # The path is: \\Domain\SYSVOL\Domain\Policies\{GPO_ID}\User\Preferences\Drives\Drives.xml
    $PrefPath = "\\$($GPODom)\SYSVOL\$($GPODom)\Policies\{$($GPOID)}\User\Preferences"
    $XMLPath = "$PrefPath\Drives\Drives.xml"
    
    if (Test-Path $XMLPath) {
        try {
            # Read the XML content
            [xml]$DriveXML = Get-Content $XMLPath -ErrorAction Stop
            
            # Check for <Drive> nodes (which define drive mappings)
            if ($DriveXML.Drives.Drive) {
                # Ensure it is treated as an array, even if only one mapping exists
                $DriveMappings = @($DriveXML.Drives.Drive)
                Write-Host "    Found $($DriveMappings.Count) GPP Drive Mappings." -ForegroundColor DarkGreen
                
                foreach ($Mapping in $DriveMappings) {
                    $Properties = $Mapping.Properties
                    
                    # Create a custom object with the desired properties
                    $ReportEntry = [PSCustomObject]@{
                        GPOName         = $GPODisp
                        DriveLetter     = $Properties.Letter
                        UNCPath         = $Properties.Path
                        Action          = $Properties.Action.Replace("U", "Update").Replace("C", "Create").Replace("R", "Replace").Replace("D", "Delete")
                        Label           = $Properties.Label
                        Reconnect       = if ($Properties.Permanent -eq 1) { "True" } else { "False" }
                        ItemLevelTargeting = if ($Mapping.Filters.FilterGroup.Name) { $Mapping.Filters.FilterGroup.Name } else { "None" }
                    }
                    
                    $ReportData += $ReportEntry
                }
            }
        }
        catch {
            Write-Host "    ❌ Error reading GPP XML for $($GPODisp): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "    - No Drive Mappings XML found. Skipping." -ForegroundColor DarkGray
    }
}

# 4. Export the final data to a CSV file
Write-Host ""
Write-Host "Exporting inventory to CSV..." -ForegroundColor Yellow

if ($ReportData.Count -gt 0) {
    # Sort data for better readability
    $ReportData | Sort-Object GPOName, DriveLetter | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "✅ Export Complete! Total drive mappings listed: $($ReportData.Count)" -ForegroundColor Green
    Write-Host "File saved at: $ExportPath" -ForegroundColor Cyan
} else {
    Write-Host "❌ No GPO mapped drives were found in the domain." -ForegroundColor Red
}
