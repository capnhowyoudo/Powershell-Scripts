<#
.SYNOPSIS
This script configures a VPN connection on a Windows system, sets up routing for specific subnets, and makes adjustments for NAT traversal issues. It also provides an option to remember credentials for the VPN connection.

.DESCRIPTION
This PowerShell script creates or updates a VPN connection with the following configurations:
- Checks if the phonebook file (rasphone.pbk) exists and creates it if necessary.
- Removes any existing VPN connection with the specified name.
- Adds a new L2TP VPN connection using a pre-shared key (PSK).
- Optionally remembers user credentials for the VPN connection.
- Configures split tunneling (can be switched to full tunnel by modifying the split tunneling setting).
- Adds static routes for specified subnets to be routed through the VPN.
- Updates the rasphone.pbk file to use Windows credentials for authentication.
- Optionally creates a desktop shortcut for the VPN connection (commented out by default).
- Fixes common NAT-Traversal issues on Windows (relevant for hotspots or NAT'd networks).
- Designed to be flexible with customizable parameters defined at the top of the script.

.NOTES
Author: capnhowyoudo
Date: 11.13.25
Version: 1.0
Use this script to automate the setup of a VPN connection, subnet routing, and handling NAT issues for users connecting to a VPN on a Windows machine.
Make sure to run as an Administrator
Make sure to modify the following parameters at the top of the script to match your VPN settings:
- `$ConnectionName` (VPN connection name)
- `$ServerAddress` (VPN server address or hostname)
- `$PresharedKey` (VPN pre-shared key)
- `$Subnets` (list of subnets to route through the VPN)
Ensure you run this script with administrative privileges for full functionality.
If you need to add additional subnets, simply **remove the comments (uncomment) the subnet lines** in the `$Subnets` array below.

#>

# Define generic parameters at the top for easy customization

# Path for the public phonebook. Change $env:PROGRAMDATA to $env:APPDATA if not creating an AllUserConnection.
$PbkPath = Join-Path $env:PROGRAMDATA 'Microsoft\Network\Connections\Pbk\rasphone.Pbk'

# VPN connection parameters
$ConnectionName = 'Generic VPN'             # VPN Connection name
$ServerAddress = '3.13.248.123'             # VPN Server address (use IP or hostname)
$PresharedKey = 'YourPresharedKeyHere'      # VPN Pre-shared Key (replace with actual value)

# Option to remember credentials
$RememberCredentials = $True

# List of subnets for routing (adjust as needed)
$Subnets = @(
    '172.31.0.0/16'  # First subnet
    # '172.31.1.0/24',  # Second subnet (commented out) - Remove comment to enable routing for this subnet
    # '192.168.1.0/24'  # Third subnet (commented out) - Remove comment to enable routing for this subnet
)

# Check if the RAS phonebook file exists, if not, create a placeholder
If ((Test-Path $PbkPath) -eq $false) {
    $PbkFolder = Join-Path $env:PROGRAMDATA "Microsoft\Network\Connections\pbk\"
    # Check if pbk folder exists. If it does, create a placeholder phonebook.
    if ((Test-Path $PbkFolder) -eq $true){
        New-Item -Path $PbkFolder -Name "rasphone.pbk" -ItemType "file" | Out-Null
    }
    # If pbk folder doesn't exist, create it and then make a placeholder phonebook.
    else {
        $ConnectionFolder = Join-Path $env:PROGRAMDATA "Microsoft\Network\Connections\"
        New-Item -Path $ConnectionFolder -Name "pbk" -ItemType "directory" | Out-Null
        New-Item -Path $PbkFolder -Name "rasphone.pbk" -ItemType "file" | Out-Null
    }
}

# Remove existing VPN connection if it exists
Remove-VpnConnection -AllUserConnection -Name $ConnectionName -Force -EA SilentlyContinue

# Add the new VPN connection with option to remember credentials
Add-VpnConnection -Name $ConnectionName -ServerAddress $ServerAddress -AllUserConnection `
    -TunnelType L2tp -L2tpPsk $PresharedKey -AuthenticationMethod Pap, Chap, MSChapv2 `
    -EncryptionLevel Optional -Force -RememberCredential $RememberCredentials -WA SilentlyContinue

# Set the VPN connection to use split tunneling (set to False for full tunnel)
Start-Sleep -m 100
Set-VpnConnection -Name $ConnectionName -SplitTunneling $True -AllUserConnection -WA SilentlyContinue

# Add routes for the defined subnets
foreach ($Destination in $Subnets) {
    Start-Sleep -m 100
    Add-VpnConnectionRoute -ConnectionName $ConnectionName -AllUserConnection -DestinationPrefix $Destination
}

# Modify RASPhone.pbk to use Windows credentials for authentication (important for cloud VPN solutions like Meraki)
(Get-Content -Path $PbkPath -Raw) -Replace 'UseRasCredentials=1', 'UseRasCredentials=0' | Set-Content -Path $PbkPath

# Create a desktop shortcut for all users (comment out if not needed)
#$ShortcutFile = "$env:Public\Desktop\$ConnectionName.lnk"
#$WScriptShell = New-Object -ComObject WScript.Shell
#$Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
#$Shortcut.TargetPath = "rasphone.exe"
#$Shortcut.Arguments = "-d `"$ConnectionName`""
#$ShortCut.WorkingDirectory = "$env:SystemRoot\System32\"
#$Shortcut.Save()

# Resolve potential NAT-Traversal issue (relevant for hotspots or NAT'd networks)
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\PolicyAgent"
$Name = "AssumeUDPEncapsulationContextOnSendRule"
$value = "2"
New-ItemProperty -Path $registryPath -Name $Name -Value $value -PropertyType DWORD -Force | Out-Null
