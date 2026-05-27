<#
.SYNOPSIS
Installs the Active Directory Users and Computers (ADUC) BitLocker Recovery Password Viewer extension.

.DESCRIPTION
This command installs the RSAT feature required to view BitLocker recovery keys
stored in Active Directory Domain Services (AD DS).

After installation, administrators can open Active Directory Users and Computers (ADUC),
enable Advanced Features, and view the "BitLocker Recovery" tab on computer objects.

The recovery information is typically stored in AD when Group Policy is configured to
back up BitLocker recovery passwords and key packages to Active Directory.

HOW TO USE:
1. Run PowerShell as Administrator.
2. Execute this command:
    
    Install-WindowsFeature RSAT-Feature-Tools-BitLocker-BdeAducExt

3. Open:
    
    Active Directory Users and Computers (dsa.msc)

4. In ADUC:
    - Click View
    - Enable "Advanced Features"

5. Browse to the computer object.
6. Right-click the computer → Properties.
7. Open the "BitLocker Recovery" tab.

NOTES:
- Requires RSAT and Active Directory administrative permissions.
- The BitLocker Recovery tab only appears after:
    - The feature is installed
    - Advanced Features is enabled
- Recovery keys will only appear if the machine has successfully escrowed
  BitLocker recovery information into AD DS.
- Common recovery object class:
    
    msFVE-RecoveryInformation

- Useful for domain-joined BitLocker-managed devices.

.NOTES
Author: capnhowyoudo
Purpose: Enable BitLocker recovery key viewing in ADUC
Applies To: Windows Server / RSAT-enabled admin workstations
#>

Install-WindowsFeature RSAT-Feature-Tools-BitLocker-BdeAducExt
