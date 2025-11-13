<#
.SYNOPSIS
This script checks the status of a scheduled task and sends an email alert if the task fails.

.DESCRIPTION
This PowerShell script is designed to check the status of a specified scheduled task. It queries the task status and checks if it has failed (i.e., if the error code is greater than 0). If the task fails, it sends an email notification to an administrator with the error code.

To ensure this check is performed daily, the script must be added to Windows Task Scheduler. The Task Scheduler will run the script at your desired frequency (e.g., daily) to check for task failures and send alerts if needed.

.NOTES
File Name      : Email_Failed_Task.ps1
Author         : capnhowyoudo
Version        : 1.0
Last Updated   : [Date]
Requires       : PowerShell 5.0 or higher
Parameters     : 
                - $ScheduledTaskName : The name of the scheduled task to query.
                - $User              : The email address of the user (admin) to send the alert.
                - $Pass              : The password for the user account (plain text, will be converted to secure string).
                - $From              : The email sender address.
                - $To                : The email recipient address.
                - $SMTPServer        : The SMTP server for sending the email.
                - $SMTPPort          : The port used by the SMTP server.

Example Usage   :
    .\Email_Failed_Task.ps1
    This will check the status of the scheduled task 'Taskname' and send an email if it fails.

    Modify parameters as needed for your environment. Example for custom SMTP settings:
    .\Email_Failed_Task.ps1 -ScheduledTaskName "Backup Task" -SMTPServer "smtp.company.com" -SMTPPort 25

Task Scheduler Setup:
    - Create a new task in Windows Task Scheduler to run this script daily.
    - Set the script to execute on a schedule (e.g., daily) to ensure task failure is checked every day.
    - Set the trigger to run at a time when the scheduled task you're monitoring should have completed.
#>

param(
    [string]$ScheduledTaskName = "Taskname",    # The name of the scheduled task to query.
    [string]$User = "admin@company.com",        # The email address of the user (admin) to send the alert.
    [string]$Pass = "myPassword",               # The password for the user account (plain text).
    [string]$From = "Alert Scheduled Task <task@servername>",   # The email sender address.
    [string]$To = "Admin <admin@company.com>",  # The email recipient address.
    [string]$SMTPServer = "smtp.company.com",   # The SMTP server for sending the email.
    [int]$SMTPPort = 25                         # The port used by the SMTP server.
)

# Query the scheduled task result
$Result = (schtasks /query /FO LIST /V /TN $ScheduledTaskName | findstr "Result")
$Result = $Result.substring(12)
$Code = $Result.trim()

# If the task failed (error code greater than 0)
If ($Code -gt 0) {
    # Create a credential object using the user and password
    $Pass = ConvertTo-SecureString -String $Pass -AsPlainText -Force
    $Cred = New-Object System.Management.Automation.PSCredential $User, $Pass

    # Set up email details
    $Subject = "Scheduled task '$ScheduledTaskName' failed on SRV-001"
    $Body = "Error code: $Code"
    
    # Send the email alert
    Send-MailMessage -From $From -To $To -Subject $Subject `
        -Body $Body -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl `
        -Credential $Cred
}
