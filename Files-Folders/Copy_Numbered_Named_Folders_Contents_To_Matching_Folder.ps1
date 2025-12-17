<#
.SYNOPSIS
    Copies contents from numbered source folders to matching destination folders and logs the operations.

.DESCRIPTION
    This script iterates through all subfolders in a specified source directory. 
    For each folder that starts with a number, it searches the destination directory recursively 
    for folders that contain the same number. The script then copies all contents from the source 
    folder to each matching destination folder. All copy operations are logged to a CSV file.

.NOTES
    Author: capnhowyoudo
    Date: [2025-12-16]
    Log file: C:\Temp\CopyLog.csv
    The script overwrites existing files in the destination folder.

.EXAMPLES
    # Example of folder matching:
    # Source folder:
    #   C:\Temp\Source\documents\12345678
    #
    # Matching destination folder:
    #   C:\Temp\Destination\documents\Backup\ProjectXYZ\DOC-9876543-12345678_config.conf
    #
    # The script will copy all files from the source folder "12345678" 
    # into the matching destination folder that contains the same number "12345678".    
#>

# Set source and destination root paths
$SourceRoot = "C:\Temp\ABC"
$DestinationRoot = "C:\Temp\ABC\documents"
$LogFile = "C:\Temp\CopyLog.csv"

# Create or clear the log file
if (Test-Path $LogFile) {
    Remove-Item $LogFile
}
# Add headers to the CSV
"SourceFolder,DestinationFolder,DateTime" | Out-File -FilePath $LogFile -Encoding UTF8

# Get all source folders
$SourceFolders = Get-ChildItem -Path $SourceRoot -Directory

foreach ($SourceFolder in $SourceFolders) {

    # Extract the starting number from the source folder name
    if ($SourceFolder.Name -match "^\d+") {
        $NumberPrefix = $matches[0]
    } else {
        # Skip folders that do not start with a number
        continue
    }

    # Find destination folders recursively that contain the full number
    $MatchingDestFolders = Get-ChildItem -Path $DestinationRoot -Directory -Recurse |
        Where-Object { $_.Name -like "*$NumberPrefix*" }

    foreach ($DestFolder in $MatchingDestFolders) {

        Write-Host "Copying from '$($SourceFolder.FullName)' to '$($DestFolder.FullName)'"

        # Copy contents of source folder to the matching destination folder
        Copy-Item -Path "$($SourceFolder.FullName)\*" `
                  -Destination $DestFolder.FullName `
                  -Recurse `
                  -Force

        # Log the operation to CSV
        $LogEntry = "$($SourceFolder.FullName),$($DestFolder.FullName),$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $LogEntry | Out-File -FilePath $LogFile -Append -Encoding UTF8
    }
}

Write-Host "Copying completed. Log saved to $LogFile"
