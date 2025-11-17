<#
.SYNOPSIS
This script retrieves the logical disk information for drives of type "3" (Local Disk) 
on individual Windows servers and calculates the free and used space percentages.

.DESCRIPTION
The script uses the `Get-WmiObject` cmdlet to query the Win32_LogicalDisk class for 
drives of type "3" (local disks). It then selects the device ID along with calculated 
values for the free and used space as percentages of the total disk size. This is 
useful for monitoring disk space utilization on individual servers.

.NOTES
File Name      : List_Free_Used_Storage_Individual_Servers.ps1
Author         : capnhowyoudo
Version        : 1.0
Date           : [Insert Date]
Purpose        : To monitor disk space usage on individual servers
Requires       : PowerShell (any version that supports Get-WmiObject)
Example Usage  : Run the script on individual servers to view disk space usage statistics.
#>

Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3" | 
Select-Object DeviceID, 
    @{Label="Free Space (%)"; Expression={[Math]::Round(($_.FreeSpace / $_.Size) * 100, 2)}},
    @{Label="Used Space (%)"; Expression={[Math]::Round(((($_.Size - $_.FreeSpace) / $_.Size) * 100), 2)}}
