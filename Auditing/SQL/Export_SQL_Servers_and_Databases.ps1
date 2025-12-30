<#
This PowerShell script is a comprehensive SQL Server inventory tool designed to automatically discover SQL Server instances across your network, collect detailed information about each instance and its databases, and export that information to a CSV file on your desktop.

It includes self-checking for required modules, automatic installation of missing dependencies, and robust error handling for discovery and connection failures.
#>

# --- Configuration ---
# Define the output file path. This saves the CSV file to the current user's Desktop.
$OutputPath = "$([Environment]::GetFolderPath('Desktop'))\SqlInventory_Detailed.csv"
# ---------------------

## Function to check if a module is installed and install it if missing
function Check-And-Install-Module {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ModuleName
    )

    Write-Host "Checking for PowerShell module: '$ModuleName'..." -ForegroundColor Cyan

    # Check if the module is available
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Host "Module '$ModuleName' not found. Attempting installation." -ForegroundColor Yellow
        
        try {
            # Install the module for the current user only
            Install-Module -Name $ModuleName -Scope CurrentUser -Force -Confirm:$false -AllowClobber
            Write-Host "Successfully installed module '$ModuleName'." -ForegroundColor Green
            
            # Since the module was just installed, we need to explicitly import it
            Import-Module $ModuleName -ErrorAction Stop
        } catch {
            Write-Error "Failed to install module '$ModuleName'. Please check your PowerShell Gallery (PSGallery) connection and permissions. Error: $($_.Exception.Message)"
            # Exit script if critical module (SqlServer) fails to install
            if ($ModuleName -eq 'SqlServer') { exit 1 } 
        }
    } else {
        Write-Host "Module '$ModuleName' is already installed. Importing..." -ForegroundColor Green
        # Ensure the module is loaded into the current session
        Import-Module $ModuleName -ErrorAction SilentlyContinue
    }
}


# Function to discover SQL Servers and list their databases
function Get-SqlServersAndDatabases {
    param(
        [string[]]$ServerList = $null
    )
    
    # Discovery logic remains the same (via SQL Browser service)
    if (-not $ServerList) {
        Write-Host "Discovering SQL Server instances on the network..." -ForegroundColor Cyan
        try {
            # Use .NET class for instance discovery
            $ServerInstances = [System.Data.Sql.SqlDataSourceEnumerator]::Instance.GetDataSources() | 
                Select-Object @{Name='InstanceName'; Expression={
                    if ($_.InstanceName) {
                        "$($_.ServerName)\$($_.InstanceName)"
                    } else {
                        $_.ServerName
                    }
                }} -Unique
            
            $ServerList = $ServerInstances.InstanceName
        } catch {
            Write-Error "Failed to discover SQL instances. You may need to provide a list of servers."
            return @()
        }
    }

    $Results = @()

    foreach ($InstanceName in $ServerList) {
        Write-Host "Connecting to instance: $($InstanceName)" -ForegroundColor Yellow
        
        try {
            # --- Get Instance-Level Details (SQL Version) ---
            # Get-SqlInstance is used to retrieve version information efficiently.
            $Instance = Get-SqlInstance -ServerInstance $InstanceName -ErrorAction Stop
            $SqlVersion = $Instance.Version
            # ------------------------------------------------

            # Get the databases for the current instance.
            $Databases = Get-SqlDatabase -ServerInstance $InstanceName -ErrorAction SilentlyContinue
            
            if ($Databases) {
                foreach ($DB in $Databases) {
                    
                    # --- Logic to Capture Database File Locations ---
                    # FileGroups property contains the data and log file paths.
                    $FileLocations = @()
                    foreach ($File in $DB.FileGroups.Files) {
                        $FileLocations += $File.FileName
                    }
                    # Join all file paths into a single string
                    $LocationString = $FileLocations -join "; "
                    # ------------------------------------------------
                    
                    # Create the final custom object with all details
                    $Results += [PSCustomObject]@{
                        ServerInstance  = $InstanceName
                        SqlVersion      = $SqlVersion         # ADDED: SQL Server Version
                        DatabaseName    = $DB.Name
                        Owner           = $DB.Owner
                        Compatibility   = $DB.CompatibilityLevel
                        SizeMB          = [math]::Round($DB.Size, 2)
                        RecoveryModel   = $DB.RecoveryModel
                        Status          = $DB.Status
                        DatabaseLocation= $LocationString     # ADDED: Physical File Path
                    }
                }
            } else {
                Write-Host "Could not retrieve databases from $($InstanceName) or no databases found." -ForegroundColor Red
            }
        } catch {
            Write-Warning "Could not connect to or query $($InstanceName). Error: $($_.Exception.Message)"
        }
    }
    
    return $Results
}

# --- Main Script Execution ---

# 1. Check and install necessary modules
Check-And-Install-Module -ModuleName 'SqlServer'
Check-And-Install-Module -ModuleName 'dbatools'

# 2. Run the inventory function
Write-Host "Starting SQL Database Inventory..." -ForegroundColor Green
$SqlData = Get-SqlServersAndDatabases

# 3. Export data to CSV
if ($SqlData) {
    # Export the custom objects to the specified CSV path.
    $SqlData | Export-Csv -Path $OutputPath -NoTypeInformation -Force
    
    Write-Host ""
    Write-Host "✅ Success: Inventory complete!" -ForegroundColor Green
    Write-Host "Data exported to: $($OutputPath)" -ForegroundColor Green
} else {
    Write-Host "❌ Failed: No SQL Servers or Databases were successfully retrieved to export." -ForegroundColor Red
}
