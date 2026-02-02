<#
.SYNOPSIS
    Automates the installation of a specific Windows App via Winget by creating a user-context scheduled task.

.DESCRIPTION
    This script facilitates the silent installation of Windows applications from the Microsoft Store. It performs the following steps:
    1. Defines a sub-script that checks for the presence of the Winget package manager and attempts to register it if missing.
    2. Checks if the target application (Microsoft Corporation Windows App) is already installed.
    3. If not installed, it uses Winget to download and install the app using its specific Store ID.
    4. Creates a Scheduled Task that runs the installation script in the context of the logged-on user with limited privileges to ensure compatibility with user-level app installations.
    5. Triggers the task to run immediately and at every subsequent logon.

.NOTES
    - If you want to install a different application, you must change --ID within the $UserScript block (currently set to 9N1F85V9T8BN).
    - The script is designed to run silently without user intervention.
    - Requires Internet access for Winget to reach the Microsoft Store.

    To obtain an AppId:
    - Open Microsoft Store https://apps.microsoft.com/home?hl=en-US&gl=US and locate the application
    - Copy the Store URL and extract the ID after the last slash (e.g. 9N1F85V9T8BN)
    - OR run: winget search <app name> and use the Id column
#>

$TaskName   = "InstallWindowsApp_UserContext"
$ScriptPath = "$env:ProgramData\InstallWindowsApp.ps1"

# User-context script (silent)
$UserScript = @'
# Function to check for winget
function Ensure-Winget {
    $wingetPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
    if (-not (Test-Path $wingetPath)) {
        # Winget comes with App Installer from Microsoft Store
        Write-Output "Winget not found. Installing App Installer silently..."
        Start-Process "powershell.exe" -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"Get-AppxPackage Microsoft.DesktopAppInstaller -AllUsers | Foreach { Add-AppxPackage -DisableDevelopmentMode -Register `"$($_.InstallLocation)\AppXManifest.xml`" }`"" -WindowStyle Hidden -Wait
    }
}

# Ensure winget is present
Ensure-Winget

# Install Windows App if not installed
if (-not (Get-AppxPackage -Name MicrosoftCorporationII.WindowsApp -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath "winget.exe" `
        -ArgumentList "install --id 9N1F85V9T8BN --source msstore --accept-package-agreements --accept-source-agreements --silent" `
        -WindowStyle Hidden `
        -Wait
}
'@

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
