<#
.SYNOPSIS
Removes a leading "DOC-<number>-<number>" prefix from directory names and logs the changes to a CSV file.

.DESCRIPTION
This script recursively scans all directories under a specified source path.
If a directory name starts with the pattern "DOC-<digits>-<digits>", that prefix
is removed and the folder is renamed. Each rename operation is recorded,
including the original full path, old name, and new name, and exported to a CSV file.
#>

$sourcePath = "C:\Your\Source\Folder\Here"
$csvPath    = "C:\Temp\RenameResults.csv"

$results = @()

Get-ChildItem -Path $sourcePath -Directory -Recurse | ForEach-Object {
    if ($_.Name -match '^DOC-\d+-\d+\s*') {
        $oldName = $_.Name
        $newName = $_.Name -replace '^DOC-\d+-\d+\s*', ''

        Rename-Item -Path $_.FullName -NewName $newName

        $results += [PSCustomObject]@{
            FullPathBefore = $_.FullName
            OldName        = $oldName
            NewName        = $newName
        }
    }
}

$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
