<#
.SYNOPSIS
    Generates and installs a self-signed RSA certificate for the local machine.

.DESCRIPTION
    This script automates the creation of a self-signed certificate using New-SelfSignedCertificate. 
    It configures the Subject and DNS names using the machine's FQDN, exports the certificate 
    as both .CER and .PFX files to a specified directory, and automatically imports the .CER 
    into the Trusted Root Certification Authorities store to establish local trust.

.PARAMETER certname
    The friendly name prefix for the certificate. Defaults to the local Computer Name.

.PARAMETER dnsname
    The Fully Qualified Domain Name (FQDN) for the certificate. Defaults to ComputerName.Domain.

.PARAMETER pwd
    The password used to protect the exported .PFX file.

.PARAMETER path
    The file system path where the certificate files will be exported. Created if it doesn't exist.

.EXAMPLE
    .\Create_2_Year_Self_Signed_Cert.ps1 -certname "DevServer" -pwd "StrongPass123!"

.NOTES
    Requires: Administrator privileges to import into the LocalMachine\Root store.
    If Using ISE be sure to set the password in [string]$pwd =
#>

param (
     [Parameter(HelpMessage="Enter a friendly name for the certificate")]
     [string]$certname=$($env:COMPUTERNAME), 

     [Parameter(HelpMessage="Enter the FQDN for the DNS name")]
     # This builds the FQDN for the Subject and DNS Name fields
     [string]$dnsname=$($env:COMPUTERNAME + "." + $env:USERDNSDOMAIN), 

     [Parameter(HelpMessage="Enter a password for the PFX export")]
     [string]$pwd = "Please set a password!",

     [Parameter(HelpMessage="Destination path for certificate files")]
     [string]$path = "C:\certs"
)

# Create directory if it doesn't exist
if (!(Test-Path $path)) { New-Item -ItemType Directory -Path $path }

$dnsname = $dnsname.ToLower()
$mypwd = ConvertTo-SecureString -String $pwd -Force -AsPlainText

# -Subject uses $dnsname to ensure the domain shows in the "Issued To" column
$cert = New-SelfSignedCertificate -Subject "CN=$dnsname" `
    -FriendlyName "$certname-SelfSigned" `
    -CertStoreLocation "Cert:\localmachine\My" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -KeyLength 2048 `
    -KeyAlgorithm RSA `
    -HashAlgorithm SHA256 `
    -DnsName $dnsname, $certname `
    -NotAfter (Get-Date).AddYears(2)

# Exporting files for backup/distribution
Export-Certificate -Cert $cert -FilePath "$path\lm_$certname.cer"
Export-PfxCertificate -Cert $cert -FilePath "$path\lm_$certname.pfx" -Password $mypwd

# Install into Trusted Root so browsers/apps trust the FQDN
$certfile = (Get-ChildItem -Path "$path\lm_$certname.cer")
$certfile | Import-Certificate -CertStoreLocation cert:\LocalMachine\Root

Write-Host "`nDone!" -ForegroundColor Green
Write-Host "Issued To: $dnsname" -ForegroundColor Cyan
Write-Host "Friendly Name: $certname-SelfSigned" -ForegroundColor Cyan
