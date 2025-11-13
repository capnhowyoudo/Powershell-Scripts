<#
.Synopsis
    This script imports user data from a CSV file and creates new user accounts in Active Directory (AD). It checks if the user already exists before attempting to create a new account.

.Description
    This PowerShell script automates the process of creating new Active Directory user accounts by importing user data from a CSV file. The script reads data for each user (such as username, first name, last name, email, password, etc.) and creates the corresponding AD user account. 

    It first checks if the user already exists in Active Directory based on the `SamAccountName`. If the user exists, a warning is displayed, and the user is not recreated. If the user does not exist, the script proceeds to create the new account in the specified Organizational Unit (OU) provided in the CSV file.

    Key properties such as user name, email, password, office phone, job title, and others are taken directly from the CSV file and assigned to the new user account. The password is set to never expire, and the user will not be prompted to change the password at the first logon.

    This script is useful for bulk user creation in AD, especially for organizations onboarding new users based on a pre-defined dataset in CSV format.

.Notes
    Requirements:
        - Active Directory module for PowerShell
        - A CSV file containing user data with the following columns: `username`, `password`, `firstname`, `lastname`, `ou`, `email`, `streetaddress`, `city`, `zipcode`, `state`, `country`, `telephone`, `jobtitle`, `company`, `department`, `description`.
    Tested On: [Version of Windows Server/Active Directory, etc.]
    Log File Path: N/A (This script outputs warnings directly to the console)
    Usage: The script assumes that the CSV file (`Bulkusers.csv`) is formatted correctly with the necessary user attributes. Make sure to adjust the domain name in the `UserPrincipalName` (`$Username@yourdomain.com`).
    Warning: Ensure that the data in the CSV is accurate before running the script, as it automatically creates new user accounts in AD.

#>
 
Import-Module ActiveDirectory
$ADUsers = Import-CSV C:\Temp\Bulkusers.csv

foreach ($User in $ADUsers) {
    # Read user data from each field in each row and assign the data to a variable
    $Username  = $User.username
    $Password  = $User.password
    $Firstname = $User.firstname
    $Lastname  = $User.lastname
    $OU        = $User.ou  # OU where the user account will be created
    $email     = $User.email
    $streetaddress = $User.streetaddress
    $city      = $User.city
    $zipcode   = $User.zipcode
    $state     = $User.state
    $country   = $User.country
    $telephone = $User.telephone
    $jobtitle  = $User.jobtitle
    $company   = $User.company
    $department = $User.department
    $description = $user.description

    # Check if the user already exists in AD
    if (Get-ADUser -F {SamAccountName -eq $Username}) {
        # If the user exists, give a warning
        Write-Warning "A user account with username $Username already exists in Active Directory."
    } else {
        # If the user does not exist, create a new user account
        New-ADUser `
            -SamAccountName $Username `
            -UserPrincipalName "$Username@yourdomain.com" `
            -Name "$Firstname $Lastname" `
            -GivenName $Firstname `
            -Surname $Lastname `
            -Enabled $True `
            -DisplayName "$Firstname $Lastname" `
            -Path $OU `
            -City $city `
            -Company $company `
            -State $state `
            -StreetAddress $streetaddress `
            -OfficePhone $telephone `
            -EmailAddress $email `
            -Title $jobtitle `
            -Description "$Firstname $Lastname" `
            -Department $department `
            -AccountPassword (convertto-securestring $Password -AsPlainText -Force) `
            -ChangePasswordAtLogon $false `
            -PasswordNeverExpires $True
    }
}
