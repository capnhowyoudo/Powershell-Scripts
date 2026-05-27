<#
.SYNOPSIS
    Exports all BitLocker recovery keys from Active Directory to a CSV file.

.DESCRIPTION
    Queries Active Directory for all BitLocker recovery objects (msFVE-RecoveryInformation)
    stored under computer accounts. Extracts the computer name, recovery key ID, recovery
    password, and date the key was backed up. Exports results to a CSV file.

.NOTES
    Requires     : PowerShell 5.0+
                   Active Directory PowerShell Module (RSAT)
                   Must be run as a Domain Admin or delegated AD read permissions
                   on the msFVE-RecoveryInformation objects

.EXAMPLE
    .\Export-BitLockerKeysFromAD.ps1
#>

# -- Prerequisites ------------------------------------------------------------
Import-Module ActiveDirectory

# -- Config -------------------------------------------------------------------
$OutputPath = "C:\Temp\BitLockerKeys.csv"

# Create C:\Temp if it doesn't exist
if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" | Out-Null
    Write-Host "Created directory C:\Temp"
}

# -- Query AD for all BitLocker recovery objects ------------------------------
$RecoveryObjects = Get-ADObject -Filter 'objectClass -eq "msFVE-RecoveryInformation"' `
                    -Properties `
                        msFVE-RecoveryPassword, `
                        msFVE-RecoveryGuid, `
                        whenCreated, `
                        DistinguishedName

# -- Parse and build output ---------------------------------------------------
$Results = foreach ($Obj in $RecoveryObjects) {

    # Extract computer name from the DistinguishedName
    # DN format: CN=<date>{GUID},CN=<ComputerName>,OU=...
    $ComputerName = ($Obj.DistinguishedName -split ',')[1] -replace 'CN=', ''

    [PSCustomObject]@{
        ComputerName      = $ComputerName
        RecoveryKeyId     = [System.BitConverter]::ToString($Obj.'msFVE-RecoveryGuid') -replace '-', ''
        RecoveryPassword  = $Obj.'msFVE-RecoveryPassword'
        DateBackedUp      = $Obj.whenCreated
        DistinguishedName = $Obj.DistinguishedName
    }
}

# -- Export to CSV ------------------------------------------------------------
$Results | Sort-Object ComputerName | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Export complete. $($Results.Count) keys saved to $OutputPath"
