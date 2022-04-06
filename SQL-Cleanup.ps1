#Requires -Module PoshRSJob,ImportExcel
<#
.DESCRIPTION
This script will obtain a list of SQL folders on a remote target and find
files older than the specified retention to delete.

.PARAMETER Path
Parent path containing SQL backups that should be cleaned up.
Will be recursively searched.

.PARAMETER Throttle
Maximum number of shares to scan simultaneously. Default: 10

.PARAMETER ExcludeShares
An array of shares to exclude from purging. A default list of shares is
already excluded; check the source of this script.

.PARAMETER BackupFileAge <Integer>
Transaction and backup files older than BackupFileAge, counting from
midnight of the day this script runs, will be deleted.

.PARAMETER ReportFileAge <Integer>
Text report files older than ReportFileAge will be removed from the
FlashBlade.

This parameter also controls how long to store the logged actions of this
script in LogDirectory.

.PARAMETER LogDirectory
Location to store the log file output. Script will automatically generate
file name based on current date-time stamp.

Default: C:\Git\Logs\PowerShell\File Operations\Cleanup-SQLBackups\

.NOTES
Author: Steven Sumichrast <ssumichrast@paylocity.com>

Version: 1.0

Changelog:

1.0 - 2019-05-15 - Initial version of script
#>

[cmdletbinding()]
param(
[parameter(Mandatory = $true)]
[string]$Path,
[int]$Throttle = 50,
[string[]]$ExcludeShares,
[int]$BackupFileAge = 8,
[int]$ReportFileAge = 35,
[string]$LogDirectory = "C:\Git\Logs\Infrastructure\PowerShell\File Operations\Cleanup-SQLBackups\"
)

$ExcludedShares = $ExcludeShares + @(
"SQLCertificates",
"SQLKeys"
)

# Generate the folder name off the full path
$FolderName = $path.split("\")[-1]

## Logging Functionality
$LogDate = Get-Date -Format 'yyyyMMddHHmm'
$LogFile = "$($FolderName)-$($LogDate).txt"
$RemovedFilesLogFile = "$($FolderName)-$($LogDate)-RemovedFiles.xlsx"

function Write-Log {
param(
# Log Line to write to log
[string]
$Text
)
# Check if we have built a log file. If not, build one.


if (!(Test-Path $LogDirectory)) {
New-Item -Path $LogDirectory -ItemType Directory | Out-Null
}

"$(Get-Date -Format 'MMMM dd HH:mm:ss'): $($Text)" | Tee-Object -FilePath ($LogDirectory + $LogFile) -Append | Write-Verbose
}

$BackupFileCutoffDate = (Get-Date -Hour 0 -Minute 0 -Second 0).AddDays(-$BackupFileAge)
$ReportFileCutoffDate = (Get-Date -Hour 0 -Minute 0 -Second 0).AddDays(-$ReportFileAge)

Write-Log "Cutoff date for backup files: $($BackupFileCutoffDate)"
Write-Log "Cutoff date for backup report files: $($ReportFileCutoffDate)"

Write-Log "Will exclude $(($ExcludedShares).count) shares from search:"
$ExcludedShares | ForEach-Object -Process {
Write-Log " $($_)"
}

# Connect to share and obtain sub paths
try {
Write-Log "Attempting to connect to $($Path) to obtain shares."
Test-Path -LiteralPath $Path | Out-Null
$SMBShares = Get-ChildItem -Directory -LiteralPath $Path | Sort-Object
Write-Log "Found $(($SMBShares).count) shares:"
$SMBShares | Foreach-Object -Process {
Write-Log " $($_.name)"
}
}
catch {
Write-Log "Failed to obtain list of SMB Shares from $($Path)."
throw "Failed to obtain list of SMB Shares from $($Path)."
}

# Create a runspace instance for each share and begin finding files to purge
Write-Log "Spawning runspace for $($SMBShares.count) shares."
Write-Log "Throttling to $($Throttle) jobs simultaneously."
$RSJobs = $SMBShares | Start-RSJob -Name { $_.Name } -Throttle $Throttle -ScriptBlock {
$Folder = $_
# Search for old backup files in the path.
Get-ChildItem -Path $Folder.FullName -File -Recurse -Include @("*.bak", "*.trn") | Where-Object { $_.LastWriteTime -lt $Using:BackupFileCutoffDate } | Foreach-Object -Process {
$_ | Copy-Item -Path "\\fpil-cohesity.paylocity.com\Infrastructure-share\Reports\*" -Destination "\\dc1backups\DC1Cohesity\" -Recurse -Confirm:$false
if ($?) {
[pscustomobject]@{
Share = $Folder.Name
Name = $_.FullName
Date = $_.LastWriteTime
Size = $_.Length
Action = "Moved"
}
}
}

# Search for old report files in the path.
Get-ChildItem -Path $Folder.FullName -File -Include "*.txt" | Where-Object { $_.LastWriteTime -lt $Using:ReportFileCutoffDate } | Foreach-Object -Process {
$_ | Remove-Item -Confirm:$false -whatif
if ($?) {
[pscustomobject]@{
Share = $Folder.Name
Name = $_.FullName
Date = $_.LastWriteTime
Size = $_.Length
Action = "Removed"
}
}
}
}

# Provide feedback that the jobs have been spawned
Write-Log "$($RSJobs.count) Runspaces created:"
$RSJobs | Foreach-Object {
Write-Log " $($_.Name)"
}

# Wait for jobs to complete
Write-Log "Waiting for all jobs to finish."
$RSJobs | Wait-RSJob | Out-Null
Write-Log "All jobs complete."

# Once jobs are spawned, we need to receive them and then remove them.
$RemovedFiles = $RSJobs | Receive-RSJob
$RSjobs | Remove-RSJob | Out-Null

# Export logs of the files removed
Write-Log "Removed $(($RemovedFiles).count) files."
Write-Log "Exporting removed files to $($LogDirectory)\$($RemovedFilesLogFile)."
$RemovedFiles | Export-Excel -Path "$($LogDirectory)\$($RemovedFilesLogFile)"

# Cleanup old job logs
Write-Log "Removing job logs older than $($ReportFileCutOffDate)"
Get-ChildItem -Path $LogDirectory | Where-Object { $_.LastWriteTime -lt $ReportFileCutoffDate } | Remove-Item -confirm:$false

# Run complete
Write-Log "Run complete"