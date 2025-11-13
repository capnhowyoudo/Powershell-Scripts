<#
.SYNOPSIS
    Displays Active Directory user accounts inactive for a specified number of days.

.DESCRIPTION
    Searches your AD domain for enabled user accounts whose LastLogonDate
    is older than a given number of days. Optionally exports results to C:\Temp\InactiveUsers.csv.

.PARAMETER DaysInactive
    The number of days since last logon to consider a user inactive.

.PARAMETER Export
    Optional switch to export results to C:\Temp\InactiveUsers.csv.

.EXAMPLE
    .\Find-InactiveUsers.ps1 -DaysInactive 90

.EXAMPLE
    .\Find-InactiveUsers.ps1 -DaysInactive 60 -Export
#>

param (
    [Parameter(Mandatory = $true)]
    [int]$DaysInactive,

    [switch]$Export
)

# Ensure AD module
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "❌ The ActiveDirectory module is not installed. Please install RSAT or run on a domain-joined system."
    exit
}

Import-Module ActiveDirectory

# Calculate cutoff date
$CutoffDate = (Get-Date).AddDays(-$DaysInactive)
Write-Host "🔍 Finding users inactive for more than $DaysInactive days (Last logon before $CutoffDate)..." -ForegroundColor Cyan

# Get enabled users from AD and retrieve LastLogonDate
$Users = Get-ADUser -Filter {Enabled -eq $true} -Properties DisplayName, SamAccountName, LastLogonDate, DistinguishedName

# Filter users inactive longer than specified days
$InactiveUsers = $Users | Where-Object {
    $_.LastLogonDate -ne $null -and $_.LastLogonDate -lt $CutoffDate
} | Select-Object DisplayName, SamAccountName, LastLogonDate, DistinguishedName

# Display results
if (-not $InactiveUsers -or $InactiveUsers.Count -eq 0) {
    Write-Host "✅ No user accounts inactive for more than $DaysInactive days were found." -ForegroundColor Green
}
else {
    Write-Host "⚠️ Found $($InactiveUsers.Count) inactive user accounts (>$DaysInactive days)." -ForegroundColor Yellow
    $InactiveUsers | Format-Table DisplayName, SamAccountName, LastLogonDate -AutoSize

    # Export if requested
    if ($Export) {
        $ExportPath = "C:\Temp\InactiveUsers.csv"
        if (-not (Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null }

        $InactiveUsers | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
        Write-Host "📁 Exported results to $ExportPath" -ForegroundColor Cyan
    }
}
