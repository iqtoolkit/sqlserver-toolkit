-- ============================================================
-- Script: Full Database Backup
-- Description: Performs a full compressed backup for every
--              online, non-system database; or for a specific
--              database when @DatabaseName is supplied.
-- Applies to: SQL Server 2008 R2 and later (Enterprise / Standard)
-- ============================================================

DECLARE @BackupPath    NVARCHAR(260) = N'D:\SQLBackups\';  -- Change to your backup share/path
DECLARE @DatabaseName  SYSNAME      = NULL;                -- NULL = all user databases
DECLARE @RetentionDays INT          = 30;

DECLARE @sql         NVARCHAR(MAX);
DECLARE @dbName      SYSNAME;
DECLARE @backupFile  NVARCHAR(500);
DECLARE @timestamp   NVARCHAR(20)  = CONVERT(NVARCHAR(20), GETDATE(), 112)
                                   + '_'
                                   + REPLACE(CONVERT(NVARCHAR(8), GETDATE(), 108), ':', '');

DECLARE db_cursor CURSOR FAST_FORWARD FOR
    SELECT name
    FROM   sys.databases
    WHERE  state_desc  = N'ONLINE'
      AND  is_read_only = 0
      AND  database_id  > 4                          -- exclude system databases
      AND  (@DatabaseName IS NULL OR name = @DatabaseName)
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @dbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @backupFile = @BackupPath + @dbName + N'_FULL_' + @timestamp + N'.bak';

    SET @sql = N'BACKUP DATABASE ' + QUOTENAME(@dbName) + N'
        TO DISK = N''' + @backupFile + N'''
        WITH
            COMPRESSION,
            CHECKSUM,
            STATS          = 10,
            NAME           = N''' + @dbName + N' Full Backup'',
            DESCRIPTION    = N''Full backup taken by 01_full_backup.sql'';';

    PRINT N'Backing up: ' + @dbName;
    EXEC sp_executesql @sql;

    FETCH NEXT FROM db_cursor INTO @dbName;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;
GO

-- -------------------------------------------------------
-- Clean up backup files older than @RetentionDays (Agent Job)
-- The DELETE FILE step below is illustrative; use xp_delete_file
-- or a maintenance plan / Ola Hallengren script in production.
-- -------------------------------------------------------
-- EXEC master.sys.xp_delete_file
--     0,                          -- 0 = backup files
--     N'D:\SQLBackups\',
--     N'bak',
--     @cutoff_date;               -- supply a datetime cutoff
-- GO
