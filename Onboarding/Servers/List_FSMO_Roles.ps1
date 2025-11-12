<#
Description
This PowerShell script is used to identify which domain controllers hold the FSMO (Flexible Single Master Operations) roles in an Active Directory environment.
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
