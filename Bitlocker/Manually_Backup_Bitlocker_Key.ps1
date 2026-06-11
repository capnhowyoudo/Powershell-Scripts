<#
.SYNOPSIS
    Backs up a BitLocker key protector for a specified drive to Active Directory or Azure Active Directory.

.DESCRIPTION
    The Backup-BitLockerKeyProtector cmdlet backs up a key protector for a BitLocker-encrypted 
    volume to Active Directory Domain Services (AD DS) or Azure Active Directory (Azure AD), 
    depending on the environment configuration.

    A key protector is a mechanism used to secure the BitLocker encryption key. Common types 
    include RecoveryPassword, TpmPin, and ExternalKey. Each protector is identified by a unique 
    GUID, which must be specified using the -KeyProtectorId parameter.

    This cmdlet is typically used by system administrators to ensure that recovery keys are 
    stored centrally, allowing drives to be unlocked in the event of a forgotten PIN, lost 
    startup key, or TPM failure.

    Requires administrator privileges and that the target volume is BitLocker-enabled.

.NOTES
    Author       : [Capnhowyoudo]
    Version      : 1.0
    Date         : 2026-05-27
    Requires     : PowerShell 3.0 or later
                   BitLocker Drive Encryption feature must be enabled
                   Must be run as Administrator
    Module       : BitLocker (included in Windows Server 2012+ / Windows 8+)

    - Use Get-BitLockerVolume to retrieve KeyProtectorId values before running this cmdlet.
    - Only key protectors of type RecoveryPassword or ExternalKey can be backed up to AD DS.
    - Ensure the AD DS schema has been extended to support BitLocker (via Group Policy) before use.
    
    Computer Configuration
  → Administrative Templates
    → Windows Components
      → BitLocker Drive Encryption
        → Operating System Drives
          → "Store BitLocker recovery information in Active Directory Domain Services" or "Choose how BitLocker-protected operating system drives can be recovered"
          
    - For Azure AD backup, the device must be Azure AD-joined and properly configured via Intune or Group Policy.
#>

# Step 1: Get the key protector ID

(Get-BitLockerVolume -MountPoint "C:").KeyProtector

# Step 2: Back up the key protector

Backup-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId <GUID>
