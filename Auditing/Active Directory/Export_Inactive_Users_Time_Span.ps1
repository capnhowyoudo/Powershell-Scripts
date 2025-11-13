<#
.SYNOPSIS
    Finds and exports Active Directory user accounts inactive for more than a specified number of days.

.DESCRIPTION
    This script searches your AD domain for enabled user accounts whose LastLogonDate
    is older than the given number of days. It always exports results to C:\Temp\InactiveUsers.csv.

.PARAMETER DaysInactive
    The number of days since last logon to consider a user inactive.

.EXAMPLE
    .\Find-InactiveUsers.ps1 -DaysInactive 90
#>

param (
    [Parameter(Mandatory = $true)]
    [int]$DaysInactive
)

# Verify AD module
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "❌ The ActiveDirectory module is not installed. Please install RSAT or run this on a domain-joined system."
    exit
}

Import-Module ActiveDirectory

# Define export path
$ExportPath = "C:\Temp\InactiveUsers.csv"
$ExportDir = Split-Path $ExportPath
if (-not (Test-Path $ExportDir)) {
    New-Item -ItemType Directory -Path $ExportDir -Force | Out-Null
    Write-Host "📁 Created missing directory: $ExportDir" -ForegroundColor Yellow
}

# Calculate cutoff date
$CutoffDate = (Get-Date).AddDays(-$DaysInactive)
Write-Host "🔍 Searching for users inactive for more than $DaysInactive days (before $CutoffDate)..." -ForegroundColor Cyan

# Get enabled users from AD and retrieve LastLogonDate
$Users = Get-ADUser -Filter {Enabled -eq $true} -Properties DisplayName, SamAccountName, LastLogonDate, DistinguishedName

# Filter users inactive longer than specified days
$InactiveUsers = $Users | Where-Object {
    $_.LastLogonDate -ne $null -and $_.LastLogonDate -lt $CutoffDate
} | Select-Object DisplayName, SamAccountName, LastLogonDate, DistinguishedName

# Display and export results
if (-not $InactiveUsers -or $InactiveUsers.Count -eq 0) {
    Write-Host "✅ No user accounts inactive for more than $DaysInactive days were found." -ForegroundColor Green
} else {
    Write-Host "⚠️ Found $($InactiveUsers.Count) inactive user account(s) (> $DaysInactive days)." -ForegroundColor Yellow
    $InactiveUsers | Format-Table DisplayName, SamAccountName, LastLogonDate -AutoSize

    try {
        $InactiveUsers | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
        Write-Host "📦 Exported results to $ExportPath" -ForegroundColor Cyan
    } catch {
        Write-Error "❌ Failed to export results: $_"
    }
}
