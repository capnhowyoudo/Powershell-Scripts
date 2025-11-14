<#
.SYNOPSIS
Bulk change the logon password for multiple Windows services.

.DESCRIPTION
This script updates the "Log On As" credentials for one or more Windows services.
Useful when a service account password changes and several services use that account.

.PARAMETER Services
Array of service names to update.

.PARAMETER Username
The logon account name (e.g. 'DOMAIN\User' or '.\LocalUser').

.PARAMETER Password
The new password for that account. You will be prompted if not provided.

.PARAMETER Restart
If specified, services will be restarted after password change.

.EXAMPLE
.\Update_Multiple_Services_Logon_Password.ps1 -Services "Spooler","W32Time" -Username "CORP\ServiceAcct" -Restart
#>

param(
    [Parameter(Mandatory=$true)]
    [string[]]$Services,

    [Parameter(Mandatory=$true)]
    [string]$Username,

    [Parameter(Mandatory=$false)]
    [string]$Password,

    [switch]$Restart
)

# Prompt for password if not supplied
if (-not $Password) {
    $Secure = Read-Host "Enter password for $Username" -AsSecureString
    $Ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($Ptr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Ptr)
}

Write-Host "`n=== Starting password update for $Username ===" -ForegroundColor Cyan

foreach ($svcName in $Services) {
    try {
        $svc = Get-WmiObject -Class Win32_Service -Filter "Name='$svcName'" -ErrorAction Stop

        if (-not $svc) {
            Write-Warning "Service '$svcName' not found!"
            continue
        }

        Write-Host "Updating: $($svc.Name) ($($svc.DisplayName))" -ForegroundColor Yellow

        # Correct method signature for Win32_Service.Change()
        # Parameters: DisplayName, PathName, ServiceType, ErrorControl, StartMode, DesktopInteract, StartName, StartPassword, LoadOrderGroup, LoadOrderGroupDependencies, ServiceDependencies
        $result = $svc.Change(
            $null,        # DisplayName
            $null,        # PathName
            $null,        # ServiceType
            $null,        # ErrorControl
            $null,        # StartMode
            $null,        # DesktopInteract
            $Username,    # StartName
            $Password,    # StartPassword
            $null,        # LoadOrderGroup
            $null,        # LoadOrderGroupDependencies
            $null         # ServiceDependencies
        )

        if ($result.ReturnValue -eq 0) {
            Write-Host "✔ Password updated successfully for $svcName" -ForegroundColor Green
        } else {
            Write-Warning "Failed to update $svcName (WMI code: $($result.ReturnValue))"
        }

        if ($Restart) {
            Write-Host "Restarting service: $svcName ..." -ForegroundColor DarkCyan
            Restart-Service -Name $svcName -Force -ErrorAction Stop
            Write-Host "✔ Restarted $svcName successfully" -ForegroundColor Green
        }

    } catch {
        Write-Warning "Error processing service '$svcName': $_"
    }
}

Write-Host "`nAll tasks completed." -ForegroundColor Cyan
