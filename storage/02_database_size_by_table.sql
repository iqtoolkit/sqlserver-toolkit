-- ============================================================
-- Script: Database Size by Table
-- Description: Reports the top tables by row count, reserved
--              space, data space, index space, and unused
--              space within the current database.
-- Applies to: SQL Server 2008 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. Database-level size summary
-- -------------------------------------------------------
SELECT
    DB_NAME()                           AS database_name,
    SUM(CASE type WHEN 0 THEN size END) * 8 / 1024  AS data_size_mb,
    SUM(CASE type WHEN 1 THEN size END) * 8 / 1024  AS log_size_mb,
    SUM(size) * 8 / 1024                            AS total_size_mb
FROM sys.database_files;
GO

-- -------------------------------------------------------
-- 2. Top 50 tables by total reserved space
-- -------------------------------------------------------
SELECT TOP 50
    s.name                              AS schema_name,
    t.name                              AS table_name,
    p.rows                              AS row_count,
    CAST(SUM(au.total_pages)   * 8.0 / 1024 AS DECIMAL(18,2)) AS reserved_mb,
    CAST(SUM(au.used_pages)    * 8.0 / 1024 AS DECIMAL(18,2)) AS used_mb,
    CAST(SUM(au.data_pages)    * 8.0 / 1024 AS DECIMAL(18,2)) AS data_mb,
    CAST((SUM(au.used_pages) - SUM(au.data_pages)) * 8.0 / 1024
        AS DECIMAL(18,2))               AS index_mb,
    CAST((SUM(au.total_pages) - SUM(au.used_pages)) * 8.0 / 1024
        AS DECIMAL(18,2))               AS unused_mb
FROM sys.tables             t
JOIN sys.schemas             s  ON s.schema_id   = t.schema_id
JOIN sys.indexes             i  ON i.object_id   = t.object_id
JOIN sys.partitions          p  ON p.object_id   = i.object_id
                               AND p.index_id    = i.index_id
JOIN sys.allocation_units    au ON au.container_id =
    CASE
        WHEN au.type IN (1,3) THEN p.hobt_id
        ELSE p.partition_id
    END
WHERE t.is_ms_shipped = 0
GROUP BY s.name, t.name, p.rows
ORDER BY SUM(au.total_pages) DESC;
GO

-- -------------------------------------------------------
-- 3. VLF (Virtual Log File) count per database
--    High VLF counts (> 1000) can slow down recovery.
-- -------------------------------------------------------
IF OBJECT_ID('tempdb..#VLF') IS NOT NULL DROP TABLE #VLF;
CREATE TABLE #VLF (
    RecoveryUnitId BIGINT,
    FileId         INT,
    FileSize       BIGINT,
    StartOffset    BIGINT,
    FSeqNo         BIGINT,
    Status         INT,
    Parity         INT,
    CreateLSN      NUMERIC(25, 0)
);

DECLARE @dbName SYSNAME;
DECLARE @vlf_count INT;
DECLARE db_cur CURSOR FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE state_desc = N'ONLINE' ORDER BY name;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @dbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    TRUNCATE TABLE #VLF;
    INSERT INTO #VLF EXEC (N'DBCC LOGINFO (' + QUOTENAME(@dbName, '''') + N') WITH NO_INFOMSGS;');
    SELECT @vlf_count = COUNT(*) FROM #VLF;
    PRINT @dbName + N': ' + CAST(@vlf_count AS NVARCHAR) + N' VLFs';
    FETCH NEXT FROM db_cur INTO @dbName;
END;

CLOSE db_cur;
DEALLOCATE db_cur;
DROP TABLE #VLF;
GO
