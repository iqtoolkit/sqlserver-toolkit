-- ============================================================
-- Script: DBCC CHECKDB – Database Integrity Checks
-- Description: Runs DBCC CHECKDB for all online user databases,
--              or a single database when @DatabaseName is set.
--              Results are captured in a temp table and printed.
-- Applies to: SQL Server 2008 and later
-- NOTE:        Run during a low-traffic window; CHECKDB can be
--              I/O intensive.  For very large databases consider
--              running PHYSICAL_ONLY first.
-- ============================================================

DECLARE @DatabaseName SYSNAME = NULL; -- NULL = all user databases
DECLARE @PhysicalOnly BIT      = 0;   -- 1 = PHYSICAL_ONLY (faster, less thorough)

DECLARE @sql          NVARCHAR(MAX);
DECLARE @dbName       SYSNAME;
DECLARE @options      NVARCHAR(100) = CASE WHEN @PhysicalOnly = 1 THEN N', PHYSICAL_ONLY' ELSE N'' END;

-- Result capture table
IF OBJECT_ID('tempdb..#CheckDBResults') IS NOT NULL
    DROP TABLE #CheckDBResults;

CREATE TABLE #CheckDBResults
(
    Error       INT,
    Level       INT,
    State       INT,
    MessageText NVARCHAR(MAX),
    RepairLevel NVARCHAR(100),
    Status      INT,
    DbId        INT,
    DbFragId    INT,
    ObjectId    INT,
    IndexId     INT,
    PartitionId BIGINT,
    AllocUnitId BIGINT,
    RidDbId     INT,
    RidPruId    INT,
    File        INT,
    Page        INT,
    Slot        INT,
    RefDbId     INT,
    RefPruId    INT,
    RefFile     INT,
    RefPage     INT,
    RefSlot     INT,
    Allocation  INT
);

DECLARE db_cur CURSOR FAST_FORWARD FOR
    SELECT name
    FROM   sys.databases
    WHERE  state_desc = N'ONLINE'
      AND  database_id > 4
      AND  (@DatabaseName IS NULL OR name = @DatabaseName)
    ORDER BY name;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @dbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT N'============================';
    PRINT N'Checking: ' + @dbName;
    PRINT N'============================';

    SET @sql = N'DBCC CHECKDB (' + QUOTENAME(@dbName) + N') WITH NO_INFOMSGS, ALL_ERRORMSGS'
             + @options + N';';

    BEGIN TRY
        EXEC sp_executesql @sql;
        PRINT N'CHECKDB completed without errors for: ' + @dbName;
    END TRY
    BEGIN CATCH
        PRINT N'ERROR running CHECKDB on ' + @dbName + N': ' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM db_cur INTO @dbName;
END;

CLOSE db_cur;
DEALLOCATE db_cur;

-- Show last recorded CHECKDB time for each database
SELECT
    d.name                                  AS database_name,
    DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime') AS last_good_checkdb
FROM sys.databases d
WHERE d.database_id > 4
ORDER BY d.name;
GO
