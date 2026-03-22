<#
.SYNOPSIS
    Automates FULL, DIFFERENTIAL, or LOG backups for all user databases on
    one or more SQL Server instances with configurable retention cleanup.

.DESCRIPTION
    - Iterates every online user database (excludes system databases by default).
    - Builds a timestamped filename per database.
    - Runs BACKUP DATABASE / BACKUP LOG with COMPRESSION, CHECKSUM, STATS.
    - Deletes backup files older than RetentionDays from the target folder.
    - Logs each operation to a dated log file.

.PARAMETER SqlInstances
    One or more SQL Server instance names.

.PARAMETER BackupRoot
    UNC or local root folder.  A sub-folder per instance is created automatically.
    Example: \\fileserver\SQLBackups

.PARAMETER BackupType
    FULL | DIFF | LOG.  Default: FULL.

.PARAMETER RetentionDays
    Backup files older than this number of days are deleted.  Default: 14.

.PARAMETER ExcludeDatabases
    Database names to skip.  Default excludes tempdb only.

.PARAMETER LogPath
    Path for the operation log file.  Default: $BackupRoot\backup_log.txt.

.EXAMPLE
    .\Invoke-BackupAll.ps1 -SqlInstances "SQL01" -BackupRoot "D:\Backups" -BackupType FULL

.EXAMPLE
    .\Invoke-BackupAll.ps1 -SqlInstances "SQL01","SQL02" -BackupRoot "\\nas\sql" -BackupType LOG -RetentionDays 3

.REQUIREMENTS
    SqlServer PowerShell module  (Install-Module SqlServer)
    db_backupoperator or sysadmin on each instance
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string[]] $SqlInstances,

    [Parameter(Mandatory)]
    [string]   $BackupRoot,

    [ValidateSet('FULL','DIFF','LOG')]
    [string]   $BackupType = 'FULL',

    [int]      $RetentionDays = 14,

    [string[]] $ExcludeDatabases = @('tempdb'),

    [string]   $LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $LogPath) { $LogPath = Join-Path $BackupRoot 'backup_log.txt' }

$ext = switch ($BackupType) { 'LOG' { 'trn' } 'DIFF' { 'bak' } default { 'bak' } }
$backupTypeClause = switch ($BackupType) {
    'LOG'  { 'LOG' }
    'DIFF' { 'DATABASE ... WITH DIFFERENTIAL' }
    default { 'DATABASE' }
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    $line | Tee-Object -FilePath $LogPath -Append | Write-Host -ForegroundColor (
        switch ($Level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } default { 'White' } }
    )
}

# ── Retrieve database list ───────────────────────────────────────────────────

$SqlGetDatabases = @"
SELECT name
FROM sys.databases
WHERE state_desc = 'ONLINE'
  AND name NOT IN ({0})
  AND source_database_id IS NULL   -- exclude snapshots
ORDER BY name;
"@

foreach ($instance in $SqlInstances) {
    Write-Log "=== Starting $BackupType backup on [$instance] ==="

    $instanceFolder = Join-Path $BackupRoot ($instance -replace '[\\/:*?"<>|]', '_')
    if (-not (Test-Path $instanceFolder)) {
        New-Item -ItemType Directory -Path $instanceFolder | Out-Null
    }

    # Build exclusion list for T-SQL
    $excludeList = ($ExcludeDatabases | ForEach-Object { "'$_'" }) -join ','

    try {
        $databases = Invoke-Sqlcmd -ServerInstance $instance `
            -Query ($SqlGetDatabases -f $excludeList) `
            -ErrorAction Stop
    } catch {
        Write-Log "Failed to retrieve database list from [$instance]: $_" 'ERROR'
        continue
    }

    foreach ($db in $databases) {
        $dbName    = $db.name
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $fileName  = "${dbName}_${BackupType}_${timestamp}.${ext}"
        $filePath  = Join-Path $instanceFolder $fileName

        # Skip LOG backups for SIMPLE recovery databases
        if ($BackupType -eq 'LOG') {
            $recoveryModel = (Invoke-Sqlcmd -ServerInstance $instance `
                -Query "SELECT recovery_model_desc FROM sys.databases WHERE name = N'$dbName'" `
                -ErrorAction Stop).recovery_model_desc
            if ($recoveryModel -eq 'SIMPLE') {
                Write-Log "Skipping LOG backup for [$dbName] — recovery model is SIMPLE" 'WARN'
                continue
            }
        }

        $backupSql = switch ($BackupType) {
            'FULL' {
"BACKUP DATABASE [$dbName]
 TO DISK = N'$filePath'
 WITH COMPRESSION, CHECKSUM, STATS = 10, NAME = N'${dbName} Full Backup';"
            }
            'DIFF' {
"BACKUP DATABASE [$dbName]
 TO DISK = N'$filePath'
 WITH DIFFERENTIAL, COMPRESSION, CHECKSUM, STATS = 10, NAME = N'${dbName} Differential Backup';"
            }
            'LOG' {
"BACKUP LOG [$dbName]
 TO DISK = N'$filePath'
 WITH COMPRESSION, CHECKSUM, STATS = 10, NAME = N'${dbName} Log Backup';"
            }
        }

        try {
            if ($PSCmdlet.ShouldProcess("[$instance].[$dbName]", "$BackupType backup to $filePath")) {
                Write-Log "Backing up [$dbName] → $fileName"
                Invoke-Sqlcmd -ServerInstance $instance -Query $backupSql `
                    -QueryTimeout 3600 -ErrorAction Stop
                Write-Log "  ✔ Completed [$dbName]"
            }
        } catch {
            Write-Log "  ✘ Failed [$dbName]: $_" 'ERROR'
        }
    }

    # ── Retention cleanup ────────────────────────────────────────────────────
    Write-Log "Cleaning up $BackupType files older than $RetentionDays days in $instanceFolder"
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -Path $instanceFolder -Filter "*_${BackupType}_*.${ext}" |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.FullName, 'Delete old backup')) {
                Remove-Item $_.FullName -Force
                Write-Log "  Deleted: $($_.Name)"
            }
        }
}

Write-Log "=== Backup run complete ==="
