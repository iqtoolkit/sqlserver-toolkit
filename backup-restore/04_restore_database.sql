-- ============================================================
-- Script: Restore Database
-- Description: Restores a database from a full + optional
--              differential + optional log backup chain.
--              Set the variables at the top before running.
-- Applies to: SQL Server 2008 R2 and later
-- WARNING:     This script will OVERWRITE an existing database.
--              Review every variable carefully before executing.
-- ============================================================

-- -------------------------------------------------------
-- Configuration
-- -------------------------------------------------------
DECLARE @DatabaseName   SYSNAME      = N'<TargetDatabaseName>';
DECLARE @FullBackup     NVARCHAR(500) = N'D:\SQLBackups\MyDB_FULL_20240101.bak';
DECLARE @DiffBackup     NVARCHAR(500) = NULL;  -- Set to path or leave NULL
DECLARE @LogBackup1     NVARCHAR(500) = NULL;  -- First log backup; NULL to skip
DECLARE @LogBackup2     NVARCHAR(500) = NULL;  -- Second log backup; NULL to skip
DECLARE @DataFilePath   NVARCHAR(260) = N'D:\SQLData\';
DECLARE @LogFilePath    NVARCHAR(260) = N'D:\SQLLogs\';
DECLARE @StopAt         DATETIME      = NULL;  -- Point-in-time; NULL = latest

-- -------------------------------------------------------
-- Step 1: Restore FULL backup with NORECOVERY
-- -------------------------------------------------------
DECLARE @sql NVARCHAR(MAX);

SET @sql = N'RESTORE DATABASE ' + QUOTENAME(@DatabaseName) + N'
    FROM DISK = N''' + @FullBackup + N'''
    WITH
        NORECOVERY,
        REPLACE,
        STATS = 10,
        MOVE (SELECT name FROM ...) ...';  -- Adjust MOVE clauses for your file layout

-- Simplified single-file restore (no MOVE); adjust for multi-file databases:
SET @sql = N'RESTORE DATABASE ' + QUOTENAME(@DatabaseName) + N'
    FROM DISK = N''' + @FullBackup + N'''
    WITH NORECOVERY, REPLACE, STATS = 10;';

PRINT N'Restoring FULL backup...';
EXEC sp_executesql @sql;
GO

-- -------------------------------------------------------
-- Step 2 (optional): Apply DIFFERENTIAL backup
-- -------------------------------------------------------
-- RESTORE DATABASE [<TargetDatabaseName>]
--     FROM DISK = N'<DiffBackupPath>'
--     WITH NORECOVERY, STATS = 10;
-- GO

-- -------------------------------------------------------
-- Step 3 (optional): Apply LOG backup(s)
-- -------------------------------------------------------
-- RESTORE LOG [<TargetDatabaseName>]
--     FROM DISK = N'<LogBackupPath>'
--     WITH NORECOVERY, STATS = 10
--     -- , STOPAT = '2024-01-01 23:59:00'  -- point-in-time
-- GO

-- -------------------------------------------------------
-- Step 4: Bring the database ONLINE
-- -------------------------------------------------------
-- RESTORE DATABASE [<TargetDatabaseName>] WITH RECOVERY;
-- GO

-- -------------------------------------------------------
-- Verify restore
-- -------------------------------------------------------
SELECT
    name,
    state_desc,
    recovery_model_desc,
    log_reuse_wait_desc,
    create_date,
    compatibility_level
FROM sys.databases
WHERE name = N'<TargetDatabaseName>';  -- replace with the name used above
GO
