<#
.SYNOPSIS
   Scans all user profile directories under C:\Users and reports their sizes.

.DESCRIPTION
   This script enumerates all directories in C:\Users, recursively calculates the total size of each user profile,
   and outputs a CSV report with the folder name, full path, and size in MB. The script uses -Force to include hidden
   files and silently continues on any access errors.

.NOTES
   Author: capnhowyoudo
   - Output CSV path: C:\Temp\UserProfiles.csv
   - Includes hidden files in size calculation
   - Handles access-denied errors silently
   - Example usage: run directly in PowerShell as administrator
   - CSV will contain columns: Name, Path, Size
#>

# Ensure output directory exists
if (-not (Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" | Out-Null }

# Scan user directories and export sizes
Get-ChildItem C:\Users |
    ForEach-Object `
        -Begin { Write-Host -Object "Scanning user directories..." } `
        -Process {
            Write-Host "Scanning path '$($_.FullName)'"
            $Size = (Get-ChildItem $_.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum -Maximum).Sum

            [pscustomobject] @{
                Name = $_.Name
                Path = $_.FullName
                Size = '{0:N2} MB' -f ( $Size / 1MB )
            }
        } |
        Export-Csv -Path C:\Temp\UserProfiles.csv -NoTypeInformation
