<#
.SYNOPSIS
Automates the provisioning and configuration of a new Windows workstation.

.DESCRIPTION
This script performs a full setup routine for a Windows 10 machine. It begins by
ensuring the script is elevated to Administrator privileges, then configures
system power settings, removes default Windows bloatware applications, installs
Chocolatey, and deploys multiple commonly-used applications such as Chrome, Firefox,
Adobe Reader, Java, and Office 365.

The script also applies a custom Start Menu and Taskbar layout, sets Windows file
association defaults, installs the NuGet provider, applies available Windows Updates,
and provides a GUI that allows the administrator to rename the workstation and
optionally restart or shut down the system afterward.

This script is designed for IT environments to streamline workstation deployment
and ensure consistent configuration across machines.

.NOTES
Author: capnhowyoudo  
Version: 6.0  
Original Release Date: 03/24/2021  
Requirements:  
 - Must be run as Administrator  
 - Requires internet access to install Chocolatey packages  
 - Designed for Windows 10  
 - Chocolatey installs applications silently using -y flag  
 - Start layout modifications apply to new user profiles only  

APPLICATION INSTALLATION:
- Applications installed through Chocolatey are located in the section labeled:
     ########################
     # Install Applications #
     ########################

  To ADD or REMOVE software:
  - Modify or comment out these lines:
        choco install googlechrome -y
        choco install firefox -y
        choco install adobereader -y
        choco install jre8 -y
        choco install silverlight -y
        choco install office365business -y

  Add new applications by inserting additional:
        choco install <packageName> -y

WINDOWS 10 BLOATWARE REMOVAL:
- Apps removed are controlled in the section labeled:
     ####################################
     # Remove Windows 10 Bloatware Apps #
     ####################################

  To STOP removing a specific app:
  - Comment out its line. Example:
        # Get-AppxPackage -allusers Microsoft.SkypeApp* | Remove-AppxPackage

  To ADD more apps to remove:
  - Insert additional lines using:
        Get-AppxPackage -allusers <AppNamePattern>* | Remove-AppxPackage

WINDOWS UPDATE CONTROL:
- Windows Updates are performed in the section labeled:
     ###############################################
     # Check for and Install Windows updates       #
     ###############################################

  Updates are enabled by these lines:
        Install-Module PSWindowsUpdate -Repository PSGallery -Force
        Get-WindowsUpdate -AcceptAll -Download -Install -AutoReboot

  To DISABLE updates:
  - Comment out both lines:
        # Install-Module PSWindowsUpdate -Repository PSGallery -Force
        # Get-WindowsUpdate -AcceptAll -Download -Install -AutoReboot

  To ENABLE updates:
  - Ensure both lines are UNCOMMENTED.

NOTES ABOUT START MENU & DEFAULT APPS:
- Start menu layout modifications are located in:
        #Add new layoutmodification Start Menu…
  Editing XML allows you to adjust tiles or taskbar pins.

- Default application associations are controlled in:
        ############################
        # Set Default Applications #
        ############################

#>

########################
# Run Script as Admin  #
########################

param([switch]$Elevated)
function Check-Admin {
$currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
$currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
if ((Check-Admin) -eq $false) {
if ($elevated)
{
# could not elevate, quit
}
else {
Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))
}
exit
}

#########################
# Change Power Settings #
#########################

POWERCFG -Change -monitor-timeout-ac 15
POWERCFG -CHANGE -monitor-timeout-dc 15
POWERCFG -CHANGE -disk-timeout-ac 0
POWERCFG -CHANGE -disk-timeout-dc 0
POWERCFG -CHANGE -standby-timeout-ac 60
POWERCFG -CHANGE -standby-timeout-dc 60
POWERCFG -CHANGE -hibernate-timeout-ac 0
POWERCFG -CHANGE -hibernate-timeout-dc 0

####################################
# Remove Windows 10 Bloatware Apps #
####################################

