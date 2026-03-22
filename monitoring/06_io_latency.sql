-- ============================================================
-- Script: I/O Latency & Disk Performance
-- Description: Reports cumulative I/O latency per database
--              file since the last SQL Server restart, and
--              identifies files with high read or write
--              latency.
-- Applies to: SQL Server 2008 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. Per-file I/O latency
-- -------------------------------------------------------
SELECT
    DB_NAME(fs.database_id)             AS database_name,
    mf.name                             AS logical_file_name,
    mf.physical_name,
    mf.type_desc                        AS file_type,
    fs.io_stall_read_ms,
    fs.num_of_reads,
    CASE WHEN fs.num_of_reads  > 0
         THEN CAST(fs.io_stall_read_ms  / fs.num_of_reads  AS DECIMAL(10,2))
         ELSE 0 END                     AS avg_read_latency_ms,
    fs.io_stall_write_ms,
    fs.num_of_writes,
    CASE WHEN fs.num_of_writes > 0
         THEN CAST(fs.io_stall_write_ms / fs.num_of_writes AS DECIMAL(10,2))
         ELSE 0 END                     AS avg_write_latency_ms,
    fs.io_stall                         AS total_io_stall_ms,
    CAST(fs.num_of_bytes_read  / 1048576.0 AS DECIMAL(18,2)) AS mb_read,
    CAST(fs.num_of_bytes_written / 1048576.0 AS DECIMAL(18,2)) AS mb_written
FROM sys.dm_io_virtual_file_stats(NULL, NULL) fs
JOIN sys.master_files mf
    ON  mf.database_id = fs.database_id
    AND mf.file_id     = fs.file_id
ORDER BY fs.io_stall DESC;
GO

-- -------------------------------------------------------
-- 2. Files with latency above threshold
--    Adjust the threshold values to suit your environment.
-- -------------------------------------------------------
SELECT
    DB_NAME(fs.database_id)             AS database_name,
    mf.physical_name,
    mf.type_desc,
    CASE WHEN fs.num_of_reads  > 0
         THEN CAST(fs.io_stall_read_ms  / fs.num_of_reads  AS DECIMAL(10,2))
         ELSE 0 END                     AS avg_read_ms,
    CASE WHEN fs.num_of_writes > 0
         THEN CAST(fs.io_stall_write_ms / fs.num_of_writes AS DECIMAL(10,2))
         ELSE 0 END                     AS avg_write_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) fs
JOIN sys.master_files mf
    ON  mf.database_id = fs.database_id
    AND mf.file_id     = fs.file_id
WHERE (fs.num_of_reads  > 0 AND (fs.io_stall_read_ms  / fs.num_of_reads)  > 20)  -- > 20 ms read
   OR (fs.num_of_writes > 0 AND (fs.io_stall_write_ms / fs.num_of_writes) > 20)  -- > 20 ms write
ORDER BY (fs.io_stall_read_ms + fs.io_stall_write_ms) DESC;
GO
