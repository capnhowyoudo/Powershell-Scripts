<#
.SYNOPSIS
Retrieves all mapped network drives for currently logged-on users.

.DESCRIPTION
This script queries the Windows registry under HKEY_USERS to find network drives mapped for 
currently logged-on users. For each mapped drive, it outputs the username, drive letter, remote path, 
the username used to connect (if different credentials were used), and the user's SID. This information 
is returned as PSCustomObjects, allowing for further processing or export. Verbose output can indicate 
if no mapped drives are found. Note that only users with loaded profiles in HKEY_USERS are included.

The script can be run interactively by an administrator or remotely as the SYSTEM account using RMM 
(Remote Monitoring and Management) tools, making it suitable for enterprise-wide audits of mapped drives.

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-12
Requires    : PowerShell 5.1+ (or compatible version), access to HKEY_USERS registry hive
Usage       : Run in a session with sufficient privileges to read HKEY_USERS. Supports Verbose output.
Limitations : Only users with loaded profiles are included. Mapped drives from unloaded profiles will not appear.
#>

[CmdletBinding()]
param (
    [switch]$ExportCsv = $false,             # Optionally export results to CSV set to true
    [string]$CsvPath = "C:\Temp\MappedDrives.csv"  # Default CSV path
)

# Get all network drives under HKEY_USERS
$Drives = Get-ItemProperty "Registry::HKEY_USERS\*\Network\*"

# Initialize results collection
$Results = @()

# Check if any drives were found
if ($Drives) {
    ForEach ($Drive in $Drives) {

        # Extract SID from the registry path
        $SID = ($Drive.PSParentPath -split '\\')[2]

        $Obj = [PSCustomObject]@{
            # Translate SID to NT username
            Username            = ([System.Security.Principal.SecurityIdentifier]"$SID").Translate([System.Security.Principal.NTAccount])
            DriveLetter         = $Drive.PSChildName
            RemotePath          = $Drive.RemotePath
            # Remove "0" for ConnectWithUsername when not used
            ConnectWithUsername = $Drive.UserName -replace '^0$', $null
            SID                 = $SID
        }

        # Output to pipeline
        $Obj
        # Collect for optional export
        $Results += $Obj

    }

    # Export to CSV if requested
    if ($ExportCsv) {
        $Results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        Write-Host "Mapped drives exported to $CsvPath"
    }

} else {

    Write-Verbose "No mapped drives were found"

}
