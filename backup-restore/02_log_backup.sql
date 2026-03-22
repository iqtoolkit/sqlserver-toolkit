-- ============================================================
-- Script: Transaction-Log Backup
-- Description: Backs up the transaction log for every online,
--              read-write database that is in FULL or
--              BULK_LOGGED recovery model.
-- Applies to: SQL Server 2008 R2 and later
-- ============================================================

DECLARE @BackupPath   NVARCHAR(260) = N'D:\SQLBackups\Logs\'; -- Change as needed
DECLARE @DatabaseName SYSNAME       = NULL;                   -- NULL = all eligible databases

DECLARE @sql        NVARCHAR(MAX);
DECLARE @dbName     SYSNAME;
DECLARE @backupFile NVARCHAR(500);
DECLARE @timestamp  NVARCHAR(20)  = CONVERT(NVARCHAR(20), GETDATE(), 112)
                                  + '_'
                                  + REPLACE(CONVERT(NVARCHAR(8), GETDATE(), 108), ':', '');

DECLARE db_cursor CURSOR FAST_FORWARD FOR
    SELECT name
    FROM   sys.databases
    WHERE  state_desc      = N'ONLINE'
      AND  is_read_only    = 0
      AND  recovery_model_desc IN (N'FULL', N'BULK_LOGGED')
      AND  database_id     > 4
      AND  (@DatabaseName IS NULL OR name = @DatabaseName)
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @dbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @backupFile = @BackupPath + @dbName + N'_LOG_' + @timestamp + N'.trn';

    SET @sql = N'BACKUP LOG ' + QUOTENAME(@dbName) + N'
        TO DISK = N''' + @backupFile + N'''
        WITH
            COMPRESSION,
            CHECKSUM,
            STATS       = 10,
            NAME        = N''' + @dbName + N' Log Backup'',
            DESCRIPTION = N''Log backup taken by 02_log_backup.sql'';';

    PRINT N'Backing up log: ' + @dbName;
    EXEC sp_executesql @sql;

    FETCH NEXT FROM db_cursor INTO @dbName;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;
GO
