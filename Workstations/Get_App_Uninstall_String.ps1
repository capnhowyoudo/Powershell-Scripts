<#
.SYNOPSIS
Finds the uninstall string for a specified application on a Windows system.

.DESCRIPTION
This script searches the Windows registry for a given program name in both the 32-bit and 64-bit 
uninstall registry paths. It retrieves the DisplayName, DisplayVersion, UninstallString, and PSChildName 
for the matching application(s). 

If a single match is found:
- If the uninstall string uses `msiexec.exe /i`, it automatically converts it to `msiexec.exe /x` 
  for silent uninstallation.
- Otherwise, it outputs the original uninstall string.

If multiple matches are found, it prompts the user to narrow down the search.  
If no match is found, it notifies the user accordingly.

This script is useful for system administrators who need to find uninstall commands for applications.

.NOTES
File Name   : Get_App_Uninstall_String.ps1
Author      : capnhowyoudo
Date        : 2025-11-13
Requires    : PowerShell 3.0+
Usage       : 
    .\Get_App_Uninstall_String.ps1
Limitations : Search is based on program name matching in registry uninstall paths only.
#>

# Prompt user for application name
$appname = Read-Host "Enter your program name"

# Search 32-bit applications
$32bit = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' |
    Select-Object DisplayName, DisplayVersion, UninstallString, PSChildName |
    Where-Object { $_.DisplayName -match "^.*$appname.*" }

# Search 64-bit applications
$64bit = Get-ItemProperty 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
    Select-Object DisplayName, DisplayVersion, UninstallString, PSChildName |
    Where-Object { $_.DisplayName -match "^.*$appname.*" }

# Process results
if ($64bit -eq $null -or $64bit.count -eq 0) {
    switch ($32bit.DisplayName.count) {
        0 { Write-Host "Cannot find the uninstall string" -ForegroundColor Red }
        1 {
            if ($32bit.UninstallString -match "msiexec.exe") {
                $32bit.UninstallString -replace 'msiexec.exe /i','msiexec.exe /x'
            }
            else {
                $32bit.UninstallString
            }
        }
        default { Write-Host "Please narrow down your search" -ForegroundColor Red }
    }
}
else {
    switch ($64bit.DisplayName.count) {
        0 { Write-Host "Cannot find the uninstall string" -ForegroundColor Red }
        1 {
            if ($64bit.UninstallString -match "msiexec.exe") {
                $64bit.UninstallString -replace 'msiexec.exe /i','msiexec.exe /x'
            }
            else {
                $64bit.UninstallString
            }
        }
        default { Write-Host "Please narrow down your search" -ForegroundColor Red }
    }
}
