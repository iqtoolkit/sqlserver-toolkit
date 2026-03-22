-- ============================================================
-- Script: Shrink Database Files
-- Description: Reports file sizes and free space, then
--              optionally truncates log files that have grown
--              due to a specific event (e.g., after a large
--              bulk operation).
-- IMPORTANT:   Routine shrinking causes index fragmentation and
--              hurts performance.  Use this script only when a
--              file has grown unexpectedly and you need to
--              reclaim space, not as a scheduled job.
-- Applies to: SQL Server 2008 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. Report all database files with used / free space
-- -------------------------------------------------------
SELECT
    DB_NAME(database_id)                AS database_name,
    name                                AS logical_name,
    physical_name,
    type_desc                           AS file_type,
    CAST(size * 8 / 1024.0 AS DECIMAL(18,2))      AS total_size_mb,
    CAST(FILEPROPERTY(name, 'SpaceUsed') * 8 / 1024.0 AS DECIMAL(18,2)) AS used_mb,
    CAST((size - FILEPROPERTY(name, 'SpaceUsed')) * 8 / 1024.0 AS DECIMAL(18,2)) AS free_mb,
    CAST(
        100.0 * (size - FILEPROPERTY(name, 'SpaceUsed')) / NULLIF(size, 0)
    AS DECIMAL(5,2))                    AS free_pct,
    growth,
    is_percent_growth,
    max_size
FROM sys.master_files
ORDER BY database_id, type_desc;
GO

-- -------------------------------------------------------
-- 2. Shrink a specific LOG file (use with caution)
-- -------------------------------------------------------
-- USE [<DatabaseName>];
-- GO
-- -- Step A: Truncate the log (only for SIMPLE recovery or after log backup)
-- CHECKPOINT;
-- -- Step B: Shrink to target size in MB
-- DBCC SHRINKFILE (N'<LogicalLogFileName>', <TargetSizeMB>);
-- GO

-- -------------------------------------------------------
-- 3. Shrink a specific DATA file (use with extreme caution)
-- -------------------------------------------------------
-- USE [<DatabaseName>];
-- GO
-- DBCC SHRINKFILE (N'<LogicalDataFileName>', <TargetSizeMB>);
-- GO
