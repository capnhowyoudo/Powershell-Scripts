<#
.SYNOPSIS
   Trims a specified number of characters from the beginning of folder names in the current directory.

.DESCRIPTION
   This script loops through all directories in the current folder and removes a defined number of characters
   from the start of each folder name. It is useful for cleaning up folder names that contain unwanted prefixes.
   The script includes safety checks to ensure folder names are long enough before renaming.
   By default, the script uses Write-Host to show the proposed changes and includes a -WhatIf parameter for safety.
   Remove -WhatIf to apply the changes.

.NOTES
   Author: capnhowyoudo
   - $charsToRemove controls how many characters are removed from the start of each folder name.
   - Only folders (directories) are renamed; files are ignored.
   - Folders shorter than the specified number of characters are skipped.
   - Example: If $charsToRemove = 20 and a folder name is "2025-Project-Files-Important", the new name will be "Files-Important".
   - Safety: The script initially shows proposed changes with Write-Host and -WhatIf. Remove -WhatIf to execute renaming.
   - Usage:
       1. Open PowerShell.
       2. Navigate to the directory containing the folders you want to rename:
           cd "C:\Path\To\Folders"
       3. Run the script:
           .\Remove_Characters_From_Folders.ps1
       4. To actually perform the rename, remove the `-WhatIf` in the `Rename-Item` line.
   - Optional: Modify $charsToRemove at the top of the script to change the number of characters removed.
#>

# Define how many characters you want to remove
$charsToRemove = 20

# Get all directories (folders) in the current path
# The -Directory parameter ensures we only select folders
Get-ChildItem -Directory | ForEach-Object {
    # Get the original folder name
    $originalName = $_.Name
    
    # Check if the name is long enough
    if ($originalName.Length -gt $charsToRemove) {
        
        # Create the new name by removing the first $charsToRemove characters
        $newName = $originalName.Substring($charsToRemove)
        
        # Perform the actual rename operation
        # Use -WhatIf for safety first. Remove -WhatIf to execute the rename.
        Rename-Item -Path $_.FullName -NewName $newName -WhatIf
        
        # Optional output to show the change
        Write-Host "Would rename: '$originalName' to '$newName'"
        
    } else {
        Write-Host "Skipping: '$originalName' (Name is too short to remove $charsToRemove characters)."
    }
}
