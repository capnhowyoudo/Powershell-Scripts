<#
.SYNOPSIS
Checks Active Directory for recent account lockout events for a specific user.

.DESCRIPTION
This script prompts for a username and searches the Primary Domain Controller (PDC) for 
account lockout events (Event ID 4740) in the Security event log. It retrieves information 
including the user, domain controller, event ID, lockout timestamp, message, and lockout source. 
The results are displayed in a formatted output. Ensure the ActiveDirectory module is installed 
and that you have sufficient permissions to query the PDC and read Security event logs.

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-12
Requires    : ActiveDirectory module (RSAT), access to Security event logs on the PDC
Usage       : Run the script in a session with AD privileges. Enter a valid username when prompted.
Limitations : Only searches lockout events on the PDC and may not include replication delays.
#>

# Import Active Directory module
Import-Module ActiveDirectory

# Prompt for username
$UserName = Read-Host "Please enter username"

# Get the Primary Domain Controller (PDC)
$PDC = (Get-ADDomainController -Filter * | Where-Object {$_.OperationMasterRoles -contains "PDCEmulator"})

# Get user information
$UserInfo = Get-ADUser -Identity $UserName

# Search PDC for lockout events with ID 4740
$LockedOutEvents = Get-WinEvent -ComputerName $PDC.HostName -FilterHashtable @{LogName='Security';Id=4740} -ErrorAction Stop | Sort-Object -Property TimeCreated -Descending

# Parse and filter lockout events for the user
Foreach($Event in $LockedOutEvents) {
    If($Event | Where {$_.Properties[2].value -match $UserInfo.SID.Value}) {
        $Event | Select-Object -Property @(
            @{Label = 'User'; Expression = {$_.Properties[0].Value}},
            @{Label = 'DomainController'; Expression = {$_.MachineName}},
            @{Label = 'EventId'; Expression = {$_.Id}},
            @{Label = 'LockoutTimeStamp'; Expression = {$_.TimeCreated}},
            @{Label = 'Message'; Expression = {$_.Message -split "`r" | Select-Object -First 1}},
            @{Label = 'LockoutSource'; Expression = {$_.Properties[1].Value}}
        )
    }
}
