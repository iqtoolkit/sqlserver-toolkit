-- ============================================================
-- Script: Disk Space & Database File Growth
-- Description: Reports disk space per volume (via xp_fixeddrives
--              and dm_os_volume_stats), database file sizes, and
--              auto-growth events from the default trace.
-- Applies to: SQL Server 2008 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. Available disk space per drive (legacy xp_fixeddrives)
-- -------------------------------------------------------
CREATE TABLE #DriveSpace (Drive CHAR(1), FreeSpaceMB INT);
INSERT INTO #DriveSpace EXEC master.dbo.xp_fixeddrives;

SELECT
    Drive,
    FreeSpaceMB / 1024.0                AS free_gb
FROM #DriveSpace
ORDER BY Drive;

DROP TABLE #DriveSpace;
GO

-- -------------------------------------------------------
-- 2. Accurate volume stats per database file
--    (SQL Server 2008 R2 SP1 / SQL Server 2012 and later)
-- -------------------------------------------------------
SELECT DISTINCT
    vs.volume_mount_point,
    vs.logical_volume_name,
    CAST(vs.total_bytes / 1073741824.0  AS DECIMAL(18,2)) AS total_gb,
    CAST(vs.available_bytes / 1073741824.0 AS DECIMAL(18,2)) AS available_gb,
    CAST(100.0 * vs.available_bytes / vs.total_bytes AS DECIMAL(5,2)) AS pct_free,
    DB_NAME(mf.database_id)             AS database_using_volume,
    mf.physical_name
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
ORDER BY vs.volume_mount_point, DB_NAME(mf.database_id);
GO

-- -------------------------------------------------------
-- 3. All database files — current size and growth settings
-- -------------------------------------------------------
SELECT
    DB_NAME(database_id)                AS database_name,
    name                                AS logical_name,
    physical_name,
    type_desc                           AS file_type,
    CAST(size * 8.0 / 1024  AS DECIMAL(18,2)) AS size_mb,
    CASE max_size
        WHEN -1  THEN 'Unlimited'
        WHEN 0   THEN 'No growth'
        ELSE CAST(max_size * 8.0 / 1024 AS NVARCHAR(20)) + ' MB'
    END                                 AS max_size,
    CASE is_percent_growth
        WHEN 1 THEN CAST(growth AS NVARCHAR(10)) + ' %'
        ELSE CAST(growth * 8.0 / 1024 AS NVARCHAR(20)) + ' MB'
    END                                 AS growth_increment,
    is_percent_growth
FROM sys.master_files
ORDER BY database_id, type_desc;
GO

-- -------------------------------------------------------
-- 4. Auto-growth events from the default trace (last 7 days)
-- -------------------------------------------------------
DECLARE @tracePath NVARCHAR(500);
SELECT @tracePath = path FROM sys.traces WHERE is_default = 1;

SELECT
    te.name                                 AS event_name,
    t.DatabaseName,
    t.FileName,
    t.Duration / 1000                       AS duration_ms,
    t.IntegerData * 8 / 1024               AS growth_mb,
    t.StartTime,
    t.EndTime,
    CAST(t.FileSize / 1048576.0 AS DECIMAL(18,2)) AS new_size_mb
FROM fn_trace_gettable(@tracePath, DEFAULT) t
JOIN sys.trace_events te ON te.trace_event_id = t.EventClass
WHERE te.name IN (N'Data File Auto Grow', N'Log File Auto Grow')
  AND t.StartTime >= DATEADD(DAY, -7, GETDATE())
ORDER BY t.StartTime DESC;
GO
