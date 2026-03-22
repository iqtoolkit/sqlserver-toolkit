-- ============================================================
-- Script: Differential Backup
-- Description: Performs a compressed differential backup for
--              every online, read-write user database (or a
--              single database when @DatabaseName is supplied).
-- Applies to: SQL Server 2008 R2 and later
-- ============================================================

DECLARE @BackupPath   NVARCHAR(260) = N'D:\SQLBackups\Diff\'; -- Change as needed
DECLARE @DatabaseName SYSNAME       = NULL;                   -- NULL = all user databases

DECLARE @sql        NVARCHAR(MAX);
DECLARE @dbName     SYSNAME;
DECLARE @backupFile NVARCHAR(500);
DECLARE @timestamp  NVARCHAR(20) = CONVERT(NVARCHAR(20), GETDATE(), 112)
                                 + '_'
                                 + REPLACE(CONVERT(NVARCHAR(8), GETDATE(), 108), ':', '');

DECLARE db_cursor CURSOR FAST_FORWARD FOR
    SELECT name
    FROM   sys.databases
    WHERE  state_desc  = N'ONLINE'
      AND  is_read_only = 0
      AND  database_id  > 4
      AND  (@DatabaseName IS NULL OR name = @DatabaseName)
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @dbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @backupFile = @BackupPath + @dbName + N'_DIFF_' + @timestamp + N'.bak';

    SET @sql = N'BACKUP DATABASE ' + QUOTENAME(@dbName) + N'
        TO DISK = N''' + @backupFile + N'''
        WITH
            DIFFERENTIAL,
            COMPRESSION,
            CHECKSUM,
            STATS       = 10,
            NAME        = N''' + @dbName + N' Differential Backup'',
            DESCRIPTION = N''Differential backup taken by 03_differential_backup.sql'';';

    PRINT N'Diff backup: ' + @dbName;
    EXEC sp_executesql @sql;

    FETCH NEXT FROM db_cursor INTO @dbName;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;
GO
