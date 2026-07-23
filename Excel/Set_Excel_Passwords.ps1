<#
.SYNOPSIS
    Batch-applies an open (workbook) password to every .xlsx/.xlsm file in a folder.

.DESCRIPTION
    Uses Excel's COM automation, so Microsoft Excel must be installed on this machine.
    Each file is opened, a password is set via Workbook.Password, and the file is
    re-saved in place (or to an output folder if -OutputFolder is specified). 
	Set Execution Policy may need to be ran if runnins scripts is disabled. 
	
	Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.PARAMETER FolderPath
    Folder containing the .xlsx/.xlsm files to protect.

.PARAMETER Password
    The password to apply to every file. If you want a different password per file,
    see the CSV-based variant in the comments at the bottom of this script.

.PARAMETER OutputFolder
    Optional. If provided, protected copies are saved here instead of overwriting
    the originals. The folder is created if it doesn't exist.

.EXAMPLE
    .\Set_Excel_Passwords.ps1 -FolderPath "C:\Reports" -Password "Sup3rSecret!"

.EXAMPLE
    .\Set_Excel_Passwords.ps1 -FolderPath "C:\Reports" -Password "Sup3rSecret!" -OutputFolder "C:\Reports\Protected"
	
.EXAMPLE
 	Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; .\Set_Excel_Passwords.ps1 -FolderPath "C:\Reports" -Password "Sup3rSecret!" -OutputFolder "C:\Reports\Protected"
	
.EXAMPLE
	Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; .\Set_Excel_Passwords.ps1 -FolderPath "C:\Reports" -Password "Sup3rSecret!"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$FolderPath,

    [Parameter(Mandatory = $true)]
    [string]$Password,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder
)

# --- Validate inputs ---
if (-not (Test-Path $FolderPath)) {
    Write-Error "Folder not found: $FolderPath"
    exit 1
}

if ($OutputFolder -and -not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}

$files = Get-ChildItem -Path $FolderPath -Include *.xlsx, *.xlsm -Recurse -File
if ($files.Count -eq 0) {
    Write-Warning "No .xlsx or .xlsm files found in $FolderPath"
    exit 0
}

Write-Host "Found $($files.Count) file(s). Starting Excel..." -ForegroundColor Cyan

function New-ExcelInstance {
    $app = New-Object -ComObject Excel.Application
    $app.Visible = $false
    $app.DisplayAlerts = $false
    $app.Interactive = $false
    $app.AskToUpdateLinks = $false
    $app.EnableEvents = $false
    return $app
}

function Close-ExcelInstance($app) {
    try {
        $app.Quit()
    } catch {}
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($app) | Out-Null
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}

function Protect-OneFile($app, $file, $password, $outputFolder) {
    $workbook = $null
    try {
        $workbook = $app.Workbooks.Open($file.FullName)
        $workbook.Password = $password

        if ($outputFolder) {
            $destPath = Join-Path $outputFolder $file.Name
            $workbook.SaveAs($destPath)
        }
        else {
            $workbook.Save()
        }

        $workbook.Close($false)
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($workbook) | Out-Null
        $workbook = $null
        return $true
    }
    catch {
        if ($workbook) {
            try { $workbook.Close($false) } catch {}
            try { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($workbook) | Out-Null } catch {}
        }
        throw
    }
}

$excel = New-ExcelInstance

$successCount = 0
$failCount = 0

foreach ($file in $files) {
    Write-Host "Processing: $($file.Name)" -NoNewline

    try {
        Protect-OneFile -app $excel -file $file -password $Password -outputFolder $OutputFolder | Out-Null
        Write-Host "  -> Done" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host "  -> FAILED (attempt 1): $($_.Exception.Message)" -ForegroundColor Yellow

        # Excel COM connection likely got into a bad state (e.g. RPC_E_CALL_REJECTED /
        # RPC_E_DISCONNECTED). Kill this instance, spin up a fresh one, and retry once.
        Close-ExcelInstance $excel
        Start-Sleep -Seconds 2
        $excel = New-ExcelInstance

        try {
            Protect-OneFile -app $excel -file $file -password $Password -outputFolder $OutputFolder | Out-Null
            Write-Host "     Retry succeeded" -ForegroundColor Green
            $successCount++
        }
        catch {
            Write-Host "     Retry FAILED: $($_.Exception.Message)" -ForegroundColor Red
            $failCount++
        }
    }

    # Brief pause between files gives Excel's COM server a moment to settle.
    Start-Sleep -Milliseconds 500
}

# --- Clean up Excel COM object ---
Close-ExcelInstance $excel

Write-Host "`nComplete: $successCount succeeded, $failCount failed." -ForegroundColor Cyan

<#
--- VARIANT: different password per file, driven by a CSV ---
If you need a unique password per file instead of one password for all,
use a CSV like:

    FileName,Password
    Report1.xlsx,Alpha123!
    Report2.xlsx,Beta456!

...and replace the foreach loop above with something like:

    $map = Import-Csv "C:\passwords.csv"
    foreach ($row in $map) {
        $path = Join-Path $FolderPath $row.FileName
        $workbook = $excel.Workbooks.Open($path)
        $workbook.Password = $row.Password
        $workbook.Save()
        $workbook.Close($false)
    }
#>
