<#
.SYNOPSIS
Retrieves a specific registry value from a given registry path.

.DESCRIPTION
The Get-RegValue function queries the Windows Registry for a specific key and value. 
It returns a custom object containing the registry path, the value name, and the value itself. 
If the value does not exist, it returns "Not Found". This script queries .NET Framework and TLS 
settings across both 32-bit and 64-bit registry paths for all installed versions of .NET and TLS protocols.

.NOTES
Requires    : PowerShell 3.0 or higher
Usage       : Call Get-RegValue with a registry path and value name.
             Example: Get-RegValue 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' 'SchUseStrongCrypto'
#>

function Get-RegValue {
    [CmdletBinding()]
    Param
    (
        # Registry Path
        [Parameter(Mandatory = $true,
                   Position = 0)]
        [string]
        $RegPath,

        # Registry Value Name
        [Parameter(Mandatory = $true,
                   Position = 1)]
        [string]
        $RegName
    )

    $regItem = Get-ItemProperty -Path $RegPath -Name $RegName -ErrorAction Ignore
    $output = "" | Select-Object Path, Name, Value
    $output.Path = $RegPath
    $output.Name = $RegName

    if ($null -eq $regItem) {
        $output.Value = "Not Found"
    }
    else {
        $output.Value = $regItem.$RegName
    }

    return $output
}

# ---------------------------
# Query .NET Framework Registry Settings
# ---------------------------
$regSettings = @()

$netKeys = @(
    'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319',
    'HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v2.0.50727'
)

foreach ($regKey in $netKeys) {
    $regSettings += Get-RegValue $regKey 'SystemDefaultTlsVersions'
    $regSettings += Get-RegValue $regKey 'SchUseStrongCrypto'
}

# ---------------------------
# Query TLS Protocol Registry Settings
# ---------------------------
$tlsKeys = @(
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Server',
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Client',
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server',
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client',
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server',
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client',
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server',
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client'
)

foreach ($regKey in $tlsKeys) {
    $regSettings += Get-RegValue $regKey 'Enabled'
    $regSettings += Get-RegValue $regKey 'DisabledByDefault'
}

# Output results
$regSettings
