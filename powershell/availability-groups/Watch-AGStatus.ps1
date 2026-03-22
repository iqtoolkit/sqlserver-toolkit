<#
.SYNOPSIS
    Continuously monitors Always On Availability Group health and alerts on
    degraded sync state, replica disconnects, or growing redo/send queues.

.DESCRIPTION
    Polls sys.dm_hadr_* DMVs on the specified interval and writes colour-coded
    output.  Optionally sends an email alert when issues are detected.

.PARAMETER SqlInstance
    Primary replica to query.  Must have VIEW SERVER STATE.

.PARAMETER IntervalSeconds
    Poll interval.  Default: 60 seconds.

.PARAMETER RedoQueueThresholdKB
    Alert if redo queue exceeds this size (KB).  Default: 102400 (100 MB).

.PARAMETER SendQueueThresholdKB
    Alert if send queue exceeds this size (KB).  Default: 51200 (50 MB).

.PARAMETER SmtpServer
    SMTP relay for email alerts.  Leave empty to disable email.

.PARAMETER AlertTo
    Recipient address for email alerts.

.PARAMETER AlertFrom
    Sender address for email alerts.

.EXAMPLE
    .\Watch-AGStatus.ps1 -SqlInstance "SQL01" -IntervalSeconds 30

.EXAMPLE
    .\Watch-AGStatus.ps1 -SqlInstance "SQL01" -SmtpServer "mail.corp.local" `
        -AlertTo "dba@corp.local" -AlertFrom "sqlalerts@corp.local"

.REQUIREMENTS
    SqlServer PowerShell module  (Install-Module SqlServer)
    VIEW SERVER STATE on the primary
    AlwaysOn feature enabled
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $SqlInstance,

    [int]    $IntervalSeconds       = 60,
    [int]    $RedoQueueThresholdKB  = 102400,
    [int]    $SendQueueThresholdKB  = 51200,
    [string] $SmtpServer            = '',
    [string] $AlertTo               = '',
    [string] $AlertFrom             = ''
)

Set-StrictMode -Version Latest

$SqlAGStatus = @"
SELECT
    ag.name                                 AS ag_name,
    ar.replica_server_name                  AS replica,
    ar.availability_mode_desc               AS avail_mode,
    ar.failover_mode_desc                   AS failover_mode,
    ars.role_desc                           AS role,
    ars.operational_state_desc              AS operational_state,
    ars.connected_state_desc                AS connected_state,
    ars.synchronization_health_desc         AS sync_health,
    adb.database_name,
    drs.synchronization_state_desc          AS db_sync_state,
    drs.is_suspended,
    drs.suspend_reason_desc,
    ISNULL(drs.log_send_queue_size,  0)     AS send_queue_kb,
    ISNULL(drs.redo_queue_size,      0)     AS redo_queue_kb,
    ISNULL(drs.log_send_rate,        0)     AS send_rate_kb_s,
    ISNULL(drs.redo_rate,            0)     AS redo_rate_kb_s
FROM sys.availability_groups                    ag
JOIN sys.availability_replicas                  ar  ON ar.group_id         = ag.group_id
JOIN sys.dm_hadr_availability_replica_states    ars ON ars.replica_id      = ar.replica_id
JOIN sys.availability_databases_cluster         adb ON adb.group_id        = ag.group_id
JOIN sys.dm_hadr_database_replica_states        drs ON drs.replica_id      = ar.replica_id
                                                   AND drs.group_database_id = adb.group_database_id
ORDER BY ag.name, ar.replica_server_name, adb.database_name;
"@

function Send-Alert {
    param([string]$Subject, [string]$Body)
    if (-not $SmtpServer -or -not $AlertTo) { return }
    try {
        Send-MailMessage -SmtpServer $SmtpServer -To $AlertTo -From $AlertFrom `
            -Subject $Subject -Body $Body -ErrorAction Stop
        Write-Host "  Alert email sent to $AlertTo" -ForegroundColor Cyan
    } catch {
        Write-Host "  Failed to send alert email: $_" -ForegroundColor Red
    }
}

Write-Host "Monitoring AG health on [$SqlInstance] every ${IntervalSeconds}s — Ctrl+C to stop" -ForegroundColor Cyan

while ($true) {
    $timestamp = Get-Date -Format 'HH:mm:ss'
    Write-Host "`n[$timestamp] Polling AG status..." -ForegroundColor Gray

    $issues = [System.Collections.Generic.List[string]]::new()

    try {
        $rows = Invoke-Sqlcmd -ServerInstance $SqlInstance -Query $SqlAGStatus `
            -ConnectionTimeout 10 -ErrorAction Stop

        # Group by AG for display
        $byAG = $rows | Group-Object ag_name

        foreach ($agGroup in $byAG) {
            Write-Host ("  AG: {0}" -f $agGroup.Name) -ForegroundColor White

            foreach ($row in $agGroup.Group) {
                $color = 'Green'
                $flag  = ''

                if ($row.connected_state -ne 'CONNECTED') {
                    $color = 'Red'; $flag = ' ← DISCONNECTED'
                    $issues.Add("[$($agGroup.Name)] replica $($row.replica) is DISCONNECTED")
                } elseif ($row.sync_health -ne 'HEALTHY') {
                    $color = 'Yellow'; $flag = " ← $($row.sync_health)"
                    $issues.Add("[$($agGroup.Name)] replica $($row.replica) sync health: $($row.sync_health)")
                }

                if ($row.is_suspended) {
                    $color = 'Red'; $flag += ' SUSPENDED'
                    $issues.Add("[$($agGroup.Name)] $($row.replica)/$($row.database_name) is SUSPENDED: $($row.suspend_reason_desc)")
                }

                if ([int]$row.redo_queue_kb -gt $RedoQueueThresholdKB) {
                    $color = 'Yellow'
                    $flag += " redo queue $([math]::Round($row.redo_queue_kb/1024))MB"
                    $issues.Add("[$($agGroup.Name)] $($row.replica)/$($row.database_name) redo queue $($row.redo_queue_kb) KB")
                }

                if ([int]$row.send_queue_kb -gt $SendQueueThresholdKB) {
                    $color = 'Yellow'
                    $flag += " send queue $([math]::Round($row.send_queue_kb/1024))MB"
                }

                Write-Host ("    {0,-20} {1,-20} {2,-12} {3}{4}" -f `
                    $row.replica, $row.database_name, $row.db_sync_state, $row.role, $flag) `
                    -ForegroundColor $color
            }
        }

    } catch {
        $msg = "Query failed: $_"
        Write-Host "  ERROR: $msg" -ForegroundColor Red
        $issues.Add($msg)
    }

    if ($issues.Count -gt 0) {
        Write-Host "  ⚠  $($issues.Count) issue(s) detected" -ForegroundColor Yellow
        Send-Alert -Subject "SQL AG Alert: $SqlInstance" -Body ($issues -join "`n")
    } else {
        Write-Host "  ✔  All AGs healthy" -ForegroundColor Green
    }

    Start-Sleep -Seconds $IntervalSeconds
}
