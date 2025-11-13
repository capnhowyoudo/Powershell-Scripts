<#
.SYNOPSIS
    Ensures the PowerShell script is running with administrator privileges.

.DESCRIPTION
    This function checks if the current PowerShell session is elevated (running as Administrator).
    If not, it attempts to re-launch itself with elevated privileges using the `runas` verb.
    If elevation fails, it displays an error message informing the user that administrative rights are required.

    The script also sets the PowerShell execution policy for the current process to Bypass, ensuring
    that the script can run without restriction regardless of system-wide execution policy settings.

.NOTES
    Requirements: Windows PowerShell 5.1 or later, Administrator rights for full functionality.
    Can be added to any powershell script by adding to the top of the script. 
    Tested On: Windows 10, Windows 11
#>

# ---------------------------
# AUTO-ELEVATE IF NOT ADMIN
# ---------------------------
function Ensure-Elevated {
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    } catch {
        $isAdmin = $false
    }
    if (-not $isAdmin) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        # If running as EXE, re-launch same exe with elevation; otherwise launch powershell with the script path
        try { $procPath = (Get-Process -Id $PID).Path } catch { $procPath = $null }
        if ($procPath) {
            $psi.FileName = $procPath
            $psi.Arguments = ""
        } else {
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
        }
        $psi.Verb = "runas"
        try {
            [System.Diagnostics.Process]::Start($psi) | Out-Null
            Exit
        } catch {
            [System.Windows.MessageBox]::Show("This tool requires administrator privileges. Please re-run as Administrator.","Elevation Required",[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
            Exit 1
        }
    }
}
Ensure-Elevated

# ---------------------------
# ENVIRONMENT
# ---------------------------
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

