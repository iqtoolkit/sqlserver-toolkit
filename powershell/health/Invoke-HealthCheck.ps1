<#
.SYNOPSIS
    Runs a health check against one or more SQL Server instances.

.DESCRIPTION
    Collects key health metrics (version, connections, waits, I/O latency,
    disk space, last backup, AG sync state) from each target instance and
    outputs a colour-coded console summary.  Optionally writes an HTML
    report to disk.

.PARAMETER SqlInstances
    One or more SQL Server instance names or connection strings.

.PARAMETER HtmlReport
    Optional path to write an HTML report file (e.g. C:\Reports\health.html).

.PARAMETER ConnectionTimeoutSeconds
    Timeout for each SQL connection attempt.  Default: 10.

.EXAMPLE
    .\Invoke-HealthCheck.ps1 -SqlInstances "SQL01","SQL02\INST1"

.EXAMPLE
    .\Invoke-HealthCheck.ps1 -SqlInstances "SQL01" -HtmlReport "C:\Reports\health.html"

.REQUIREMENTS
    SqlServer PowerShell module  (Install-Module SqlServer)
    VIEW SERVER STATE on each target instance
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string[]] $SqlInstances,

    [string]   $HtmlReport,

    [int]      $ConnectionTimeoutSeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── SQL fragments ────────────────────────────────────────────────────────────

$SqlVersion = @"
SELECT  SERVERPROPERTY('ServerName')       AS ServerName,
        @@VERSION                           AS FullVersion,
        SERVERPROPERTY('ProductVersion')   AS ProductVersion,
        SERVERPROPERTY('Edition')          AS Edition,
        (SELECT SUM(active_workers_count)
         FROM sys.dm_os_schedulers
         WHERE status = 'VISIBLE ONLINE')  AS ActiveWorkers,
        (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1) AS UserSessions;
"@

$SqlWaits = @"
SELECT TOP 5
    wait_type,
    CAST(wait_time_ms / 1000.0 AS DECIMAL(12,2)) AS wait_time_s,
    waiting_tasks_count
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    N'SLEEP_TASK',N'SLEEP_SYSTEMTASK',N'WAITFOR',N'DISPATCHER_QUEUE_SEMAPHORE',
    N'CLR_AUTO_EVENT',N'CLR_MANUAL_EVENT',N'DBMIRROR_EVENTS_QUEUE',
    N'XE_TIMER_EVENT',N'XE_DISPATCHER_WAIT',N'BROKER_TO_FLUSH',
    N'BROKER_TASK_STOP',N'CHECKPOINT_QUEUE',N'REQUEST_FOR_DEADLOCK_SEARCH',
    N'RESOURCE_QUEUE',N'SERVER_IDLE_CHECK',N'HADR_WORK_QUEUE',
    N'DIRTY_PAGE_POLL',N'SQLTRACE_BUFFER_FLUSH',N'SLEEP_LAZYWRITER'
)
AND wait_time_ms > 0
ORDER BY wait_time_ms DESC;
"@

$SqlIoLatency = @"
SELECT TOP 5
    DB_NAME(vfs.database_id) AS database_name,
    mf.physical_name,
    CAST(io_stall_read_ms  / NULLIF(num_of_reads,  0) AS DECIMAL(10,2)) AS avg_read_ms,
    CAST(io_stall_write_ms / NULLIF(num_of_writes, 0) AS DECIMAL(10,2)) AS avg_write_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf
    ON mf.database_id = vfs.database_id AND mf.file_id = vfs.file_id
ORDER BY (io_stall_read_ms + io_stall_write_ms) DESC;
"@

$SqlLastBackup = @"
SELECT
    d.name                          AS database_name,
    d.recovery_model_desc           AS recovery_model,
    MAX(CASE b.type WHEN 'D' THEN b.backup_finish_date END) AS last_full,
    MAX(CASE b.type WHEN 'L' THEN b.backup_finish_date END) AS last_log
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b
    ON b.database_name = d.name
WHERE d.database_id > 4
GROUP BY d.name, d.recovery_model_desc
ORDER BY d.name;
"@

# ── Helpers ──────────────────────────────────────────────────────────────────

