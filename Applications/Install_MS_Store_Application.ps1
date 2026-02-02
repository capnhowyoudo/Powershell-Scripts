<#
.SYNOPSIS
Creates a user-context scheduled task that installs a Microsoft Store application silently using winget at user logon.

.DESCRIPTION
This script writes a secondary PowerShell script to ProgramData that ensures winget is available in the user context and installs a specified Microsoft Store application if it is not already present.  
It then creates and registers a scheduled task that runs at user logon under the standard user context (non-elevated), executes silently, and triggers immediately after registration.

.NOTES
- Runs in user context (non-administrative)
- Uses winget via Microsoft Store App Installer
- Executes silently with no user interaction
- Application installed can be changed by modifying the AppId variable
- To obtain an AppId:
  - Open Microsoft Store and locate the application
  - Copy the Store URL and extract the ID after the last slash (e.g. 9N1F85V9T8BN)
  - OR run: winget search <app name> and use the Id column
#>

$TaskName   = "InstallWindowsApp_UserContext"
$ScriptPath = "$env:ProgramData\InstallWindowsApp.ps1"

# Winget App ID to install (change as needed)
$AppId = "9N1F85V9T8BN"

# User-context script (silent)
$UserScript = @"
# Function to check for winget
function Ensure-Winget {
    \$wingetPath = "\$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
    if (-not (Test-Path \$wingetPath)) {
        # Winget comes with App Installer from Microsoft Store
        Write-Output "Winget not found. Installing App Installer silently…"
        Start-Process "powershell.exe" -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"Get-AppxPackage Microsoft.DesktopAppInstaller -AllUsers | Foreach { Add-AppxPackage -DisableDevelopmentMode -Register `"`$(`$_.InstallLocation)\AppXManifest.xml`" }`"" -WindowStyle Hidden -Wait
    }
}

# Ensure winget is present
Ensure-Winget

# Install application if not installed
Start-Process -FilePath "winget.exe" `
    -ArgumentList "install --id $AppId --source msstore --accept-package-agreements --accept-source-agreements --silent" `
    -WindowStyle Hidden `
    -Wait
"@

# Write script silently
Set-Content -Path $ScriptPath -Value $UserScript -Encoding UTF8 -Force

# Scheduled task action
$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""

# Run at user logon
$Trigger = New-ScheduledTaskTrigger -AtLogOn

# Run as logged-on user, not elevated
$Principal = New-ScheduledTaskPrincipal `
    -GroupId "BUILTIN\Users" `
    -RunLevel Limited

# Register task
Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Force

# Run immediately (silent)
schtasks /run /tn $TaskName | Out-Null
