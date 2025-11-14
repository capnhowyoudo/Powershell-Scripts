<#
.SYNOPSIS
    Shows all AD user accounts updated within a specified number of days.

.DESCRIPTION
    This script searches Active Directory for user objects whose `whenChanged`
    attribute falls within a user-specified number of days from today. It displays
    usernames, display names, who modified them (if available), and when the change occurred.

.NOTES
    - Requires ActiveDirectory module (RSAT or Domain Controller)
    - Run as a domain admin or account with read access to all users
    - You can specify how many days back to check using the -Days parameter
    - Default is 1 day (today)
    - Example usage:
        .\Get_AD_Users_Accounts_Updated_Last_N_Days.ps1 -Days 3
      This checks all users updated in the last 3 days.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [int]$Days = 1  # Number of days to look back
)

Import-Module ActiveDirectory

# Calculate date range
$today = (Get-Date).Date
$startDate = $today.AddDays(-($Days - 1))   # Start date based on number of days
$endDate = $today.AddDays(1)                # Up to tomorrow

Write-Host "Searching for AD user accounts updated between $startDate and $endDate..." -ForegroundColor Cyan

# Query Active Directory for users changed in the date range
$updatedUsers = Get-ADUser -Filter {
    whenChanged -ge $startDate -and whenChanged -lt $endDate
} -Properties whenChanged, whenCreated, Name, SamAccountName, DisplayName, Modified, Manager, lastLogonDate

if ($updatedUsers.Count -eq 0) {
    Write-Host "No user accounts were updated in the last $Days day(s)." -ForegroundColor Yellow
} else {
    Write-Host "Found $($updatedUsers.Count) user accounts updated in the last $Days day(s):" -ForegroundColor Green
    $updatedUsers |
        Select-Object SamAccountName, DisplayName, whenChanged, whenCreated, Manager |
        Sort-Object whenChanged -Descending |
        Format-Table -AutoSize
}

# Optional: Export results to CSV
$exportPath = "C:\Temp\AD_Users_Updated_Last${Days}Days.csv"
$updatedUsers |
    Select-Object SamAccountName, DisplayName, whenChanged, whenCreated, Manager |
    Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8 -Force

Write-Host "`nResults exported to: $exportPath" -ForegroundColor Cyan
