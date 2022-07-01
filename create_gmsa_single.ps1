<# 
 .SYNOPSIS 
 Script to create new GMSA Service Accounts (Groupmanaged)
 This script does nearly all what is needed to use GMSA Accounts.

 The only things you need to do are:
 1. Create an OU in AD where the Groups for the GMSA Accounts will be stored
 2. Add this Information to this Script here
 3. Add your local Domain (here in this Example: home.local) to the Script

 Run the Script and let it create the Account for you
 (also Adding the Root Key if needed)
   
 .NOTES  
 Author: Clemens Bayer (mastadook@gmx.de)
 Version: 1.0.1
 DateCreated: 2022.06.10
 DateUpdated: 2022.06.30
 
 .CHANGELOG 
 2022.06.30: Add Kerberos purging to save from restarts
				
 #>

# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
        $Command = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
        Start-Process -FilePath PowerShell.exe -Verb RunAs -ArgumentList $Command
        Exit
 }
Write-Host "Had to start PowerShell Evaluated"
}

# extracting Working Path of the Script
function Get-ScriptDirectory
{
$Invocation = (Get-Variable MyInvocation -Scope 1).Value
Split-Path $Invocation.MyCommand.Path
}
$ScriptPath = Get-ScriptDirectory

#
# !!!!!!!!!!!!!!Enter the Data of your Environment here!!!!!!!!!!!!!!!!!!!!!!!!!!
#
# Path to add the new created gmsa groups (Path must exist in Active Directory)
$Grouppath = "OU=GMSA-Groups,OU=Groups,DC=home,DC=local"
# Local AD Domain name 
$Domain = "home.local"

Write-Host "PowerShell runs now Evaluated"

# Check for Root Key
Write-Host "Check now if Root Key is working properly"
try {
    test-kdsrootkey -keyid ((get-kdsrootkey).keyid).guid}
catch {
    Write-Host "Root Key NOT OK" -fore Red
    Add-KdsRootKey -EffectiveTime ((get-date).addhours(-10))
    Write-Host "Root Key added now" -fore green}
Write-Host "Root Key is working properly" -fore green

# Colleting Informations of Account and setting Name etc.
Write-Host "Create new Group Managed Service Account"
$Case = Read-Host "Please enter a short Use Case for Account without spaces (App Name for Example)"
try {
$users = get-AdServiceAccount -filter "Name -like 'y001*'" | sort # | select -ExpandProperty name
foreach ($user in $users){}
[int]$zahl = $user.samaccountname.Substring(3,4)
$Newnumber = $zahl + 1
$Newaccount = "Y00" + $Newnumber
$Name = $Newaccount}
catch { $Newaccount = "Y001001"
        $Name = $Newaccount}
$Servernames = Read-Host "Please enter Servers that should work with the Account. separate with , Comma"
if ($Servernames) {$Servernames=$Servernames.Split(',')}
$DNSHostname = "$Name.$Domain"
$Groupname = "GMSA-G-" + "$Case"
$ExecUser = ([Environment]::UserName) 
$Date = (Get-Date).ToString("yyyy.MM.dd")
$Groupdescription = "Group for Computers that are allowed to read the PW for GMSA $Name (Created by $ExecUser / $Date)"
$AccountDescription = "GMSA for Application $Case. Working with together with Group $Groupname (Created by $ExecUser / $Date)"
$eventSource = "create_gmsa_single.ps1"

if ($Error01) {Clear-variable Error01}
if ($Error02) {Clear-variable Error02}
if ($Error03) {Clear-variable Error03}
if ($ErrorMessage01) {Clear-variable ErrorMessage01}
if ($ErrorMessage02) {Clear-variable ErrorMessage02}
if ($ErrorMessage03) {Clear-variable ErrorMessage03}

if ([System.Diagnostics.EventLog]::SourceExists($EventSource) -eq $false) {
   Write-Host "Creating event source [$EventSource] on event log [Application]"
   [System.Diagnostics.EventLog]::CreateEventSource("$EventSource",'Application')
} else { Write-Host "Event source [$EventSource] is already registered" }

