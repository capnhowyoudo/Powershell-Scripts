<#
.SYNOPSIS
Renames folders by removing everything after the first dot in the folder name recursively.

.DESCRIPTION
This script navigates to a specified folder, iterates through all subdirectories starting from the deepest level, 
and renames each folder by removing any text after the first dot. It can preview changes or actually rename folders
based on the $UseWhatIf variable. Additionally, it logs the original and new folder paths to a CSV file.

.EXAMPLE
Old folder name: "Project.2025.Draft"
New folder name: "Project"
#>

# Navigate to your main folder
Set-Location "C:\Temp\Folder"

# Set this variable to $true to preview changes, $false to actually rename
$UseWhatIf = $false

# Prepare an array to store CSV data
$folderData = @()

# Get all directories recursively, starting from the deepest level
Get-ChildItem -Recurse -Directory | Sort-Object FullName -Descending | ForEach-Object {
    $originalPath = $_.FullName

    # Remove everything after the first dot in the folder name
    $newName = $_.Name.Split('.')[0]

    # Combine with parent directory
    $newPath = Join-Path $_.Parent.FullName $newName

    # Only rename if the new path is different
    if ($originalPath -ne $newPath) {
        if ($UseWhatIf) {
            Rename-Item -Path $originalPath -NewName $newPath -WhatIf
        } else {
            Rename-Item -Path $originalPath -NewName $newPath
        }
    }

    # Add data to array for CSV export
    $folderData += [PSCustomObject]@{
        OriginalPath = $originalPath
        NewPath      = $newPath
    }
}

# Export to CSV
$folderData | Export-Csv -Path "C:\Temp\folder_rename_log.csv" -NoTypeInformation
