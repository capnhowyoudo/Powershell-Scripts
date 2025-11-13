<#
.SYNOPSIS
Installs the Print Management Console feature on the local Windows system.

.DESCRIPTION
This script uses the DISM (Deployment Image Servicing and Management) tool to add the 
Print Management Console capability to the current Windows installation.

The Print Management Console provides a graphical interface to manage printers, print queues, 
and printer drivers on local or remote systems.  

This script must be run with administrative privileges to successfully install the feature.

.NOTES
File Name   : Install_PrintManagement_Console.ps1
Author      : capnhowyoudo
Date        : 2025-11-13
Requires    : Windows 10 / Windows Server 2012 or later
Usage       : 
    - Run the script in an elevated PowerShell session:
        .\Install_PrintManagementConsole.ps1
#>

# Install the Print Management Console feature
Dism /Online /Add-Capability /CapabilityName:Print.Management.Console~~~~0.0.1.0
