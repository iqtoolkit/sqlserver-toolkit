<#
.SYNOPSIS
    Reports SQL Agent job failures from the past N hours across one or more
    SQL Server instances.

.DESCRIPTION
    Queries msdb.dbo.sysjobhistory for failed steps, summarises them by job,
    and optionally sends a consolidated email alert.

.PARAMETER SqlInstances
    One or more SQL Server instance names.

.PARAMETER LookbackHours
    How many hours back to check.  Default: 24.

.PARAMETER SmtpServer
    SMTP relay for email alerts.  Leave empty to disable.

.PARAMETER AlertTo
    Alert recipient email address.

.PARAMETER AlertFrom
    Alert sender email address.

.EXAMPLE
    .\Get-JobFailures.ps1 -SqlInstances "SQL01","SQL02" -LookbackHours 12

.REQUIREMENTS
    SqlServer PowerShell module  (Install-Module SqlServer)
    SQLAgentReaderRole or sysadmin on each instance
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string[]] $SqlInstances,

    [int]    $LookbackHours = 24,
    [string] $SmtpServer    = '',
    [string] $AlertTo       = '',
    [string] $AlertFrom     = ''
)

Set-StrictMode -Version Latest

$SqlJobFailures = @"
DECLARE @since DATETIME = DATEADD(HOUR, -$LookbackHours, GETDATE());

SELECT
    j.name                                      AS job_name,
    h.step_id,
    h.step_name,
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS run_at,
    h.run_duration,
    LEFT(h.message, 500)                        AS error_message
FROM msdb.dbo.sysjobs          j
JOIN msdb.dbo.sysjobhistory    h  ON h.job_id = j.job_id
WHERE h.run_status = 0   -- 0 = failed
  AND msdb.dbo.agent_datetime(h.run_date, h.run_time) >= @since
ORDER BY run_at DESC;
"@

$allFailures = [System.Collections.Generic.List[hashtable]]::new()

foreach ($instance in $SqlInstances) {
    Write-Host "`n[$instance] Checking last ${LookbackHours}h..." -ForegroundColor Cyan

    try {
        $rows = Invoke-Sqlcmd -ServerInstance $instance -Query $SqlJobFailures `
            -ConnectionTimeout 10 -ErrorAction Stop
    } catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
        continue
    }

    if (-not $rows) {
        Write-Host "  ✔ No job failures" -ForegroundColor Green
        continue
    }

    foreach ($row in $rows) {
        Write-Host ("  ✘ {0} — step [{1}] {2} — {3}" -f `
            $row.job_name, $row.step_id, $row.step_name, $row.run_at) -ForegroundColor Red
        Write-Host ("    {0}" -f $row.error_message.Substring(0, [Math]::Min(120, $row.error_message.Length))) `
            -ForegroundColor Gray
        $allFailures.Add(@{
            Instance     = $instance
            Job          = $row.job_name
            Step         = $row.step_name
            RunAt        = $row.run_at
            ErrorMessage = $row.error_message
        })
    }
}

if ($allFailures.Count -gt 0 -and $SmtpServer -and $AlertTo) {
    $body = $allFailures | ForEach-Object {
        "[$($_.Instance)] $($_.Job) / $($_.Step) at $($_.RunAt)`n  $($_.ErrorMessage)`n"
    }
    try {
        Send-MailMessage -SmtpServer $SmtpServer -To $AlertTo -From $AlertFrom `
            -Subject "SQL Agent Failures: $($allFailures.Count) in last ${LookbackHours}h" `
            -Body ($body -join "`n") -ErrorAction Stop
        Write-Host "`nAlert sent to $AlertTo" -ForegroundColor Cyan
    } catch {
        Write-Host "Alert email failed: $_" -ForegroundColor Red
    }
}

Write-Host "`nTotal failures found: $($allFailures.Count)" -ForegroundColor (
    if ($allFailures.Count -gt 0) { 'Red' } else { 'Green' }
)
