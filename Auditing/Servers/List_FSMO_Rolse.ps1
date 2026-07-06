<#
This PowerShell script is used to identify and display which domain controllers hold the five FSMO (Flexible Single Master Operations) roles in an Active Directory (AD) environment.
#>
# Requires the ActiveDirectory module to be installed (part of RSAT/on Domain Controllers)

# Get Forest-Wide Roles (Schema Master, Domain Naming Master)
$ForestRoles = Get-ADForest | Select-Object SchemaMaster, DomainNamingMaster

# Get Domain-Wide Roles (PDC Emulator, RID Master, Infrastructure Master)
$DomainRoles = Get-ADDomain | Select-Object PDCEmulator, RIDMaster, InfrastructureMaster

# Create a custom object for a clean display
$AllFSMO = [PSCustomObject]@{
    'Schema Master'          = $ForestRoles.SchemaMaster
    'Domain Naming Master'   = $ForestRoles.DomainNamingMaster
    'PDC Emulator'           = $DomainRoles.PDCEmulator
    'RID Master'             = $DomainRoles.RIDMaster
    'Infrastructure Master'  = $DomainRoles.InfrastructureMaster
}

# Display the results
$AllFSMO | Format-List

# Ensure the output directory exists
$OutputPath = "C:\temp"
if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Export to CSV
$CsvFile = Join-Path $OutputPath "FSMORoles_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$AllFSMO | Export-Csv -Path $CsvFile -NoTypeInformation

Write-Host "FSMO role report exported to: $CsvFile" -ForegroundColor Green