Get-AppxPackage -allusers Microsoft.ScreenSketch* | Remove-AppxPackage
Get-AppxPackage -allusers Microsoft.SkypeApp* | Remove-AppxPackage
Get-AppxPackage -allusers Microsoft.Microsoft3DViewer* | Remove-AppxPackage
Get-AppxPackage -allusers Microsoft.MicrosoftOfficeHub* | Remove-AppxPackage
Get-AppxPackage -allusers Microsoft.MicrosoftSolitaireCollection* | Remove-AppxPackage
Get-AppxPackage -allusers Microsoft.ZuneMusic* | Remove-AppxPackage
Get-AppxPackage -allusers Microsoft.ZuneVideo* | Remove-AppxPackage
Get-AppxPackage -allusers Microsoft.Xbox.TCUI* | Remove-AppxPackage
Get-AppxPackage -allusers Microsoft.XboxApp* | Remove-AppxPackage
Get-AppxPackage -allusers Microsoft.XboxGameOverlay* | Remove-AppxPackage
Get-AppxPackage -allusers Microsoft.XboxGamingOverlay* | Remove-AppxPackage
Get-AppxPackage -allusers Microsoft.XboxIdentityProvider* | Remove-AppxPackage

#######################
# Install Chocolatey  #
#######################

Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

########################
# Install Applications #
########################

choco install googlechrome -y
choco install firefox -y
choco install adobereader -y
choco install jre8 -y
choco install silverlight -y
choco install office365business -y

####################################################################
#Add new layoutmodification Start Menu And Pin Shortcuts to Taskbar#
####################################################################

Set-Content C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml @"
<LayoutModificationTemplate xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" Version="1" xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" >
  <LayoutOptions StartTileGroupCellWidth="6" />
  <DefaultLayoutOverride>
    <StartLayoutCollection>
      <defaultlayout:StartLayout GroupCellWidth="6">
        <start:Group Name="">
          <start:DesktopApplicationTile Size="2x2" Column="0" Row="0" DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk" />
          <start:DesktopApplicationTile Size="2x2" Column="2" Row="2" DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Excel.lnk" />
          <start:DesktopApplicationTile Size="2x2" Column="4" Row="2" DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Outlook.lnk" />
          <start:DesktopApplicationTile Size="2x2" Column="0" Row="2" DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Word.lnk" />
          <start:Tile Size="2x2" Column="0" Row="4" AppUserModelID="Microsoft.BingWeather_8wekyb3d8bbwe!App" />
          <start:DesktopApplicationTile Size="2x2" Column="4" Row="0" DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Acrobat Reader DC.lnk" />
          <start:DesktopApplicationTile Size="2x2" Column="2" Row="0" DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Firefox.lnk" />
        </start:Group>
      </defaultlayout:StartLayout>
    </StartLayoutCollection>
  </DefaultLayoutOverride>
    <CustomTaskbarLayoutCollection PinListPlacement="Replace">
     <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
	    <taskbar:DesktopApp DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\System Tools\File Explorer.lnk" />
        <taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk"/>
        <taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Firefox.lnk" />
        <taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Outlook.lnk" />
		<taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Word.lnk" />
		<taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Excel.lnk" />
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@

############################
# Set Default Applications #
############################

New-Item -Path "c:\" -Name "Temp" -ItemType "directory"