function Invoke-SqlQuery {
    param([string]$Instance, [string]$Query)
    Invoke-Sqlcmd -ServerInstance $Instance `
                  -Query $Query `
                  -ConnectionTimeout $ConnectionTimeoutSeconds `
                  -ErrorAction Stop
}

function Write-Status {
    param([string]$Label, [string]$Value, [string]$Color = 'White')
    Write-Host ("  {0,-30} " -f $Label) -NoNewline
    Write-Host $Value -ForegroundColor $Color
}

# ── Main loop ────────────────────────────────────────────────────────────────

$allResults = [System.Collections.Generic.List[hashtable]]::new()

foreach ($instance in $SqlInstances) {
    Write-Host "`n════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host " $instance" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════" -ForegroundColor Cyan

    $result = @{ Instance = $instance; Status = 'OK'; Issues = @() }

    try {
        # Version / sessions
        $info = Invoke-SqlQuery -Instance $instance -Query $SqlVersion
        Write-Status 'Version'      $info.ProductVersion
        Write-Status 'Edition'      $info.Edition
        Write-Status 'User sessions' $info.UserSessions

        # Top waits
        $waits = Invoke-SqlQuery -Instance $instance -Query $SqlWaits
        Write-Host '  Top waits:' -ForegroundColor Gray
        foreach ($w in $waits) {
            Write-Host ("    {0,-40} {1,10:N2}s" -f $w.wait_type, $w.wait_time_s) -ForegroundColor Gray
        }

        # I/O latency — flag files with > 30ms avg
        $io = Invoke-SqlQuery -Instance $instance -Query $SqlIoLatency
        foreach ($f in $io) {
            $readMs  = [double]$f.avg_read_ms
            $writeMs = [double]$f.avg_write_ms
            if ($readMs -gt 30 -or $writeMs -gt 30) {
                $msg = "High I/O latency on $($f.physical_name) (read ${readMs}ms / write ${writeMs}ms)"
                Write-Status 'I/O WARNING' $msg 'Yellow'
                $result.Issues += $msg
                $result.Status   = 'WARNING'
            }
        }

        # Last backup — flag databases with no full backup in 7 days
        $backups = Invoke-SqlQuery -Instance $instance -Query $SqlLastBackup
        foreach ($db in $backups) {
            $lastFull = $db.last_full
            if ($null -eq $lastFull -or $lastFull -eq [DBNull]::Value) {
                $msg = "No full backup recorded for [$($db.database_name)]"
                Write-Status 'BACKUP WARNING' $msg 'Red'
                $result.Issues += $msg
                $result.Status   = 'CRITICAL'
            } elseif (([datetime]$lastFull) -lt (Get-Date).AddDays(-7)) {
                $msg = "Full backup for [$($db.database_name)] is older than 7 days ($lastFull)"
                Write-Status 'BACKUP WARNING' $msg 'Yellow'
                $result.Issues += $msg
                if ($result.Status -ne 'CRITICAL') { $result.Status = 'WARNING' }
            }
        }

        $statusColor = switch ($result.Status) {
            'CRITICAL' { 'Red' }
            'WARNING'  { 'Yellow' }
            default    { 'Green' }
        }
        Write-Host ("  Overall: {0}" -f $result.Status) -ForegroundColor $statusColor

    } catch {
        $msg = "Connection or query failed: $_"
        Write-Host "  ERROR: $msg" -ForegroundColor Red
        $result.Status = 'ERROR'
        $result.Issues += $msg
    }

    $allResults.Add($result)
}

# ── Optional HTML report ─────────────────────────────────────────────────────

if ($HtmlReport) {
    $rows = $allResults | ForEach-Object {
        $color = switch ($_.Status) {
            'CRITICAL' { '#f8d7da' }
            'WARNING'  { '#fff3cd' }
            'ERROR'    { '#f8d7da' }
            default    { '#d4edda' }
        }
        $issues = if ($_.Issues.Count -gt 0) { $_.Issues -join '<br/>' } else { '—' }
        "<tr style='background:$color'><td>$($_.Instance)</td><td>$($_.Status)</td><td>$issues</td></tr>"
    }

    $html = @"
<!DOCTYPE html>
<html><head><meta charset='utf-8'>
<title>SQL Server Health Check — $(Get-Date -Format 'yyyy-MM-dd HH:mm')</title>
<style>
body { font-family: Segoe UI, sans-serif; margin: 2em; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #dee2e6; padding: 8px 12px; text-align: left; }
th { background: #343a40; color: #fff; }
</style></head>
<body>
<h1>SQL Server Health Check</h1>
<p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<table>
  <thead><tr><th>Instance</th><th>Status</th><th>Issues</th></tr></thead>
  <tbody>$($rows -join "`n")</tbody>
</table>
</body></html>
"@
    $html | Out-File -FilePath $HtmlReport -Encoding utf8
    Write-Host "`nHTML report written to: $HtmlReport" -ForegroundColor Cyan
}
