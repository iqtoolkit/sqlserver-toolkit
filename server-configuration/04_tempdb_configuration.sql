-- ============================================================
-- Script: TempDB Configuration Review
-- Description: Reviews tempdb data and log file configuration,
--              checks for contention (PAGELATCH waits on
--              allocation pages), and reports current usage.
-- Applies to: SQL Server 2008 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. TempDB file configuration
-- -------------------------------------------------------
USE tempdb;
GO

SELECT
    name                                    AS logical_name,
    physical_name,
    type_desc,
    state_desc,
    CAST(size * 8.0 / 1024 AS DECIMAL(18,2)) AS size_mb,
    CAST(
        FILEPROPERTY(name, 'SpaceUsed') * 8.0 / 1024
    AS DECIMAL(18,2))                       AS used_mb,
    CAST(
        (size - FILEPROPERTY(name, 'SpaceUsed')) * 8.0 / 1024
    AS DECIMAL(18,2))                       AS free_mb,
    growth,
    is_percent_growth,
    max_size
FROM sys.database_files
ORDER BY type, file_id;
GO

-- -------------------------------------------------------
-- 2. TempDB allocation page contention
--    (PAGELATCH waits on pages 2, 3 indicate too few data files)
-- -------------------------------------------------------
SELECT
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    resource_description
FROM sys.dm_os_waiting_tasks
WHERE wait_type LIKE N'PAGELATCH%'
  AND resource_description LIKE N'2:%'     -- tempdb = database_id 2
ORDER BY wait_time_ms DESC;
GO

-- -------------------------------------------------------
-- 3. Identify sessions using the most tempdb space
-- -------------------------------------------------------
SELECT TOP 20
    r.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    CAST(SUM(tsu.user_objects_alloc_page_count  -
             tsu.user_objects_dealloc_page_count) * 8.0 / 1024
        AS DECIMAL(18,2))                   AS user_objects_mb,
    CAST(SUM(tsu.internal_objects_alloc_page_count -
             tsu.internal_objects_dealloc_page_count) * 8.0 / 1024
        AS DECIMAL(18,2))                   AS internal_objects_mb,
    SUBSTRING(t.text, (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)
          ELSE r.statement_end_offset END - r.statement_start_offset) / 2) + 1
    )                                       AS current_statement
FROM sys.dm_db_task_space_usage         tsu
JOIN sys.dm_exec_requests               r   ON r.session_id = tsu.session_id
                                           AND r.request_id = tsu.request_id
JOIN sys.dm_exec_sessions               s   ON s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE tsu.session_id > 50
GROUP BY r.session_id, s.login_name, s.host_name, s.program_name,
         t.text, r.statement_start_offset, r.statement_end_offset
ORDER BY (SUM(tsu.user_objects_alloc_page_count - tsu.user_objects_dealloc_page_count)
        + SUM(tsu.internal_objects_alloc_page_count - tsu.internal_objects_dealloc_page_count)) DESC;
GO

-- -------------------------------------------------------
-- Best practice reminder:
--   Number of tempdb data files = number of logical CPU cores
--   (up to 8; after 8, add in groups of 4 only if contention persists)
-- -------------------------------------------------------
