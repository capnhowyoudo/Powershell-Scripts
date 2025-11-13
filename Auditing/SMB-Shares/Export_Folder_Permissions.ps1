<#
.SYNOPSIS
Generates a CSV report of folder permissions for a specified shared directory.

.DESCRIPTION
This script recursively enumerates all folders under a given shared network path and retrieves their 
Access Control Lists (ACLs). For each folder, it collects the AD group or user, their permissions, 
and whether the permissions are inherited.  

The results are stored in a CSV file in C:\Temp for auditing, compliance, or documentation purposes.  
The script can be run by an administrator or through RMM tools with sufficient access to the target share.

.NOTES
File Name   : Export_Folder_Permissions.ps1
Author      : capnhowyoudo
Date        : 2025-11-13
Requires    : PowerShell 3.0+ and read access to the shared folders
Usage       : 
    - Modify $FolderPath to the target shared folder
    - Run the script to generate a CSV report
Output File : C:\Temp\FolderPermissions.csv
Limitations : Only enumerates folders; files are not included. Requires proper network and filesystem permissions.
#>

# Set target folder path
$FolderPath = Get-ChildItem -Directory -Path "\\fs1\Shared" -Recurse -Force

# Initialize report collection
$Report = @()

# Loop through each folder and get ACLs
foreach ($Folder in $FolderPath) {
    $Acl = Get-Acl -Path $Folder.FullName
    foreach ($Access in $Acl.Access) {
        $Properties = [ordered]@{
            'FolderName'         = $Folder.FullName
            'AD Group or User'   = $Access.IdentityReference
            'Permissions'        = $Access.FileSystemRights
            'Inherited'          = $Access.IsInherited
        }
        $Report += New-Object -TypeName PSObject -Property $Properties
    }
}

# Ensure output directory exists
$OutputPath = "C:\Temp\FolderPermissions.csv"
if (!(Test-Path (Split-Path $OutputPath))) {
    New-Item -ItemType Directory -Path (Split-Path $OutputPath) -Force | Out-Null
}

# Export report to CSV
$Report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "Folder permissions exported to $OutputPath"
