<#
.SYNOPSIS
Lists all printers mapped to the currently logged-on user session.

.DESCRIPTION
Retrieves printer details including Name, ShareName, and whether it is the 
default printer, specifically focusing on user-mapped devices.
#>

Write-Host "Retrieving printer list for: $env:USERNAME" -ForegroundColor Cyan
Write-Host "--------------------------------------------------"

# Fetch printers using CIM (modern WMI)
Get-CimInstance -Class Win32_Printer | 
    Select-Object Name, 
                  @{Name="Type"; Expression={if($_.Network){"Network"}else{"Local"}}},
                  PortName, 
                  Default, 
                  Status | 
    Format-Table -AutoSize

Write-Host "Finished." -ForegroundColor Green
