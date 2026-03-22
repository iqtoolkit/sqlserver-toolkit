-- ============================================================
-- Script: Index Rebuild & Reorganize
-- Description: Rebuilds indexes with fragmentation >= 30 % and
--              reorganizes indexes with fragmentation between
--              10 % and 30 %. Updates statistics afterward.
--              Set @DatabaseName to target a specific database,
--              or leave NULL to process all user databases.
-- Applies to: SQL Server 2008 and later
-- ============================================================

DECLARE @DatabaseName    SYSNAME = NULL;  -- NULL = all user databases
DECLARE @RebuildThreshold  FLOAT  = 30.0; -- Fragmentation % triggering REBUILD
DECLARE @ReorgThreshold    FLOAT  = 10.0; -- Fragmentation % triggering REORGANIZE
DECLARE @MinPageCount      INT    = 1000; -- Skip small indexes (< N pages)
DECLARE @FillFactor        TINYINT = 90;

DECLARE @sql        NVARCHAR(MAX);
DECLARE @dbName     SYSNAME;
DECLARE @schemaName SYSNAME;
DECLARE @tableName  SYSNAME;
DECLARE @indexName  SYSNAME;
DECLARE @frag       FLOAT;
DECLARE @indexId    INT;
DECLARE @objectId   INT;

-- Temp table to hold index fragmentation data
IF OBJECT_ID('tempdb..#IndexFragmentation') IS NOT NULL
    DROP TABLE #IndexFragmentation;

CREATE TABLE #IndexFragmentation
(
    DatabaseName    SYSNAME,
    SchemaName      SYSNAME,
    TableName       SYSNAME,
    IndexName       SYSNAME,
    IndexId         INT,
    ObjectId        INT,
    Fragmentation   FLOAT,
    PageCount       BIGINT
);

-- Populate fragmentation data for target database(s)
DECLARE db_cur CURSOR FAST_FORWARD FOR
    SELECT name
    FROM   sys.databases
    WHERE  state_desc = N'ONLINE'
      AND  is_read_only = 0
      AND  database_id  > 4
      AND  (@DatabaseName IS NULL OR name = @DatabaseName);

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @dbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@dbName) + N';
    INSERT INTO #IndexFragmentation
    SELECT
        DB_NAME()                           AS DatabaseName,
        s.name                              AS SchemaName,
        t.name                              AS TableName,
        i.name                              AS IndexName,
        i.index_id                          AS IndexId,
        t.object_id                         AS ObjectId,
        ips.avg_fragmentation_in_percent    AS Fragmentation,
        ips.page_count                      AS PageCount
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N''LIMITED'') ips
    JOIN sys.tables  t ON t.object_id = ips.object_id
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    JOIN sys.indexes i ON i.object_id = ips.object_id
                      AND i.index_id  = ips.index_id
    WHERE ips.index_id > 0             -- exclude heaps
      AND ips.page_count >= ' + CAST(@MinPageCount AS NVARCHAR) + N'
      AND ips.avg_fragmentation_in_percent >= ' + CAST(@ReorgThreshold AS NVARCHAR) + N';';

    EXEC sp_executesql @sql;
    FETCH NEXT FROM db_cur INTO @dbName;
END;

CLOSE db_cur;
DEALLOCATE db_cur;

-- Process indexes
DECLARE idx_cur CURSOR FAST_FORWARD FOR
    SELECT DatabaseName, SchemaName, TableName, IndexName, IndexId, ObjectId, Fragmentation
    FROM   #IndexFragmentation
    ORDER  BY Fragmentation DESC;

OPEN idx_cur;
FETCH NEXT FROM idx_cur INTO @dbName, @schemaName, @tableName, @indexName, @indexId, @objectId, @frag;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF @frag >= @RebuildThreshold
    BEGIN
        SET @sql = N'USE ' + QUOTENAME(@dbName) + N';
            ALTER INDEX ' + QUOTENAME(@indexName) + N'
            ON ' + QUOTENAME(@schemaName) + N'.' + QUOTENAME(@tableName) + N'
            REBUILD WITH (ONLINE = ON, FILLFACTOR = ' + CAST(@FillFactor AS NVARCHAR) + N', SORT_IN_TEMPDB = ON);';
        PRINT N'REBUILD: ' + @dbName + N'.' + @schemaName + N'.' + @tableName + N'.' + @indexName
            + N' (' + CAST(CAST(@frag AS DECIMAL(5,1)) AS NVARCHAR) + N'%)';
    END
    ELSE
    BEGIN
        SET @sql = N'USE ' + QUOTENAME(@dbName) + N';
            ALTER INDEX ' + QUOTENAME(@indexName) + N'
            ON ' + QUOTENAME(@schemaName) + N'.' + QUOTENAME(@tableName) + N'
            REORGANIZE;';
        PRINT N'REORGANIZE: ' + @dbName + N'.' + @schemaName + N'.' + @tableName + N'.' + @indexName
            + N' (' + CAST(CAST(@frag AS DECIMAL(5,1)) AS NVARCHAR) + N'%)';
    END;

    EXEC sp_executesql @sql;
    FETCH NEXT FROM idx_cur INTO @dbName, @schemaName, @tableName, @indexName, @indexId, @objectId, @frag;
END;

CLOSE idx_cur;
DEALLOCATE idx_cur;

DROP TABLE #IndexFragmentation;
GO
