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

# This is required for Verbose to work correctly.
# If you don't want the Verbose message, remove "-Verbose" from the Parameters field.
[CmdletBinding()]
param ()

# On most OSes, HKEY_USERS only contains users that are logged on.
# There are ways to load the other profiles, but it can be problematic.
$Drives = Get-ItemProperty "Registry::HKEY_USERS\*\Network\*"

# See if any drives were found
if ( $Drives ) {

ForEach ( $Drive in $Drives ) {

# PSParentPath looks like this: Microsoft.PowerShell.Core\Registry::HKEY_USERS\S-1-5-21-##########-##########-##########-####\Network
        $SID = ($Drive.PSParentPath -split '\\')[2]

[PSCustomObject]@{
            # Use .NET to look up the username from the SID
            Username            = ([System.Security.Principal.SecurityIdentifier]"$SID").Translate([System.Security.Principal.NTAccount])
            DriveLetter         = $Drive.PSChildName
            RemotePath          = $Drive.RemotePath

# The username specified when you use "Connect using different credentials".
            # For some reason, this is frequently "0" when you don't use this option. I remove the "0" to keep the results consistent.
            ConnectWithUsername = $Drive.UserName -replace '^0$', $null
            SID                 = $SID
        }

}

} else {

Write-Verbose "No mapped drives were found"

}
