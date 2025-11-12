# Script to find all Domain Controllers and export to CSV
# Run this from a server or workstation with the Active Directory PowerShell module installed.

$ExportPath = "C:\Temp\DomainControllers_Report.csv"

# 1. Get all Domain Controller objects (-Filter *)
# 2. Select the specific properties you want to include in the CSV
# 3. Export the results to the specified CSV file
Get-ADDomainController -Filter * | 
    Select-Object Name, HostName, IPv4Address, Domain, Site, OperatingSystem, IsGlobalCatalog, OperationMasterRoles | 
    Export-Csv -Path $ExportPath -NoTypeInformation

Write-Host "Successfully exported Domain Controller list to: $ExportPath"

# Optional: Display the contents of the CSV file in the console
# Get-Content $ExportPath | Format-Table -Wrap
