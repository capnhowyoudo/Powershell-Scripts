<#
This PowerShell script scans Active Directory (AD) and Group Policy Objects (GPOs) to find all logon scripts used in your domain, then exports a detailed report to a CSV file.

It’s a very useful AD audit and cleanup tool, helping administrators locate where user logon scripts are defined—whether they’re assigned directly to users in AD or through GPOs.
#>


# Create export folder if not exists
$exportPath = "C:\Temp\LogonScriptReport.csv"
$exportDir = Split-Path $exportPath
If (!(Test-Path $exportDir)) {
    New-Item -Path $exportDir -ItemType Directory | Out-Null
}

# Import required modules
Import-Module ActiveDirectory
Import-Module GroupPolicy

# Get the domain info for building full paths
$domain = (Get-ADDomain).DNSRoot
$sysvolPath = "\\$domain\SYSVOL\$domain\scripts"

# Initialize results array
$results = @()

### --- Search AD Users for Logon Scripts ---
$ADUsers = Get-ADUser -Filter {scriptPath -like "*"} -Properties scriptPath, DistinguishedName |
    Where-Object { $_.scriptPath -ne $null }

foreach ($user in $ADUsers) {
    $scriptFile = $user.scriptPath
    $fullPath = Join-Path $sysvolPath $scriptFile

    $results += [PSCustomObject]@{
        Source        = "ActiveDirectory"
        Name          = $user.Name
        Identifier    = $user.SamAccountName
        ScriptPath    = $scriptFile
        FullPath      = $fullPath
        Location      = $user.DistinguishedName
    }
}

### --- Search GPOs for Logon Scripts ---
$allGPOs = Get-GPO -All

foreach ($gpo in $allGPOs) {
    $report = Get-GPOReport -Guid $gpo.Id -ReportType Xml
    $xml = [xml]$report

    $logonScripts = $xml.GPO.User.ExtensionData.Extension.Script | Where-Object { $_.Type -eq 'Logon' }

    if ($logonScripts) {
        foreach ($script in $logonScripts.Script) {
            $scriptFile = $script.Command
            $fullPath = Join-Path $sysvolPath $scriptFile

            $results += [PSCustomObject]@{
                Source        = "GPO"
                Name          = $gpo.DisplayName
                Identifier    = $gpo.Id
                ScriptPath    = $scriptFile
                FullPath      = $fullPath
                Location      = $gpo.Path
            }
        }
    }
}

### --- Export to CSV ---
if ($results.Count -gt 0) {
    $results | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
    Write-Host "Logon script report exported to $exportPath"
} else {
    Write-Host "No logon scripts found in AD or any GPOs."
}
