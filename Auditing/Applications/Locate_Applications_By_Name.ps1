<#
This PowerShell script provides a graphical tool (GUI) that lets you search for installed software across all Windows Servers in your Active Directory domain.

It combines a simple Windows Forms interface for user input with remote PowerShell execution on domain servers to scan the registry for matching application names, then displays the results in a visual table.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- 1. GUI Input Form Setup ---

# Create the form
$Form = New-Object System.Windows.Forms.Form
$Form.Text = 'Software Search'
$Form.Size = New-Object System.Drawing.Size(350, 150)
$Form.StartPosition = 'CenterScreen'
$Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$Form.MaximizeBox = $false
$Form.MinimizeBox = $false

# Label for the text box
$Label = New-Object System.Windows.Forms.Label
$Label.Location = New-Object System.Drawing.Point(10, 20)
$Label.Size = New-Object System.Drawing.Size(300, 20)
$Label.Text = 'Enter Application Name (e.g., "Google Chrome"): '
$Form.Controls.Add($Label)

# Text box for application name
$TextBox = New-Object System.Windows.Forms.TextBox
$TextBox.Location = New-Object System.Drawing.Point(10, 45)
$TextBox.Size = New-Object System.Drawing.Size(310, 20)
$Form.Controls.Add($TextBox)

# OK Button
$OKButton = New-Object System.Windows.Forms.Button
$OKButton.Location = New-Object System.Drawing.Point(235, 80)
$OKButton.Size = New-Object System.Drawing.Size(85, 25)
$OKButton.Text = 'Search'
$OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$Form.AcceptButton = $OKButton
$Form.Controls.Add($OKButton)

# Show the form and capture the result
$result = $Form.ShowDialog()

# --- 2. Processing and Execution ---

if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    # Get the search term and trim it
    $ApplicationName = $TextBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($ApplicationName)) {
        [System.Windows.Forms.MessageBox]::Show("Please enter an application name.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        exit
    }
    
    Write-Host "Searching for '$ApplicationName' on all domain servers..."

    # Get all servers in the domain (assuming you have the ActiveDirectory module installed)
    try {
        $Servers = Get-ADComputer -Filter 'OperatingSystem -Like "Windows Server*" -and Enabled -eq $true' -Properties Name | Select-Object -ExpandProperty Name
    }
    catch {
        Write-Error "Failed to retrieve servers from Active Directory. Ensure the ActiveDirectory module is installed and you have permissions."
        exit
    }
    
    if (-not $Servers) {
        Write-Host "No enabled Windows Servers found in Active Directory."
        exit
    }

    $ScriptBlock = {
        param($App)
        # Query two registry paths for installed software using Get-ItemProperty
        # This is more reliable than Win32_Product
        $UninstallPaths = @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )

        $InstalledSoftware = Get-ItemProperty -Path $UninstallPaths -ErrorAction SilentlyContinue |
            Where-Object { 
                # Filter by display name containing the search term
                $_.DisplayName -like "*$App*" 
            } |
            Select-Object @{Name='ApplicationName'; Expression={$_.DisplayName}},
                          @{Name='Version'; Expression={$_.DisplayVersion}},
                          Publisher
        
        return $InstalledSoftware
    }

    # Execute the script block on all servers in parallel using Invoke-Command
    $Results = Invoke-Command -ComputerName $Servers -ScriptBlock $ScriptBlock -ArgumentList $ApplicationName -ErrorAction SilentlyContinue

    # --- 3. Output to GridView ---
    
    if ($Results) {
        # Select and reorder properties, then pipe to Out-GridView
        $Results | Select-Object PSComputerName, ApplicationName, Version, Publisher |
            Out-GridView -Title "Search Results for '$ApplicationName'"
    }
    else {
        [System.Windows.Forms.MessageBox]::Show("No application matching '$ApplicationName' was found on the scanned servers.", "Search Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
}
# Otherwise, the form was closed/cancelled, and the script exits.
