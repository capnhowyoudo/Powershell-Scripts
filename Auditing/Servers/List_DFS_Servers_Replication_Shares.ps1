<#
.SYNOPSIS
Performs a domain-wide DFS Namespace and DFS Replication audit and exports the results to CSV.

.DESCRIPTION
This script audits Distributed File System (DFS) across an Active Directory domain. It automatically verifies and installs required management tools (DFSN, DFSR, and ActiveDirectory RSAT modules), then performs the following tasks:

- Enumerates all domain-based DFS Namespaces, folders, and folder targets
- Collects namespace target state, referral priority, and hosting server
- Enumerates DFS Replication Groups and replicated folders
- Calculates DFSR backlog counts between replication members where possible
- Identifies replication health, offline targets, and access issues

All findings are consolidated into a single CSV report and optionally displayed in an interactive grid view for review.

.NOTES
1. This script must be run with sufficient privileges:
   - Domain User (minimum) for namespace enumeration
   - Domain Admin or delegated DFS permissions for replication backlog checks
2. The script automatically installs required RSAT tools if they are missing:
   - On Windows Server: installs Windows Features
   - On Windows Client: installs Windows Capabilities
3. PowerShell must be run **as Administrator** to allow tool installation.
4. Output file:
   - Default path: C:\temp\DFS_Domain_Wide_Audit.csv
   - The folder will be created automatically if it does not exist.
5. The CSV output includes:
   Category, GroupName, Member_Folder, Target_Path, Status_State,
   Backlog_Count, Details, ServerChecked
6. Backlog counts may show:
   - Numeric values (successful query)
   - "Offline/No Access" (target unavailable or permission issue)
   - "Error/Access Denied" (DFSR query failure)
7. This script is intended for auditing, troubleshooting, documentation,
   and health assessment of DFS environments.
#>

# --- 1. Check and Install DFS & AD Tools ---
Write-Host "Checking for Required Management Tools..." -ForegroundColor Cyan

$isServer = (Get-CimInstance Win32_OperatingSystem).Caption -match "Server"

# Check for DFS and Active Directory modules
$requiredModules = @("DFSN", "DFSR", "ActiveDirectory")
foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Host "$mod Tools missing. Attempting installation..." -ForegroundColor Yellow
        try {
            if ($isServer) {
                Install-WindowsFeature RSAT-DFS-Mgmt-Con, RSAT-AD-PowerShell -IncludeManagementTools -ErrorAction Stop
            } else {
                Add-WindowsCapability -Online -Name Rsat.FileServices.Tools~~~~0.0.1.0 -ErrorAction Stop
                Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0 -ErrorAction Stop
            }
            Import-Module $mod -ErrorAction SilentlyContinue
        } catch {
            Write-Error "Failed to install tools. Please run PowerShell as Administrator."
            return
        }
    }
}

# --- 2. Define Audit Paths ---
$csvPath = "C:\temp\DFS_Domain_Wide_Audit.csv"
if (-not (Test-Path "C:\temp")) { New-Item -Path "C:\temp" -ItemType Directory }
$report = New-Object System.Collections.Generic.List[PSObject]

# --- 3. Get All Servers in the Domain ---
Write-Host "Fetching list of servers from Active Directory..." -ForegroundColor Cyan
try {
    $allServers = Get-ADComputer -Filter 'OperatingSystem -like "*Server*"' -Properties OperatingSystem | Select-Object -ExpandProperty Name
    Write-Host "Found $($allServers.Count) servers to check." -ForegroundColor Gray
} catch {
    Write-Error "Failed to query Active Directory. Ensure you are logged in with domain credentials."
    return
}

# --- 4. Domain-Wide Namespace Audit ---
Write-Host "Querying Namespaces across the domain..." -ForegroundColor Cyan

try {
    # Get-DfsnRoot without parameters usually finds all domain-based namespaces
    $namespaces = Get-DfsnRoot
    foreach ($root in $namespaces) {
        $folders = Get-DfsnFolder -Path "$($root.Path)\*" -ErrorAction SilentlyContinue
        foreach ($folder in $folders) {
            $targets = Get-DfsnFolderTarget -Path $folder.Path
            foreach ($target in $targets) {
                $report.Add([PSCustomObject]@{
                    Category      = "Namespace"
                    GroupName     = $root.Path
                    Member_Folder = $folder.Path
                    Target_Path   = $target.TargetPath
                    Status_State  = $target.State
                    Backlog_Count = "N/A"
                    Details       = "Priority: $($target.ReferralPriorityClass)"
                    ServerChecked = $target.TargetPath.Split('\')[2] # Extracts server name from UNC
                })
            }
        }
    }
} catch { Write-Warning "Namespace query failed." }

# --- 5. Replication & Backlog Audit ---
Write-Host "Querying Replication Groups and Backlogs..." -ForegroundColor Cyan

try {
    $repGroups = Get-DfsrReplicationGroup
    foreach ($group in $repGroups) {
        $members = Get-DfsrMember -GroupName $group.GroupName
        $folders = Get-DfsrReplicatedFolder -GroupName $group.GroupName

        foreach ($folder in $folders) {
            $source = $members[0].ComputerName
            foreach ($dest in $members) {
                if ($source -ne $dest.ComputerName) {
                    $backlogCount = "Error/Access Denied"
                    try {
                        $backlog = Get-DfsrBacklog -GroupName $group.GroupName `
                                                   -FolderName $folder.ReplicatedFolderName `
                                                   -SourceComputerName $source `
                                                   -DestinationComputerName $dest.ComputerName `
                                                   -ErrorAction Stop
                        $backlogCount = if ($null -ne $backlog) { $backlog.Count } else { 0 }
                    } catch { 
                        $backlogCount = "Offline/No Access"
                    }
                    
                    $report.Add([PSCustomObject]@{
                        Category      = "Replication"
                        GroupName     = $group.GroupName
                        Member_Folder = $folder.ReplicatedFolderName
                        Target_Path   = $dest.ComputerName
                        Status_State  = "Syncing from $source"
                        Backlog_Count = $backlogCount
                        Details       = "Backlog check complete"
                        ServerChecked = $dest.ComputerName
                    })
                }
            }
        }
    }
} catch { Write-Warning "Replication query failed. Ensure you have Domain Admin rights." }

# --- 6. Export and Output ---
$report | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "Domain-Wide Audit Complete! File saved to: $csvPath" -ForegroundColor Green
$report | Out-GridView -Title "Domain-Wide DFS Master Audit"
