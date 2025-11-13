<#
.SYNOPSIS
Searches all computers in an Active Directory environment for a specific logged-on user.

.DESCRIPTION
This script prompts for admin credentials, a username to search for, and a computer name prefix. 
It then queries all enabled computers in Active Directory matching the given prefix and checks for 
any running explorer.exe processes to determine if the specified user is currently logged on. 
The script provides real-time progress updates and displays the computers where the user is found. 

.NOTES
Author      : capnhowyoudo
Date        : 2025-11-12
Requires    : ActiveDirectory module (RSAT) installed, WMI access to remote computers
Usage       : Run the script in a session with AD privileges. Provide admin credentials, the target username, 
              and a computer name prefix (e.g., CXX*). Use '*' to search all computers.
Limitations : Only checks for interactive explorer.exe processes. May not detect disconnected sessions.
#>

# ---------------------------
# Initialize progress counter
# ---------------------------
$progress = 0

# ---------------------------
# Get Admin Credentials
# ---------------------------
Function Get-Login {
    Clear-Host
    Write-Host "Please provide admin credentials (for example DOMAIN\admin.user and your password)"
    $Global:Credential = Get-Credential
}
Get-Login

# ---------------------------
# Get Username to search for
# ---------------------------
Function Get-Username {
    Clear-Host
    $Global:Username = Read-Host "Enter username you want to search for"
    if ($Username -eq $null){
        Write-Host "Username cannot be blank, please re-enter username!"
        Get-Username
    }
    $UserCheck = Get-ADUser $Username
    if ($UserCheck -eq $null){
        Write-Host "Invalid username, please verify this is the logon id for the account!"
        Get-Username
    }
}
Get-Username

# ---------------------------
# Get Computer Name Prefix
# ---------------------------
Function Get-Prefix {
    Clear-Host
    $Global:Prefix = Read-Host "Enter a prefix of Computernames to search on (CXX*) use * as a wildcard or enter * to search on all computers"
    Clear-Host
}
Get-Prefix

# ---------------------------
# Start search
# ---------------------------
$computers = Get-ADComputer -Filter {Enabled -eq 'true' -and SamAccountName -like $Prefix}
$CompCount = $Computers.Count
Write-Host "Searching for $Username on $Prefix on $CompCount Computers`n"

# ---------------------------
# Main foreach loop: search processes on all computers
# ---------------------------
foreach ($comp in $computers){
    $Computer = $comp.Name
    $Reply = $null
    $Reply = Test-Connection $Computer -Count 1 -Quiet
    if ($Reply -eq 'True'){
        if($Computer -eq $env:COMPUTERNAME){
            # Query explorer.exe locally
            $proc = Get-WmiObject win32_process -ErrorAction SilentlyContinue -Computer $Computer -Filter "Name = 'explorer.exe'"
        }
        else{
            # Query explorer.exe remotely with credentials
            $proc = Get-WmiObject win32_process -ErrorAction SilentlyContinue -Credential $Credential -Computer $Computer -Filter "Name = 'explorer.exe'"
        }           
        # If no process returned, display failure message
        if([string]::IsNullOrEmpty($proc)){
            Write-Host "Failed to check $Computer!"
        }
        else{   
            $progress++            
            ForEach ($p in $proc) {              
                $temp = ($p.GetOwner()).User
                Write-Progress -Activity "Working..." -Status "Status: $progress of $CompCount Computers checked" -PercentComplete (($progress/$Computers.Count)*100)
                if ($temp -eq $Username){
                    Write-Host "$Username is logged on $Computer"
                }
            }
        }   
    }
}
Write-Host "Search done!"
