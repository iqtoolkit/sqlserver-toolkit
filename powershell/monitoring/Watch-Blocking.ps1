<#
.SYNOPSIS
    Polls for blocking chains on a SQL Server instance and alerts when
    the blocking duration exceeds a configurable threshold.

.DESCRIPTION
    Queries sys.dm_exec_requests and sys.dm_exec_sessions on each poll cycle.
    When a blocking chain is found where the head blocker has been waiting
    longer than BlockingThresholdSeconds:
      - Prints the full blocking chain to the console.
      - Optionally sends an email alert.
      - Optionally captures sp_who2 and the blocking session's query text
        to a log file for post-incident review.

.PARAMETER SqlInstance
    SQL Server instance to monitor.

.PARAMETER IntervalSeconds
    Poll interval.  Default: 15 seconds.

.PARAMETER BlockingThresholdSeconds
    Only alert when the head blocker has been waiting at least this many
    seconds.  Default: 30.

.PARAMETER LogPath
    File to append blocking incidents to.  Default: %TEMP%\blocking_log.txt.

.PARAMETER SmtpServer
    SMTP relay for email alerts.  Leave empty to disable.

.PARAMETER AlertTo
    Alert recipient email address.

.PARAMETER AlertFrom
    Alert sender email address.

.EXAMPLE
    .\Watch-Blocking.ps1 -SqlInstance "SQL01" -BlockingThresholdSeconds 60

.REQUIREMENTS
    SqlServer PowerShell module  (Install-Module SqlServer)
    VIEW SERVER STATE on the target instance
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $SqlInstance,

    [int]    $IntervalSeconds           = 15,
    [int]    $BlockingThresholdSeconds  = 30,
    [string] $LogPath                   = (Join-Path $env:TEMP 'blocking_log.txt'),
    [string] $SmtpServer                = '',
    [string] $AlertTo                   = '',
    [string] $AlertFrom                 = ''
)

Set-StrictMode -Version Latest

$SqlBlocking = @"
SELECT
    r.session_id,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time / 1000                          AS wait_seconds,
    r.status,
    r.command,
    DB_NAME(r.database_id)                      AS database_name,
    s.login_name,
    s.host_name,
    s.program_name,
    LEFT(ISNULL(qt.text,''), 512)               AS query_text,
    r.cpu_time,
    r.logical_reads
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions  s  ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) qt
WHERE r.blocking_session_id > 0
   OR r.session_id IN (
       SELECT DISTINCT blocking_session_id
       FROM sys.dm_exec_requests
       WHERE blocking_session_id > 0
   )
ORDER BY r.blocking_session_id, r.session_id;
"@

function Write-Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    $line | Out-File -FilePath $LogPath -Append
    Write-Host $line
}

function Send-Alert {
    param([string]$Subject, [string]$Body)
    if (-not $SmtpServer -or -not $AlertTo) { return }
    try {
        Send-MailMessage -SmtpServer $SmtpServer -To $AlertTo -From $AlertFrom `
            -Subject $Subject -Body $Body -ErrorAction Stop
    } catch {
        Write-Host "Alert email failed: $_" -ForegroundColor Red
    }
}

function Build-BlockingTree {
    param($Rows)
    # Find head blockers (sessions that are blocking but not themselves blocked)
    $blockedIds = $Rows | Where-Object { $_.blocking_session_id -gt 0 } |
        Select-Object -ExpandProperty session_id

    $headBlockers = $Rows | Where-Object {
        $_.blocking_session_id -eq 0 -and $_.session_id -in $blockedIds
    }
    return $headBlockers
}

Write-Host "Watching for blocking on [$SqlInstance] (threshold: ${BlockingThresholdSeconds}s, poll: ${IntervalSeconds}s) — Ctrl+C to stop" -ForegroundColor Cyan

$lastAlertTime = [datetime]::MinValue

while ($true) {
    try {
        $rows = Invoke-Sqlcmd -ServerInstance $SqlInstance -Query $SqlBlocking `
            -ConnectionTimeout 10 -ErrorAction Stop
    } catch {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Query failed: $_" -ForegroundColor Red
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }

    if (-not $rows) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ✔ No blocking" -ForegroundColor Green
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }

    $headBlockers = Build-BlockingTree -Rows $rows
    $maxWait = ($rows | Measure-Object -Property wait_seconds -Maximum).Maximum

    if ($maxWait -lt $BlockingThresholdSeconds) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Blocking present but under threshold (max ${maxWait}s)" -ForegroundColor Gray
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }

    # ── Threshold exceeded — log and alert ───────────────────────────────────
    Write-Host ""
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ⚠  BLOCKING DETECTED (max ${maxWait}s)" -ForegroundColor Red

    $logLines = [System.Collections.Generic.List[string]]::new()
    $logLines.Add("=== BLOCKING INCIDENT — $(Get-Date) ===")
    $logLines.Add("Head blocker(s):")

    foreach ($hb in $headBlockers) {
        $line = "  SPID $($hb.session_id) [$($hb.login_name) on $($hb.host_name)] — $($hb.database_name) — wait ${maxWait}s"
        Write-Host $line -ForegroundColor Red
        $logLines.Add($line)
        $logLines.Add("  Query: $($hb.query_text)")
    }

    Write-Host "  Blocked sessions:"
    foreach ($row in ($rows | Where-Object { $_.blocking_session_id -gt 0 })) {
        $line = "    SPID $($row.session_id) blocked by $($row.blocking_session_id) — wait $($row.wait_seconds)s ($($row.wait_type)) — $($row.query_text.Substring(0,[Math]::Min(120,$row.query_text.Length)))"
        Write-Host $line -ForegroundColor Yellow
        $logLines.Add($line)
    }

    $logLines | ForEach-Object { Write-Log $_ }

    # Rate-limit email alerts to once per 5 minutes
    if ((Get-Date) - $lastAlertTime -gt [timespan]::FromMinutes(5)) {
        Send-Alert -Subject "SQL Blocking Alert: $SqlInstance (${maxWait}s)" `
                   -Body ($logLines -join "`n")
        $lastAlertTime = Get-Date
    }

    Start-Sleep -Seconds $IntervalSeconds
}
