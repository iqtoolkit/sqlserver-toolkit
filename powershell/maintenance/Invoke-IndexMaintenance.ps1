<#
.SYNOPSIS
    Performs index REBUILD or REORGANIZE across all user databases based on
    fragmentation thresholds, with optional statistics update.

.DESCRIPTION
    For each index in each online user database:
      - Fragmentation >= RebuildThresholdPct  → REBUILD (online if edition supports it)
      - Fragmentation >= ReorgThresholdPct    → REORGANIZE
      - Fragmentation <  ReorgThresholdPct    → skip

    After index work, runs UPDATE STATISTICS for each database if
    UpdateStatistics is set.

    Results are logged to a file and summarised on the console.

.PARAMETER SqlInstance
    Target SQL Server instance.

.PARAMETER RebuildThresholdPct
    Fragmentation % at or above which REBUILD is used.  Default: 30.

.PARAMETER ReorgThresholdPct
    Fragmentation % at or above which REORGANIZE is used.  Default: 10.

.PARAMETER MinPageCount
    Minimum page count to consider an index for maintenance.  Default: 100.

.PARAMETER OnlineRebuild
    Use ONLINE = ON for REBUILD when the edition supports it.  Default: $false.

.PARAMETER UpdateStatistics
    Run UPDATE STATISTICS after index work.  Default: $true.

.PARAMETER ExcludeDatabases
    Databases to skip.

.PARAMETER LogPath
    Log file path.  Default: %TEMP%\IndexMaintenance_yyyyMMdd.log.

.EXAMPLE
    .\Invoke-IndexMaintenance.ps1 -SqlInstance "SQL01"

.EXAMPLE
    .\Invoke-IndexMaintenance.ps1 -SqlInstance "SQL01" -OnlineRebuild -RebuildThresholdPct 25

.REQUIREMENTS
    SqlServer PowerShell module  (Install-Module SqlServer)
    db_owner or ALTER INDEX on target databases
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string]   $SqlInstance,

    [int]      $RebuildThresholdPct   = 30,
    [int]      $ReorgThresholdPct     = 10,
    [int]      $MinPageCount          = 100,
    [switch]   $OnlineRebuild,
    [bool]     $UpdateStatistics      = $true,
    [string[]] $ExcludeDatabases      = @(),
    [string]   $LogPath               = (Join-Path $env:TEMP ("IndexMaintenance_{0}.log" -f (Get-Date -Format 'yyyyMMdd')))
)

Set-StrictMode -Version Latest

$stats = @{ Rebuilt = 0; Reorganized = 0; Skipped = 0; Errors = 0 }

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message"
    $line | Out-File -FilePath $LogPath -Append
    Write-Host $line -ForegroundColor (switch ($Level) {
        'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'ACTION' { 'Cyan' } default { 'Gray' }
    })
}

# ── Get user databases ───────────────────────────────────────────────────────

$excludeList = (@('master','model','msdb','tempdb') + $ExcludeDatabases |
    ForEach-Object { "'$_'" }) -join ','

$databases = (Invoke-Sqlcmd -ServerInstance $SqlInstance `
    -Query "SELECT name FROM sys.databases WHERE state_desc='ONLINE' AND name NOT IN ($excludeList)" `
    -ErrorAction Stop).name

Write-Log "=== Index maintenance on [$SqlInstance] — $($databases.Count) database(s) ==="
Write-Log "Thresholds: REBUILD >= ${RebuildThresholdPct}%  REORG >= ${ReorgThresholdPct}%  MinPages: $MinPageCount"

# ── Per-database maintenance ─────────────────────────────────────────────────

foreach ($db in $databases) {
    Write-Log "--- [$db] ---"

    $fragSql = @"
SELECT
    OBJECT_SCHEMA_NAME(i.object_id, DB_ID('$db')) AS schema_name,
    OBJECT_NAME(i.object_id, DB_ID('$db'))        AS table_name,
    i.name                                         AS index_name,
    i.index_id,
    s.avg_fragmentation_in_percent,
    s.page_count
FROM sys.dm_db_index_physical_stats(DB_ID('$db'), NULL, NULL, NULL, 'LIMITED') s
JOIN sys.indexes i
    ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE s.index_id > 0
  AND s.page_count >= $MinPageCount
  AND s.avg_fragmentation_in_percent >= $ReorgThresholdPct
ORDER BY s.avg_fragmentation_in_percent DESC;
"@

    try {
        $indexes = Invoke-Sqlcmd -ServerInstance $SqlInstance `
            -Query $fragSql -Database $db -QueryTimeout 300 -ErrorAction Stop
    } catch {
        Write-Log "Failed to get fragmentation data for [$db]: $_" 'ERROR'
        $stats.Errors++
        continue
    }

    if (-not $indexes) {
        Write-Log "  No indexes require maintenance in [$db]"
        continue
    }

    foreach ($idx in $indexes) {
        $frag   = [math]::Round($idx.avg_fragmentation_in_percent, 1)
        $action = if ($frag -ge $RebuildThresholdPct) { 'REBUILD' } else { 'REORGANIZE' }
        $onlineClause = if ($action -eq 'REBUILD' -and $OnlineRebuild) { ' WITH (ONLINE = ON)' } else { '' }

        $sql = "ALTER INDEX [$($idx.index_name)] ON [$db].[$($idx.schema_name)].[$($idx.table_name)] $action$onlineClause;"

        Write-Log "  $action [$($idx.schema_name)].[$($idx.table_name)].[$($idx.index_name)] (${frag}%)" 'ACTION'

        try {
            if ($PSCmdlet.ShouldProcess("[$db] $($idx.table_name).$($idx.index_name)", $action)) {
                Invoke-Sqlcmd -ServerInstance $SqlInstance -Database $db `
                    -Query $sql -QueryTimeout 3600 -ErrorAction Stop
                if ($action -eq 'REBUILD') { $stats.Rebuilt++ } else { $stats.Reorganized++ }
            }
        } catch {
            Write-Log "  ERROR on $($idx.index_name): $_" 'ERROR'
            $stats.Errors++
        }
    }

    # ── Update statistics ────────────────────────────────────────────────────
    if ($UpdateStatistics) {
        Write-Log "  Updating statistics for [$db]" 'ACTION'
        try {
            if ($PSCmdlet.ShouldProcess($db, 'UPDATE STATISTICS')) {
                Invoke-Sqlcmd -ServerInstance $SqlInstance -Database $db `
                    -Query "EXEC sp_updatestats;" -QueryTimeout 3600 -ErrorAction Stop
            }
        } catch {
            Write-Log "  UPDATE STATISTICS failed for [$db]: $_" 'ERROR'
            $stats.Errors++
        }
    }
}

Write-Log "=== Complete — Rebuilt: $($stats.Rebuilt)  Reorganized: $($stats.Reorganized)  Errors: $($stats.Errors) ==="
Write-Log "Log written to: $LogPath"
