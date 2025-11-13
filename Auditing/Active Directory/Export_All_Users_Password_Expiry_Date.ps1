<#
.SYNOPSIS
Generates a report of Active Directory users including password expiration and last set dates.

.DESCRIPTION
This script retrieves all Active Directory users and relevant properties including `DisplayName`, 
`PasswordNeverExpires`, `msDS-UserPasswordExpiryTimeComputed`, and `PasswordLastSet`.  

It calculates the next password change date based on the domain password policy and whether the user’s 
password is set to never expire.  

The output is sorted alphabetically by `DisplayName` and exported to a CSV file in `C:\Temp` for auditing 
or compliance purposes.  

The script can be run by an administrator or a system account (for example via RMM tools) with the 
required permissions to read user attributes in Active Directory.

.NOTES
File Name   : Export_All_Users_Password_Expiry_Date.ps1
Author      : capnhowyoudo
Date        : 2025-11-13
Requires    : PowerShell 5.1+ and ActiveDirectory module
Usage       : 
    - Run the script to generate a CSV report of AD users and password information
Output File : C:\Temp\ADUserPasswordReport.csv
Limitations : Requires access to Active Directory. Users without a password set will show "Never" or "Unknown".
#>

# Get all AD users with relevant properties
$users = Get-ADUser -Filter * -Properties "DisplayName", "PasswordNeverExpires", "msDS-UserPasswordExpiryTimeComputed", "PasswordLastSet" |

# Select desired properties and calculate expiry and last set date
Select-Object -Property "DisplayName",
    @{Name="PasswordNeverExpires";Expression={$_.PasswordNeverExpires}},
    @{Name="LastPasswordSet";Expression={
        if ($_.PasswordLastSet) {
            [DateTime]::FromFileTime($_.PasswordLastSet)
        } else {
            "Never"
        }
    }},
    @{Name="NextPasswordChange";Expression={
        if ($_.PasswordNeverExpires -eq $True) {
            "Never"
        } elseif ($_. "msDS-UserPasswordExpiryTimeComputed") {
            [DateTime]::FromFileTime($_."msDS-UserPasswordExpiryTimeComputed")
        } elseif ($_.PasswordLastSet) {
            [DateTime]::FromFileTime($_.PasswordLastSet) + (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge
        } else {
            "Unknown"
        }
    }} |

# Sort alphabetically by DisplayName
Sort-Object -Property "DisplayName"

# Export the result to CSV
$users | Export-Csv -Path "C:\Temp\ADUserPasswordReport.csv" -NoTypeInformation -Encoding UTF8

# Optional: display a confirmation
Write-Host "Report exported to C:\Temp\ADUserPasswordReport.csv"
