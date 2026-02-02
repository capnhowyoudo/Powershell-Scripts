<#
.SYNOPSIS
    Automates the installation of multiple Windows Apps via Winget with zero window pop-ups and immediate execution.

.DESCRIPTION
    This script uses 'conhost.exe --headless' to prevent the console flash and 'Start-ScheduledTask' 
    to ensure the installation begins the moment the script is executed.

.NOTES
    - If you want to install a different application, you must change the app ID within the $UserScript block.
    - Current ID: 9N1F85V9T8BN (Windows App).
    - Current ID: 9ncbcszsjrsb (Spotify).
    - To add more apps, list them inside the parentheses separated by commas
      $AppIds = @("9N1F85V9T8BN", "9WZDNCRFJBMP", "9NBLGGH4R3PZ")
    
      To obtain an AppId:
    - Open Microsoft Store https://apps.microsoft.com/home?hl=en-US&gl=US and locate the application
    - Copy the Store URL and extract the ID after the last slash (e.g. 9N1F85V9T8BN)
    - OR run: winget search <app name> and use the Id column
#>

$TaskName   = "InstallWindowsApp_Silent_Immediate"
$ScriptPath = "$env:ProgramData\InstallWindowsApp.ps1"

# User-context script
$UserScript = @'
function Ensure-Winget {
    $wingetPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
    if (-not (Test-Path $wingetPath)) {
        Start-Process "powershell.exe" -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"Get-AppxPackage Microsoft.DesktopAppInstaller -AllUsers | Foreach { Add-AppxPackage -DisableDevelopmentMode -Register `"$($_.InstallLocation)\AppXManifest.xml`" }`"" -Wait
    }
}

Ensure-Winget

# App IDs to install
$AppIds = @("9N1F85V9T8BN")

foreach ($Id in $AppIds) {
    Start-Process -FilePath "winget.exe" `
        -ArgumentList "install --id $Id --source msstore --accept-package-agreements --accept-source-agreements --silent --disable-interactivity" `
        -WindowStyle Hidden `
        -Wait
}
'@

# Write script silently
Set-Content -Path $ScriptPath -Value $UserScript -Encoding UTF8 -Force

# Scheduled task action
$Action = New-ScheduledTaskAction `
    -Execute "conhost.exe" `
    -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

$Trigger = New-ScheduledTaskTrigger -AtLogOn

$Principal = New-ScheduledTaskPrincipal `
    -GroupId "BUILTIN\Users" `
    -RunLevel Limited

# Register task
Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Force | Out-Null

# --- Immediate Execution Fix ---
# Wait 1 second to ensure registration is complete, then start
Start-Sleep -Seconds 1
Start-ScheduledTask -TaskName $TaskName
