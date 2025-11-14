<#
.SYNOPSIS
    Retrieves the last installation or upgrade date of the local Windows operating system.

.DESCRIPTION
    This script reads the 'InstallTime' value from the registry at 
    HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion, which stores the 
    system installation timestamp as a Windows FileTime (64-bit integer).
    It converts this timestamp into a human-readable DateTime object 
    and outputs the system name along with the last OS installation/upgrade time.

.NOTES
    - Works on local machines only; does not query remote computers.
    - Requires read access to HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion.
    - No additional modules are required.
    - Example usage:
        1. Save the script as Get_Windows_OS_Upgrade_Time.ps1
        2. Run in PowerShell:
            .\Get_Windows_OS_Upgrade_Time.ps1
    - Output will show:
        - System name
        - Last OS Upgrade/Installation date and time
#>

## ⏳ Local Windows OS Upgrade Time Check

# Define the registry path where OS installation/upgrade details are stored
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"

# Use Get-ItemProperty to retrieve the 'InstallTime' value
try {
    $InstallDateFileTime = (Get-ItemProperty -Path $RegPath).InstallTime
    
    # Convert the FileTime value (a 64-bit integer) to a standard, human-readable DateTime object
    $InstallDate = [DateTime]::FromFileTime($InstallDateFileTime)

    # Output the result
    Write-Host "✅ System Name: $($env:COMPUTERNAME)" -ForegroundColor Green
    Write-Host "📅 Last OS Upgrade/Installation Time (Local): $($InstallDate)" -ForegroundColor Cyan
    
}
catch {
    Write-Host "❌ Error: Could not read the registry key or convert the date." -ForegroundColor Red
    Write-Host "Detail: $($_.Exception.Message)"
}
