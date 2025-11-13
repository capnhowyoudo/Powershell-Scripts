🪟 Windows 11 Base Image Automation Script – Version 1.0

Author: capnhowyoudo
Purpose: Automate setup, cleanup, and configuration of a clean, standardized Windows 11 image ready for deployment or cloning.

1. 🧰 Administrative Setup and Execution Policy

The script begins by ensuring it runs with administrative privileges.
If it’s not already elevated, it relaunches itself using Start-Process -Verb RunAs to gain admin rights.

It also reminds the user that PowerShell may need its execution policy relaxed (Unrestricted) to run unsigned scripts.

2. ⚙️ Power Settings Configuration

It modifies system power plan settings to standardize behavior across machines:

Monitor timeout: 15 minutes (both AC and battery)

Disk timeout: disabled (0 minutes)

Standby (sleep): 60 minutes

Hibernate: disabled

This ensures consistent sleep/hibernate behavior, useful for corporate imaging and energy management.

3. 🧹 Windows Debloating – Removing Built-in Apps

The script performs a mass cleanup of default Windows 11 apps using Remove-AppxPackage and Get-AppxProvisionedPackage.

It keeps (whitelists) only key apps such as:

Notepad

Calculator

Paint 3D

Microsoft Store

Company Portal (for Intune/MDM)

It removes:

Consumer entertainment and news apps

Social media and promotional apps

Developer demo apps

OEM preloads (HP, Dell, Lenovo helper utilities)

Microsoft Office preinstalled trial versions (via the SARA removal tool)

The goal is a clean, business-ready Windows with minimal clutter.

4. 🍫 Chocolatey Installation and Software Deployment

The script installs Chocolatey, a Windows package manager that automates app installations.

It then installs a set of standard tools via Chocolatey, such as:

Google Chrome

Adobe Acrobat Reader

Microsoft Edge (if needed)

7-Zip

Notepad++

VLC

Office 365 (optional, customizable)

The list is defined within the script and can be easily extended.

Chocolatey is installed silently, configured to skip prompts, and logs progress.

5. 🧱 Default Application Associations

It sets default file handlers and system associations:

.html, .htm, .pdf, and other web links → open in Google Chrome

.pdf → open in Adobe Acrobat Reader

Mail links (mailto:) → open in Outlook

This is done using dism.exe and XML configuration files to enforce defaults for all user profiles.

6. 🖥️ Taskbar and Start Menu Customization

A major part of the script tailors the Windows shell experience:

Start Menu Layout

It replaces the default Windows 11 start layout with a predefined one that includes:

Commonly used enterprise apps (Chrome, Office, File Explorer, etc.)

Custom folder/group arrangements

Removes consumer icons (e.g., TikTok, Spotify, Xbox)

Taskbar Configuration

Moves the taskbar alignment to the left

Removes: Widgets, Chat, Copilot buttons

Pins: File Explorer, Chrome, Outlook, Adobe Reader, etc.

Unpins: Microsoft Store and irrelevant shortcuts

Ensures these settings apply to all user profiles (via registry and policy scripts)

This results in a consistent, professional desktop layout.

7. 🧩 Windows Updates and Driver Handling

The script includes (commented-out) sections for:

Checking for and installing the latest Windows Updates

Optionally enabling automatic updates

Optionally installing drivers or performing Windows Feature updates

These are toggled by uncommenting certain lines (around lines 1850–1860).

8. 💼 Office 365 Custom Installation

The script uses Chocolatey to install Office 365 with custom parameters, allowing:

Edition selection (O365BusinessRetail, O365ProPlusRetail, etc.)

Custom configuration XML path

Language selection

Auto-updates toggle

EULA acceptance

Optional exclusion of specific Office apps (e.g., exclude Teams)

Example command embedded in the script:
