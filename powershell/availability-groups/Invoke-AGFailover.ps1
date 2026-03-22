<#
.SYNOPSIS
    Orchestrates a planned manual failover for a SQL Server Always On
    Availability Group with pre-flight checks and confirmation prompts.

.DESCRIPTION
    Performs the following steps:
      1. Verifies the target replica is SYNCHRONIZED and CONNECTED.
      2. Verifies the AG is in AUTOMATIC or MANUAL failover mode.
      3. Shows the current primary and asks for explicit confirmation.
      4. Executes ALTER AVAILABILITY GROUP ... FAILOVER on the target replica.
      5. Polls for the new primary to come online (up to WaitSeconds).

    This script does NOT perform forced failover with data loss.
    For forced failover use the T-SQL script: availability-groups/02_ag_failover.sql

.PARAMETER TargetReplica
    The SQL Server instance to fail over TO (the new primary).

.PARAMETER AGName
    Name of the Availability Group to fail over.

.PARAMETER WaitSeconds
    Seconds to poll for the new primary to come online.  Default: 120.

.PARAMETER Force
    Suppress the interactive confirmation prompt.

.EXAMPLE
    .\Invoke-AGFailover.ps1 -TargetReplica "SQL02" -AGName "AG_Production"

.EXAMPLE
    .\Invoke-AGFailover.ps1 -TargetReplica "SQL02" -AGName "AG_Production" -Force

.REQUIREMENTS
    SqlServer PowerShell module  (Install-Module SqlServer)
    ALTER AVAILABILITY GROUP permission on the target replica
    AlwaysOn feature enabled
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string] $TargetReplica,

    [Parameter(Mandatory)]
    [string] $AGName,

    [int]    $WaitSeconds = 120,

    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-SqlQuery {
    param([string]$Instance, [string]$Query)
    Invoke-Sqlcmd -ServerInstance $Instance -Query $Query `
        -ConnectionTimeout 15 -ErrorAction Stop
}

# ── Pre-flight: query current state from the target replica ──────────────────

Write-Host "`nPre-flight checks on [$TargetReplica] for AG [$AGName]..." -ForegroundColor Cyan

$preflightSql = @"
SELECT
    ag.name                                 AS ag_name,
    ar.replica_server_name                  AS replica,
    ars.role_desc                           AS role,
    ars.operational_state_desc              AS operational_state,
    ars.connected_state_desc                AS connected_state,
    ars.synchronization_health_desc         AS sync_health,
    ar.failover_mode_desc                   AS failover_mode
FROM sys.availability_groups                    ag
JOIN sys.availability_replicas                  ar  ON ar.group_id    = ag.group_id
JOIN sys.dm_hadr_availability_replica_states    ars ON ars.replica_id = ar.replica_id
WHERE ag.name = N'$AGName'
ORDER BY ars.role_desc;
"@

try {
    $replicas = Invoke-SqlQuery -Instance $TargetReplica -Query $preflightSql
} catch {
    Write-Host "ERROR: Cannot connect to [$TargetReplica] or AG [$AGName] not found." -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    exit 1
}

if (-not $replicas) {
    Write-Host "ERROR: No replicas found for AG [$AGName]." -ForegroundColor Red
    exit 1
}

$currentPrimary = ($replicas | Where-Object { $_.role -eq 'PRIMARY' }).replica
$targetState    = $replicas | Where-Object { $_.replica -eq $TargetReplica }

Write-Host ""
Write-Host "  Current primary : $currentPrimary" -ForegroundColor White
Write-Host "  Target replica  : $TargetReplica"  -ForegroundColor White

if (-not $targetState) {
    Write-Host "ERROR: [$TargetReplica] is not a replica in AG [$AGName]." -ForegroundColor Red
    exit 1
}

# Check sync health
if ($targetState.sync_health -ne 'HEALTHY') {
    Write-Host "ERROR: Target replica sync health is '$($targetState.sync_health)' — must be HEALTHY before failover." -ForegroundColor Red
    exit 1
}

if ($targetState.connected_state -ne 'CONNECTED') {
    Write-Host "ERROR: Target replica is '$($targetState.connected_state)' — must be CONNECTED before failover." -ForegroundColor Red
    exit 1
}

Write-Host "  Sync health     : $($targetState.sync_health)" -ForegroundColor Green
Write-Host "  Connected state : $($targetState.connected_state)" -ForegroundColor Green
Write-Host "  Failover mode   : $($targetState.failover_mode)" -ForegroundColor White
Write-Host ""
Write-Host "All pre-flight checks passed." -ForegroundColor Green

# ── Confirmation ─────────────────────────────────────────────────────────────

if (-not $Force) {
    $confirm = Read-Host "`nFail over AG [$AGName] from [$currentPrimary] to [$TargetReplica]? (yes/no)"
    if ($confirm -ne 'yes') {
        Write-Host "Failover cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# ── Execute failover ─────────────────────────────────────────────────────────

if ($PSCmdlet.ShouldProcess("AG [$AGName]", "Planned failover to [$TargetReplica]")) {
    Write-Host "`nExecuting failover..." -ForegroundColor Cyan
    try {
        Invoke-SqlQuery -Instance $TargetReplica `
            -Query "ALTER AVAILABILITY GROUP [$AGName] FAILOVER;"
        Write-Host "Failover command issued successfully." -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failover command failed: $_" -ForegroundColor Red
        exit 1
    }
}

# ── Poll for new primary ─────────────────────────────────────────────────────

Write-Host "Waiting for [$TargetReplica] to become PRIMARY (timeout: ${WaitSeconds}s)..." -ForegroundColor Cyan

$elapsed    = 0
$pollEvery  = 5
$newPrimary = $null

while ($elapsed -lt $WaitSeconds) {
    Start-Sleep -Seconds $pollEvery
    $elapsed += $pollEvery

    try {
        $check = Invoke-SqlQuery -Instance $TargetReplica -Query @"
SELECT ars.role_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ar.group_id = ag.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ars.replica_id = ar.replica_id
WHERE ag.name = N'$AGName'
  AND ar.replica_server_name = N'$TargetReplica';
"@
        if ($check.role_desc -eq 'PRIMARY') {
            $newPrimary = $TargetReplica
            break
        }
    } catch {
        # Transient during role transition — keep polling
    }

    Write-Host "  ${elapsed}s — waiting..." -ForegroundColor Gray
}

if ($newPrimary) {
    Write-Host "`n✔ Failover complete. [$TargetReplica] is now PRIMARY." -ForegroundColor Green
} else {
    Write-Host "`n⚠ Timeout reached. Verify AG state manually." -ForegroundColor Yellow
    exit 1
}
