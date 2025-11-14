<#
.SYNOPSIS
    Uninstalls Microsoft Teams Classic and installs the new Microsoft Teams client (Bootstrapper-based).

.DESCRIPTION
    This script performs a seamless upgrade from Microsoft Teams Classic to the new Teams client.
    - Step 1: Checks if the script has already run (creates a run-once flag file).
    - Step 2: Uninstalls Microsoft Teams Classic using a downloaded script.
    - Step 3: Downloads the New Teams Bootstrapper installer.
    - Step 4: Installs the New Teams client machine-wide.
    - Step 5: Marks the upgrade as complete and cleans up temporary files.
    
    Designed to run silently during GPO shutdown as SYSTEM without logging, so users do not require interaction.

.NOTES
    Author: capnhowyoudo
    - Intended for GPO deployment (runs as SYSTEM)
    - Run-once behavior ensures it does not re-run on subsequent startups
    - Run as SYSTEM or equivalent admin context for proper installation
    - No logging is built-in; consider adding logging if needed
    - Files created temporarily:
        $env:TEMP\UninstallClassicTeams.ps1
        C:\ProgramData\TeamsBootstrapper.exe
        C:\ProgramData\UpgradeToNewTeams.done (run-once flag)
    - Deployment Instructions:
        1. Add this script to **Computer Configuration → Policies → Windows Settings → Scripts → Shutdown**.
        2. Use the following script parameters: `-ExecutionPolicy Bypass -NoProfile`
        3. The script will automatically uninstall Classic Teams, install the new Teams client, and clean up temporary files.
    - Usage:
        1. Deploy via GPO Shutdown Script.
        2. Ensure the script has network access to download installers.
        3. The script runs silently as SYSTEM.
#>

# ========================
# Run-once check
# ========================
$RunOnceFlag = "C:\ProgramData\UpgradeToNewTeams.done"
if (Test-Path $RunOnceFlag) {
    exit 0
}

# ========================
# Step 1: Uninstall Teams Classic
# ========================
$UninstallScriptPath = "$env:TEMP\UninstallClassicTeams.ps1"
try {
    Invoke-WebRequest -Uri "https://aka.ms/uninstallclassicteamsscript" -OutFile $UninstallScriptPath -UseBasicParsing
    powershell.exe -ExecutionPolicy Bypass -File $UninstallScriptPath -ErrorAction Stop
} catch {
    # Ignore uninstall errors
}

# ========================
# Step 2: Download New Teams Bootstrapper
# ========================
$BootstrapperURL = "https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409"
$BootstrapperPath = "C:\ProgramData\TeamsBootstrapper.exe"

try {
    Invoke-WebRequest -Uri $BootstrapperURL -OutFile $BootstrapperPath -UseBasicParsing
} catch {
    exit 1
}

# ========================
# Step 3: Install Teams (Machine-Wide)
# ========================
try {
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$BootstrapperPath`" -p" -Wait -WindowStyle Hidden
} catch {
    # Ignore install errors
}

# ========================
# Step 4: Mark as complete
# ========================
try {
    New-Item -ItemType File -Path $RunOnceFlag -Force | Out-Null
} catch {}

# ========================
# Step 5: Cleanup
# ========================
try {
    Remove-Item $UninstallScriptPath -Force -ErrorAction SilentlyContinue
    Remove-Item $BootstrapperPath -Force -ErrorAction SilentlyContinue
} catch {}
