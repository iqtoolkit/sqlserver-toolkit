-- ============================================================
-- Script: Add / Remove a Database from an Availability Group
-- Description: Demonstrates the full workflow for adding a new
--              database to an existing AG and for removing one.
-- Applies to: SQL Server 2012 and later
-- ============================================================

-- -------------------------------------------------------
-- SECTION A – Add a database to an AG
-- -------------------------------------------------------
-- Step 1: On the PRIMARY replica — take a full backup
-- -------------------------------------------------------
BACKUP DATABASE [<DatabaseName, sysname, MyDB>]
    TO DISK = N'\\<BackupShare>\<DatabaseName>_full.bak'
    WITH FORMAT, INIT, COMPRESSION, STATS = 10;
GO

-- Step 2: On the PRIMARY replica — take a log backup
BACKUP LOG [<DatabaseName, sysname, MyDB>]
    TO DISK = N'\\<BackupShare>\<DatabaseName>_log.bak'
    WITH NORECOVERY, COMPRESSION, STATS = 10;
GO

-- Step 3: On EACH SECONDARY replica — restore with NORECOVERY
RESTORE DATABASE [<DatabaseName, sysname, MyDB>]
    FROM DISK = N'\\<BackupShare>\<DatabaseName>_full.bak'
    WITH NORECOVERY, STATS = 10;

RESTORE LOG [<DatabaseName, sysname, MyDB>]
    FROM DISK = N'\\<BackupShare>\<DatabaseName>_log.bak'
    WITH NORECOVERY, STATS = 10;
GO

-- Step 4: On EACH SECONDARY replica — join the database to the AG
ALTER DATABASE [<DatabaseName, sysname, MyDB>]
    SET HADR AVAILABILITY GROUP = [<AGName, sysname, MyAG>];
GO

-- Step 5: On the PRIMARY replica — add the database to the AG
ALTER AVAILABILITY GROUP [<AGName, sysname, MyAG>]
    ADD DATABASE [<DatabaseName, sysname, MyDB>];
GO

-- -------------------------------------------------------
-- SECTION B – Remove a database from an AG
-- -------------------------------------------------------
-- Step 1: On the PRIMARY replica — remove from AG
ALTER AVAILABILITY GROUP [<AGName, sysname, MyAG>]
    REMOVE DATABASE [<DatabaseName, sysname, MyDB>];
GO

-- Step 2: On EACH SECONDARY replica — recover the database
-- so it becomes accessible as a standalone database.
-- (Skip this step if you simply want to drop it.)
-- RESTORE DATABASE [<DatabaseName, sysname, MyDB>] WITH RECOVERY;
-- GO
