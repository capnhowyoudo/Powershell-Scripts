<#
.SYNOPSIS
   Scans remote computers for PST files and exports details to a CSV.

.DESCRIPTION
   This script reads a list of computer names from a text file (computers.txt),
   recursively searches each computer's C$ drive for PST files (*.pst),
   and exports the results to a CSV file. The output includes file name, directory,
   size, last access time, last write time, and creation time.

.NOTES
   Author: capnhowyoudo
   - Input file: computers.txt (one computer name per line)
   - Output CSV: C:\Temp\PSTfiles.csv
   - Requires administrative access to remote C$ shares
   - Handles multiple computers automatically
   - Where to place computers.txt:
       Place the file in the same directory as this script OR specify the full path in Get-Content:
       Example: "C:\Scripts\computers.txt"
   - Example computers.txt content:
       PC01
       PC02
       Server01
   - Usage:
       1. Ensure computers.txt exists in the same folder as the script (or adjust the path in the script).
       2. Run the script in PowerShell as an admin:
           .\Scan_For_PST_Files.ps1
#>

# Ensure output directory exists
if (-not (Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" | Out-Null }

# Scan remote computers for PST files
Get-Content "computers.txt" |
    ForEach-Object {
        Write-Host "Scanning \\$_\c$ for PST files..."
        Get-ChildItem "\\$_\c$" -Include *.pst -Recurse -ErrorAction SilentlyContinue
    } |
    Select-Object Name, Directory, Length, LastAccessTime, LastWriteTime, CreationTime |
    Export-Csv "C:\Temp\PSTfiles.csv" -NoTypeInformation
