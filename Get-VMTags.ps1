#Requires -Modules VMware.VimAutomation.Core,ImportExcel

<#
.SYNOPSIS
Obtains output from vCenter to generate list of VM's tagged for Data Protection

.DESCRIPTION
Obtains the Data Protection tagging information from vCenter and exports to an Excel document
with the protection levels listed on different sheets.
.PARAMETER Path
File name to save the output of the script run to. Defaults to "<Desktop>\VMDPMTags(Date)"

.EXAMPLE
./Get-VMTagScript.ps1

.NOTES
1.0 - Steven Sumichrast <ssumichrast@paylocity.com and Brandon Graves <bgraves@paylocity.com> - Initial Version
1.1 - - Added timestamp to file name.
#>

$vCenter = Connect-VIServer "dc1prod-vcenter.paylocity.com", "dc1int-vcenter.paylocity.com", "dc1qa-vcenter.paylocity.com", "kewi-vcenter.paylocity.com", "dc1derp-vcenter.paylocity.com", "dc1-vcenter-robo.paylocity.com"

# Obtain list of all VMs with their tags, or a "catch all" value
$results = Get-VM | ForEach-Object {
# Get the tag value assigned to the VM
$VMTag = $_ | Get-TagAssignment -Category "Backup Tier"
# If there's no tag value, set our catch all
if (!$VMTag) {
$VMTag = "No Tier Set"
}
else {
# There was a value returned from the get-tagassignment so use it
$VMTag = $VMTag.tag.name
}

# Output the VM + Tag value
[PSCustomObject]@{
VM = $_.Name
Tag = $VMTag
}
}
$timestamp = Get-Date -Format o
# Loop through each tier and save the VMs with that same tier name to the Excel file
$Tiers = $results.tag | Sort-Object $_.Tag -Unique
foreach ($tier in $tiers) {
$results | Where-Object { $_.Tag -eq $tier } | Export-Excel -Path "$($env:UserProfile)\Desktop\VMDPMTags$(Get-Date -f yyyy-MM-dd).xlsx" -WorksheetName $tier
}

$vCenter | Disconnect-VIServer

#Requires -Modules PureStoragePowerShellSDK

# Script generates a report of all the protection groups on an array, what
# volumes are included and where replication is enabled.


param(
[Parameter(Mandatory = $True)]
[string[]]$PureFlashArray
)

$PureFlashArray | ForEach-Object -Begin {
# Obtain Credentials
$PFACredentials = Get-Credential -Message "FlashArray Login Credentials"
} `
-Process {
# Try to connect to FlashArray
try {
$PFA = New-PfaArray -EndPoint $_ -IgnoreCertificateError -Credentials $PFACredentials
}
catch {
Write-Error "Unable to connect to the requested Pure FlashArray $_."
Continue
}

# Obtain list of Protection Groups
$ProtectionGroups = Get-PfaProtectionGroups -Array $PFA
Write-Output "Array: $($pfa.endpoint)"

# Return list of protection groups
$ProtectionGroups | ForEach-Object {
Write-Output " Protection Group $($_.Name)"
Write-Output " Source Array:"
Write-Output " $($_.Source)"
Write-Output ""
if ($_.Targets) {
Write-Output " Target Arrays:"
$_.Targets | ForEach-Object {
Write-Output " $($_.Name)"
}
Write-Output ""
}

Write-Output " Protected Volumes:"
$_.Volumes | ForEach-Object {
Write-Output " $($_)"
}
Write-Output ""
}
Disconnect-PfaArray -Array $PFA
}

