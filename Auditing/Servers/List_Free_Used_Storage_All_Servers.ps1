<#
This PowerShell script is designed to collect disk space information from all enabled Windows Server computers listed in Active Directory (AD). 
It connects remotely to each server, retrieves details about local drives, calculates disk usage statistics, and then produces a report — both on-screen and optionally exported as a CSV file.
#>

# Requires appropriate permissions to read AD and access remote WMI/CIM on servers

# 1. Get a list of all server computers from Active Directory that are enabled
$Servers = Get-ADComputer -Filter 'OperatingSystem -Like "*Server*" -and Enabled -eq $True' | 
            Select-Object -ExpandProperty Name

# Define an array to store the results
$DiskReport = @()

# 2. Loop through each server and check disk space
foreach ($Server in $Servers) {
    Write-Host "Checking disk space on server: $Server" -ForegroundColor Yellow

    # Check if the server is online (optional but recommended)
    if (Test-Connection -ComputerName $Server -Count 1 -ErrorAction SilentlyContinue) {
        try {
            # Use Get-CimInstance (preferred over Get-WmiObject) for remote disk info
            # Filter for DriveType 3 (Local Disk)
            $Disks = Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $Server -Filter "DriveType = 3" -ErrorAction Stop
            
            # Process the data for each disk
            foreach ($Disk in $Disks) {
                # Calculate size, used space, and percentages
                $TotalSizeGB = [Math]::Round($Disk.Size / 1GB, 2)
                $FreeSpaceGB = [Math]::Round($Disk.FreeSpace / 1GB, 2)
                
                # Handle potential division by zero if Size is null/zero
                if ($TotalSizeGB -gt 0) {
                    $UsedSpaceGB = [Math]::Round($TotalSizeGB - $FreeSpaceGB, 2)
                    $FreePercent = [Math]::Round(($Disk.FreeSpace / $Disk.Size) * 100, 2)
                    $UsedPercent = [Math]::Round(100 - $FreePercent, 2)
                } else {
                    $UsedSpaceGB = 0
                    $FreePercent = 0
                    $UsedPercent = 0
                }

                # Create a custom object for the report
                $DiskReport += [PSCustomObject]@{
                    ServerName    = $Server
                    DriveLetter   = $Disk.DeviceID
                    VolumeName    = $Disk.VolumeName
                    TotalGB       = $TotalSizeGB
                    UsedGB        = $UsedSpaceGB
                    FreeGB        = $FreeSpaceGB
                    FreePercent   = "$FreePercent%"
                    UsedPercent   = "$UsedPercent%"
                }
            }
        }
        catch {
            Write-Warning "Could not retrieve disk info from $Server. $($_.Exception.Message)"
            $DiskReport += [PSCustomObject]@{
                ServerName    = $Server
                DriveLetter   = "N/A"
                VolumeName    = "N/A"
                TotalGB       = "Error"
                UsedGB        = "Error"
                FreeGB        = "Error"
                FreePercent   = "Error"
                UsedPercent   = "Error"
            }
        }
    }
    else {
        Write-Warning "Server $Server is offline or unreachable."
        $DiskReport += [PSCustomObject]@{
            ServerName    = $Server
            DriveLetter   = "N/A"
            VolumeName    = "N/A"
            TotalGB       = "Offline"
            UsedGB        = "Offline"
            FreeGB        = "Offline"
            FreePercent   = "Offline"
            UsedPercent   = "Offline"
        }
    }
}

# 3. Output the final report
Write-Host "`n--- Disk Space Report ---" -ForegroundColor Green
$DiskReport | Format-Table -AutoSize

# Optional: Export the report to a CSV file
$ReportPath = "C:\temp\AD_Disk_Space_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$DiskReport | Export-Csv -Path $ReportPath -NoTypeInformation
