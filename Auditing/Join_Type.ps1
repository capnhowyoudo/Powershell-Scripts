<#
.SYNOPSIS
    Identifies the directory membership status of the local workstation.

.DESCRIPTION
    This script evaluates whether the computer is joined to a traditional On-Premises Active Directory domain, 
    Microsoft Entra ID (Azure AD), or remains in a Workgroup. It parses both WMI data and 'dsregcmd' 
    output to provide a consolidated view of the machine's identity state and associated names.
#>

# 1. Get Domain and Workgroup Information from WMI/CIM
$computerSystem = Get-CimInstance Win32_ComputerSystem
$isDomainJoined = $computerSystem.PartOfDomain
$domainName = if ($isDomainJoined) { $computerSystem.Domain } else { "N/A" }
$workgroupName = if (-not $isDomainJoined) { $computerSystem.Workgroup } else { "N/A" }

# 2. Get Azure AD / Entra ID Information via dsregcmd
$dsregRaw = dsregcmd /status | Out-String
$isAzureJoined = $dsregRaw -match "AzureAdJoined : YES"
$isHybridJoined = ($dsregRaw -match "DomainJoined : YES") -and $isAzureJoined
$tenantName = if ($dsregRaw -match "TenantName : (.*)") { $Matches[1].Trim() } else { "N/A" }

# 3. Logic to determine the primary identity state
$joinType = "Workgroup"
if ($isHybridJoined) { 
    $joinType = "Entra ID (Azure AD) Hybrid Joined" 
} elseif ($isAzureJoined) { 
    $joinType = "Entra ID (Azure AD) Joined" 
} elseif ($isDomainJoined) { 
    $joinType = "On-Premises Domain Joined" 
}

# 4. Construct and Output the result object
[PSCustomObject]@{
    ComputerName = $env:COMPUTERNAME
    JoinType     = $joinType
    DomainName   = $domainName
    EntraTenant  = $tenantName
    Workgroup    = $workgroupName
} | Format-List
