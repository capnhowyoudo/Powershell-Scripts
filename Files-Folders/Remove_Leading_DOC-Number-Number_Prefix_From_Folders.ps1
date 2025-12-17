<#
.SYNOPSIS
Removes a leading "DOC-<number>-<number>" prefix from directory names and logs the changes to a CSV file.

.DESCRIPTION
This script recursively scans all directories under a specified source path.
If a directory name starts with the pattern "DOC-<digits>-<digits>", that prefix
is removed and the folder is renamed. Each rename operation is recorded,
including the original full path, old name, and new name, and exported to a CSV file.

.NOTES
PREVIEW-ONLY MODE:
To test this script without making any changes to the filesystem,
temporarily remove or comment out the following line:

    Rename-Item -Path $_.FullName -NewName $newName

When that line is removed, the script will only calculate and log the
proposed new names to the CSV file without renaming any folders.

.EXAMPLE
If you have a directory named:

    DOC-12345-67890 ProjectName_1-0_0012_202512161200

Running the script will rename it to:

    ProjectName_1-0_0012_202512161200

This shows the prefix "DOC-12345-67890" being removed while keeping the rest of the folder name intact.

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