Set-Content C:\Temp\AppAssoc.xml @"
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
  <Association Identifier=".arw" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".bmp" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".cr2" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".crw" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".dib" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".erf" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".gif" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".htm" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier=".html" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier=".inf" ProgId="inffile" ApplicationName="Notepad" />
  <Association Identifier=".ini" ProgId="inifile" ApplicationName="Notepad" />
  <Association Identifier=".jfif" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".jpe" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".jpeg" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".jpg" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".jxr" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".kdc" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".log" ProgId="txtfile" ApplicationName="Notepad" />
  <Association Identifier=".MP2" ProgId="WMP11.AssocFile.MP3" ApplicationName="Windows Media Player" />
  <Association Identifier=".mrw" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".nef" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".nrw" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".orf" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".pdf" ProgId="AcroExch.Document.DC" ApplicationName="Adobe Acrobat Reader DC" />
  <Association Identifier=".pef" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".png" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".ps1" ProgId="Microsoft.PowerShellScript.1" ApplicationName="Notepad" />
  <Association Identifier=".psd1" ProgId="Microsoft.PowerShellData.1" ApplicationName="Notepad" />
  <Association Identifier=".psm1" ProgId="Microsoft.PowerShellModule.1" ApplicationName="Notepad" />
  <Association Identifier=".raf" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".raw" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".rw2" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".rwl" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".scp" ProgId="txtfile" ApplicationName="Notepad" />
  <Association Identifier=".sr2" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".srw" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".svg" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
  <Association Identifier=".tif" ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".tiff" ProgId="PhotoViewer.FileAssoc.Tiff" ApplicationName="Windows Photo Viewer" />
  <Association Identifier=".txt" ProgId="txtfile" ApplicationName="Notepad" />
  <Association Identifier=".url" ProgId="IE.AssocFile.URL" ApplicationName="Internet Browser" />
  <Association Identifier=".wdp" ProgId="AppX43hnxtbyyps62jhe9sqpdzxn1790zetc" ApplicationName="Photos" />
  <Association Identifier=".website" ProgId="IE.AssocFile.WEBSITE" ApplicationName="Internet Explorer" />
  <Association Identifier=".wtx" ProgId="txtfile" ApplicationName="Notepad" />
  <Association Identifier="bingmaps" ProgId="AppXp9gkwccvk6fa6yyfq3tmsk8ws2nprk1p" ApplicationName="Maps" />
  <Association Identifier="http" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier="https" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier="mailto" ProgId="Outlook.URL.mailto.15" ApplicationName="Outlook" />
  <Association Identifier="microsoft-edge" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
  <Association Identifier="microsoft-edge-holographic" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
  <Association Identifier="ms-xbl-3d8b930f" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
  <Association Identifier="read" ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge" />
</DefaultAssociations>
"@

Dism.exe /online /Import-DefaultAppAssociations:C:\Temp\AppAssoc.xml

#############
# Rename PC #                         
#############

