<#
.SYNOPSIS
Combines multiple CSV files from a folder into a single Excel workbook, each CSV in its own sheet.

.DESCRIPTION
This script scans a target folder for all CSV files and creates a new Excel workbook where each CSV 
file is imported into a separate worksheet. The worksheet names match the original CSV file names.

The output Excel file is named using the current date and the username in the format:
YYYYMMDD_USERNAME_combined-data.xlsx. 

This script uses the Excel COM object and requires Excel to be installed on the system. It is 
useful for consolidating multiple CSV reports into a single Excel file for easier analysis.

.NOTES
File Name   : Combine_CSVs_To_Excel.ps1
Author      : capnhowyoudo
Date        : 2025-11-13
Requires    : PowerShell 3.0+, Microsoft Excel installed
Usage       : 
    - Modify the $path variable to point to your folder containing CSV files
    - Run the script:
        .\Combine_CSVs_To_Excel.ps1
Limitations : 
    - Only CSV files in the specified folder are processed.
    - Worksheet names are limited by Excel's maximum sheet name length.
    - Excel COM object may remain in memory if script is interrupted.
Source      : https://stackoverflow.com/questions/49324636/multiple-csv-files-into-a-xlsx-file-but-different-sheets-using-powershell
#>

# Set target folder
$path="c:\path\to\folder" # Modify this path to your folder
cd $path

# Get all CSV files in the folder
$csvs = Get-ChildItem .\* -Include *.csv
$y = $csvs.Count
Write-Host "Detected the following CSV files: ($y)"
foreach ($csv in $csvs) {
    Write-Host " "$csv.Name
}

# Create output filename with date and username
$outputfilename = $(Get-Date -f yyyyMMdd) + "_" + $env:USERNAME + "_combined-data.xlsx"
Write-Host "Creating: $outputfilename"

# Create new Excel application and workbook
$excelapp = New-Object -ComObject Excel.Application
$excelapp.sheetsInNewWorkbook = $csvs.Count
$xlsx = $excelapp.Workbooks.Add()
$sheet = 1

# Import each CSV into a separate worksheet
foreach ($csv in $csvs) {
    $row = 1
    $column = 1
    $worksheet = $xlsx.Worksheets.Item($sheet)
    $worksheet.Name = $csv.BaseName

    $file = Get-Content $csv
    foreach ($line in $file) {
        $linecontents = $line -split ',(?!\s*\w+")'
        foreach ($cell in $linecontents) {
            $worksheet.Cells.Item($row, $column) = $cell
            $column++
        }
        $column = 1
        $row++
    }
    $sheet++
}

# Save the workbook and clean up
$output = Join-Path $path $outputfilename
$xlsx.SaveAs($output)
$excelapp.Quit()
cd \  # Return to drive root

Write-Host "Excel workbook created at: $output" -ForegroundColor Green