# creating the new AD Group now
try {
New-ADGroup -Name $Groupname -SamAccountName $Groupname -GroupCategory Security -GroupScope Global -DisplayName $Groupname -Path $Grouppath -Description $Groupdescription
}
catch {Write-Host "Error creating Group $Groupname" -ForegroundColor Red
        $Error01 = "Problems creating Group $Groupname"
        $ErrorMessage01 = $_.Exception.message}
Write-Host "Group $Groupname created" -ForegroundColor Green
Write-Host "Going to Sleep 10 seconds" -ForegroundColor Yellow
Start-Sleep 10

# Adding the Servers to the new AD Group
if ($Servernames) {
foreach ($Servername in $Servernames) {
try {
ADD-ADGroupMember -identity $Groupname –members (Get-ADComputer $Servername)}
catch {Write-Host "Error adding $Servername to $Groupname" -ForegroundColor Red
        $Error02 = "Problems adding Servers to Group $Groupname"
        $ErrorMessage02 = $_.Exception.message}
Write-Host "$Servername to $Groupname added" -ForegroundColor Green}}
else {Write-Host "No Groupmembers for Group $Groupname entered, so no Computers added" -ForegroundColor Green}

Write-Host "Going to Sleep 5 seconds" -ForegroundColor Yellow
Start-Sleep 5

# creating the GMSA Account now
try {
New-AdServiceAccount -Name $Name -DNSHostName $DNSHostname -PrincipalsAllowedToRetrieveManagedPassword $Groupname -Description $AccountDescription
}
catch {Write-Host "Error creating GMSA $Name" -ForegroundColor Red
        $Error03 = "Problems creating GMSA Account $Name"
        $ErrorMessage03 = $_.Exception.message}
Write-Host "Account $Name created" -ForegroundColor Green

if ($Error01) {
Write-EventLog -LogName "Application" -Source $eventSource -EventID 7077 -EntryType Error -Message "Problems creating the GMSA Account or Group Error: $Error0 and $ErrorMessage01" -Category 1}
elseif ($Error02) {
Write-EventLog -LogName "Application" -Source $eventSource -EventID 7077 -EntryType Error -Message "Problems creating the GMSA Account or Group Error: $Error02 and $ErrorMessage02" -Category 1}
elseif ($Error03) {
Write-EventLog -LogName "Application" -Source $eventSource -EventID 7077 -EntryType Error -Message "Problems creating the GMSA Account or Group Error: $Error03 and $ErrorMessage03" -Category 1}
else {
Write-EventLog -LogName "Application" -Source $eventSource -EventID 7078 -EntryType Information -Message "New Account $Name and corresponding Group $Groupname created" -Category 1}


Write-Host "Should we also refresh the Kerberos Tickets in order to save the Restart"

Write-Host "Y = YES" -foreground "yellow"
Write-Host "N = NO" -foreground "yellow"

$choose = read-host -Prompt 'Please choose Y or N'

if ($choose -like "Y") {

#Script to refresh the Kerberos Tickets on Memberservers to save from reboot after creating new GMSA Account
$GroupName
$Groupmembers = Get-ADGroupMember $GroupName | select-object -ExpandProperty name
$Groupmembers

Write-Host "Going to Sleep 5 seconds" -ForegroundColor Yellow
Start-Sleep 5

foreach ($Server in $Groupmembers) {

$Server

Invoke-Command -ComputerName $Server -ScriptBlock {
Write-Host "Purging the Tickets now for Computer $Server" -ForegroundColor Yellow
klist.exe -li 0x3e7
klist.exe -li 0x3e7 purge
gpupdate
klist.exe -li 0x3e7
gpresult /r /scope computer
}
Write-EventLog -LogName "Application" -Source $eventSource -EventID 7078 -EntryType Information -Message "Kerberos Tickets purged on affected Server $Server" -Category 1
}
Write-Host "Done, GMSA Account created and Kerberos Tickets purged and new created" -fore green
}

else {Write-Host "Done, GMSA Account created" -fore green}
