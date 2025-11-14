<#
.SYNOPSIS
    Checks the status of the Windows Mobile Hotspot and enables it if it is turned off.

.DESCRIPTION
    This script uses Windows Runtime (WinRT) APIs to manage the Mobile Hotspot (Internet Connection Sharing) on a Windows machine.
    - First, it checks the current Internet connection profile.
    - Then it creates a NetworkOperatorTetheringManager object from the connection profile.
    - If the hotspot is already on, it reports that status.
    - If the hotspot is off, it starts the hotspot asynchronously and waits for it to complete.
    - Helper functions are included to handle asynchronous WinRT operations synchronously in PowerShell.

.NOTES
    - Requires PowerShell 5.1+ (for Add-Type and WinRT integration)
    - Must be run on a machine that supports Windows Mobile Hotspot
    - The script does not require administrative privileges but may require them depending on system policies
    - No logging is built-in; you can wrap outputs in Write-Host or export to a file if needed
    - Example usage:
        1. Save as Enable_Hotspot.ps1
        2. Run in PowerShell:
            .\Enable_Hotspot.ps1
    - To integrate into automated workflows, consider calling from Task Scheduler at logon or startup
#>

Add-Type -AssemblyName System.Runtime.WindowsRuntime

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]

Function Await($WinRtTask, $ResultType) {
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}

Function AwaitAction($WinRtAction) {
    $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and !$_.IsGenericMethod })[0]
    $netTask = $asTask.Invoke($null, @($WinRtAction))
    $netTask.Wait(-1) | Out-Null
}

$connectionProfile = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetInternetConnectionProfile()
$tetheringManager = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]::CreateFromConnectionProfile($connectionProfile)

if ($tetheringManager.TetheringOperationalState -eq 1) {
    "Hotspot is already On!"
} else {
    "Hotspot is off! Turning it on"
    Await ($tetheringManager.StartTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
}