function Show-ChangeComputerName_psf
{
	# Import the Assemblies
	[void][reflection.assembly]::Load('System.Windows.Forms, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089')
	[void][reflection.assembly]::Load('System.Drawing, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a')

	# Form Objects
	[System.Windows.Forms.Application]::EnableVisualStyles()
	$formChangeComputerName = New-Object 'System.Windows.Forms.Form'
	$groupbox1 = New-Object 'System.Windows.Forms.GroupBox'
	$radiobuttonStayOn = New-Object 'System.Windows.Forms.RadioButton'
	$radiobuttonRestart = New-Object 'System.Windows.Forms.RadioButton'
	$radiobuttonShutdown = New-Object 'System.Windows.Forms.RadioButton'
	$CopyPCName = New-Object 'System.Windows.Forms.Button'
	$textboxComputerName = New-Object 'System.Windows.Forms.TextBox'
	$labelEnterPCName = New-Object 'System.Windows.Forms.Label'
	$buttonOK = New-Object 'System.Windows.Forms.Button'
	$InitialFormWindowState = New-Object 'System.Windows.Forms.FormWindowState'

	# Script
	$formChangeComputerName_Load = {
	}
	
	$buttonOK_Click = {
		if ($radiobuttonShutdown.Checked) { $AfterShow = "Shutdown" }
		if ($radiobuttonRestart.Checked) { $AfterShow = "Restart" }
		if ($radiobuttonStayOn.Checked) { $AfterShow = "Stay On" }
		if ($textboxComputerName_TextChanged)
		{
			# Take the computer name from the text box
			$ComputerName = $textboxComputerName.Text
			
			# Ask to confrim the name change
			Add-Type -AssemblyName PresentationCore, PresentationFramework
			$ButtonType1 = [System.Windows.MessageBoxButton]::YesNo
			$MessageIcon1 = [System.Windows.MessageBoxImage]::None
			$MessageBody1 = "Computer Name: $ComputerName `n`nAfter: $AfterShow"
			$MessageTitle1 = "Confirm Settings"
			$msgBoxInput1 = [System.Windows.MessageBox]::Show($MessageBody1, $MessageTitle1, $ButtonType1, $MessageIcon1)
			switch ($msgBoxInput1)
			{
				# If click yes
				'Yes' {
					# Edit Registry files for changing the computer name
					New-PSDrive -name HKU -PSProvider "Registry" -Root "HKEY_USERS"
					
					Remove-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -name "Hostname"
					Remove-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -name "NV Hostname"
					Set-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\Computername\Computername" -name "Computername" -value $ComputerName
					Set-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\Computername\ActiveComputername" -name "Computername" -value $ComputerName
					Set-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -name "Hostname" -value $ComputerName
					Set-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -name "NV Hostname" -value $ComputerName
					Set-ItemProperty -path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "AltDefaultDomainName" -value $ComputerName
					Set-ItemProperty -path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "DefaultDomainName" -value $ComputerName
					# Set-ItemProperty -path "HKU:\.Default\Software\Microsoft\Windows Media\WMSDK\General" -name "Computername" -value $ComputerName
					
					# Restart or Shutdown
					if ($radiobuttonRestart.Checked) { shutdown /r -t 0 }
					if ($radiobuttonShutdown.Checked) { Stop-Computer }
				}
				# If click No
				'No' { <# Do nothing #> }
			}
		}
	}
	
	$radiobuttonStayOn_CheckedChanged = { <# Empty #> }
	$radiobuttonRestart_CheckedChanged = { <# Empty #> }
	$radiobuttonShutdown_CheckedChanged = { <# Empty #> }
	$CopyPCName_Click = {
		$CurrentComputerName = $env:computername
		$textboxComputerName.Text = $CurrentComputerName
	}
	
	$textboxComputerName_TextChanged = { <# Empty #> }
	
	# Events
	$Form_StateCorrection_Load =
	{
		# Correct the initial state of the form to prevent the .Net maximized form issue
		$formChangeComputerName.WindowState = $InitialFormWindowState
	}
	
	$Form_Cleanup_FormClosed =
	{
		# Remove all event handlers from the controls
		try
		{
			$radiobuttonStayOn.remove_CheckedChanged($radiobuttonStayOn_CheckedChanged)
			$radiobuttonRestart.remove_CheckedChanged($radiobuttonRestart_CheckedChanged)
			$radiobuttonShutdown.remove_CheckedChanged($radiobuttonShutdown_CheckedChanged)
			$CopyPCName.remove_Click($CopyPCName_Click)
			$textboxComputerName.remove_TextChanged($textboxComputerName_TextChanged)
			$buttonOK.remove_Click($buttonOK_Click)
			$formChangeComputerName.remove_Load($formChangeComputerName_Load)
			$formChangeComputerName.remove_Load($Form_StateCorrection_Load)
			$formChangeComputerName.remove_FormClosed($Form_Cleanup_FormClosed)
		}
		catch { Out-Null <# Prevent PSScriptAnalyzer warning #> }
	}

	# region Generated Form Code
	$formChangeComputerName.SuspendLayout()
	$groupbox1.SuspendLayout()

	# formChangeComputerName
	$formChangeComputerName.Controls.Add($groupbox1)
	$formChangeComputerName.Controls.Add($CopyPCName)
	$formChangeComputerName.Controls.Add($textboxComputerName)
	$formChangeComputerName.Controls.Add($labelEnterPCName)
	$formChangeComputerName.Controls.Add($buttonOK)
	$formChangeComputerName.AcceptButton = $buttonOK
	$formChangeComputerName.AutoScaleDimensions = '6, 13'
	$formChangeComputerName.AutoScaleMode = 'Font'
	$formChangeComputerName.ClientSize = '284, 207'
	$formChangeComputerName.FormBorderStyle = 'FixedDialog'
	$formChangeComputerName.MaximizeBox = $False
	$formChangeComputerName.MinimizeBox = $False
	$formChangeComputerName.Name = 'formChangeComputerName'
	$formChangeComputerName.StartPosition = 'CenterScreen'
	$formChangeComputerName.Text = 'Change Computer Name'
	$formChangeComputerName.add_Load($formChangeComputerName_Load)

	# groupbox1
	$groupbox1.Controls.Add($radiobuttonStayOn)
	$groupbox1.Controls.Add($radiobuttonRestart)
	$groupbox1.Controls.Add($radiobuttonShutdown)
	$groupbox1.Location = '6, 58'
	$groupbox1.Name = 'groupbox1'
	$groupbox1.Size = '272, 109'
	$groupbox1.TabIndex = 4
	$groupbox1.TabStop = $False
	$groupbox1.Text = 'After Name Change'
	$groupbox1.UseCompatibleTextRendering = $True

	# radiobuttonStayOn
	$radiobuttonStayOn.Location = '20, 79'
	$radiobuttonStayOn.Name = 'radiobuttonStayOn'
	$radiobuttonStayOn.Size = '104, 24'
	$radiobuttonStayOn.TabIndex = 2
	$radiobuttonStayOn.Text = 'Stay On'
	$radiobuttonStayOn.UseCompatibleTextRendering = $True
	$radiobuttonStayOn.UseVisualStyleBackColor = $True
	$radiobuttonStayOn.add_CheckedChanged($radiobuttonStayOn_CheckedChanged)

	# radiobuttonRestart
	$radiobuttonRestart.Location = '20, 49'
	$radiobuttonRestart.Name = 'radiobuttonRestart'
	$radiobuttonRestart.Size = '104, 24'
	$radiobuttonRestart.TabIndex = 1
	$radiobuttonRestart.Text = 'Restart'
	$radiobuttonRestart.UseCompatibleTextRendering = $True
	$radiobuttonRestart.UseVisualStyleBackColor = $True
	$radiobuttonRestart.add_CheckedChanged($radiobuttonRestart_CheckedChanged)

	# radiobuttonShutdown
	$radiobuttonShutdown.Location = '20, 19'
	$radiobuttonShutdown.Name = 'radiobuttonShutdown'
	$radiobuttonShutdown.Size = '104, 24'
	$radiobuttonShutdown.TabIndex = 0
	$radiobuttonShutdown.Text = 'Shutdown'
	$radiobuttonShutdown.UseCompatibleTextRendering = $True
	$radiobuttonShutdown.UseVisualStyleBackColor = $True
	$radiobuttonShutdown.add_CheckedChanged($radiobuttonShutdown_CheckedChanged)

	# CopyPCName
	$CopyPCName.Location = '12, 29'
	$CopyPCName.Name = 'CopyPCName'
	$CopyPCName.Size = '86, 23'
	$CopyPCName.TabIndex = 3
	$CopyPCName.Text = 'Copy Name'
	$CopyPCName.UseCompatibleTextRendering = $True
	$CopyPCName.UseVisualStyleBackColor = $True
	$CopyPCName.add_Click($CopyPCName_Click)
	
	# textboxComputerName
	$textboxComputerName.Location = '104, 6'
	$textboxComputerName.Name = 'textboxComputerName'
	$textboxComputerName.Size = '174, 20'
	$textboxComputerName.TabIndex = 2
	$textboxComputerName.add_TextChanged($textboxComputerName_TextChanged)

	# labelEnterPCName
	$labelEnterPCName.AutoSize = $True
	$labelEnterPCName.Location = '12, 9'
	$labelEnterPCName.Name = 'labelEnterPCName'
	$labelEnterPCName.Size = '86, 17'
	$labelEnterPCName.TabIndex = 1
	$labelEnterPCName.Text = 'Enter PC Name:'
	$labelEnterPCName.UseCompatibleTextRendering = $True
	
	# buttonOK
	$buttonOK.Anchor = 'Bottom, Right'
	$buttonOK.DialogResult = 'OK'
	$buttonOK.Location = '197, 172'
	$buttonOK.Name = 'buttonOK'
	$buttonOK.Size = '75, 23'
	$buttonOK.TabIndex = 0
	$buttonOK.Text = '&OK'
	$buttonOK.UseCompatibleTextRendering = $True
	$buttonOK.UseVisualStyleBackColor = $True
	$buttonOK.add_Click($buttonOK_Click)
	$groupbox1.ResumeLayout()
	$formChangeComputerName.ResumeLayout()

	# Save the initial state of the form
	$InitialFormWindowState = $formChangeComputerName.WindowState
	# Init the OnLoad event to correct the initial state of the form
	$formChangeComputerName.add_Load($Form_StateCorrection_Load)
	# Clean up the control events
	$formChangeComputerName.add_FormClosed($Form_Cleanup_FormClosed)
	# Show the Form
	return $formChangeComputerName.ShowDialog()
}

# Call the form
Show-ChangeComputerName_psf | Out-Null

#################################
#Install NUGet Package Provide  #
#################################

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

###############################################
# Check for and Install Windows updates       #
###############################################

Install-Module PSWindowsUpdate -Repository PSGallery -Force

Get-WindowsUpdate -AcceptAll -Download -Install -AutoReboot

# Close Powershell Window 

stop-process -Id $PID
