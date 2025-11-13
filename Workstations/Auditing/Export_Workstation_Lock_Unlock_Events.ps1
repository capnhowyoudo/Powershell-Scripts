<#
.SYNOPSIS
Retrieves user workstation lock and unlock events from the Windows Security log and optionally exports them to CSV.

.DESCRIPTION
This script queries the Windows Security event log for event IDs 4800 (workstation locked) 
and 4801 (workstation unlocked). It selects and displays the following properties:
- TimeCreated: The timestamp of the event.
- Id: The event ID (4800 or 4801).
- EventType: A readable label indicating "Lock" or "Unlock".
- Message: The full event message describing the action.

The results are displayed in the console and can optionally be exported to a CSV file in C:\Temp.

This script is useful for auditing user activity, monitoring workstation security, 
or analyzing lock/unlock patterns on a system.

.NOTES
File Name   : Export_Workstation_Lock_Unlock_Events.ps1
Author      : capnhowyoudo
Date        : 2025-11-13
Requires    : PowerShell 3.0+
Usage       : 
    - Display events in console without exporting:
        .\Export_Workstation_Lock_Unlock_Events.ps1 -Export $false
    - Display events and export to CSV:
        .\Export_Workstation_Lock_Unlock_Events.ps1 -Export $true
Output File : C:\Temp\WorkstationLockEvents.csv
Limitations : Only retrieves events from the local machine. Remote queries require additional parameters.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [bool]$Export = $true
)

# Retrieve workstation lock/unlock events
$Events = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4800,4801} |
    Select-Object TimeCreated,
                  Id,
                  @{Name='EventType'; Expression={if ($_.Id -eq 4800) {'Lock'} else {'Unlock'}}},
                  Message

# Display in console
$Events | Format-Table -AutoSize

# Export to CSV if $Export is true
if ($Export) {
    $OutputPath = "C:\Temp\WorkstationLockEvents.csv"
    if (!(Test-Path (Split-Path $OutputPath))) {
        New-Item -ItemType Directory -Path (Split-Path $OutputPath) -Force | Out-Null
    }
    $Events | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "Events exported to $OutputPath" -ForegroundColor Green
}
