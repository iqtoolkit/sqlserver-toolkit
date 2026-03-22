-- ============================================================
-- Script: Verify Backup Integrity
-- Description: Runs RESTORE VERIFYONLY against the most recent
--              backup files in msdb.dbo.backupset and also
--              reports backups with failed checksums in the
--              past 7 days.
-- Applies to: SQL Server 2008 R2 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. Latest backup per database (last 7 days)
-- -------------------------------------------------------
SELECT
    bs.database_name,
    bs.type                             AS backup_type,
    CASE bs.type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        ELSE bs.type
    END                                 AS backup_type_desc,
    bs.backup_start_date,
    bs.backup_finish_date,
    DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS duration_seconds,
    CAST(bs.backup_size / 1048576.0     AS DECIMAL(18,2)) AS backup_size_mb,
    CAST(bs.compressed_backup_size / 1048576.0 AS DECIMAL(18,2)) AS compressed_mb,
    bs.is_password_protected,
    bs.has_backup_checksums,
    bs.is_damaged,
    bmf.physical_device_name            AS backup_file
FROM msdb.dbo.backupset            bs
JOIN msdb.dbo.backupmediafamily    bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.backup_start_date >= DATEADD(DAY, -7, GETDATE())
ORDER BY
    bs.database_name,
    bs.backup_start_date DESC;
GO

-- -------------------------------------------------------
-- 2. Identify databases with no recent full backup
--    (no full backup in the last 24 hours)
-- -------------------------------------------------------
SELECT
    d.name                          AS database_name,
    d.recovery_model_desc,
    MAX(bs.backup_finish_date)      AS last_full_backup
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset bs
    ON  bs.database_name = d.name
    AND bs.type          = 'D'
WHERE d.database_id > 4             -- exclude system databases
  AND d.state_desc   = N'ONLINE'
GROUP BY
    d.name,
    d.recovery_model_desc
HAVING MAX(bs.backup_finish_date) < DATEADD(HOUR, -24, GETDATE())
    OR MAX(bs.backup_finish_date) IS NULL
ORDER BY last_full_backup;
GO

-- -------------------------------------------------------
-- 3. Verify the most recent full backup file (VERIFYONLY)
--    Replace the path with an actual backup file.
-- -------------------------------------------------------
-- RESTORE VERIFYONLY
--     FROM DISK = N'D:\SQLBackups\MyDB_FULL_20240101.bak'
--     WITH CHECKSUM;
-- GO
