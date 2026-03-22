-- ============================================================
-- Script: Update Statistics
-- Description: Updates statistics for all tables in a database
--              using a FULLSCAN. Targets all user databases
--              when @DatabaseName is NULL.
-- Applies to: SQL Server 2008 and later
-- ============================================================

DECLARE @DatabaseName SYSNAME = NULL; -- NULL = all user databases

DECLARE @sql    NVARCHAR(MAX);
DECLARE @dbName SYSNAME;

DECLARE db_cur CURSOR FAST_FORWARD FOR
    SELECT name
    FROM   sys.databases
    WHERE  state_desc = N'ONLINE'
      AND  is_read_only = 0
      AND  database_id  > 4
      AND  (@DatabaseName IS NULL OR name = @DatabaseName)
    ORDER BY name;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @dbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Build a dynamic script that iterates all tables in the database
    SET @sql = N'
    USE ' + QUOTENAME(@dbName) + N';
    DECLARE @tblName SYSNAME;
    DECLARE @sName   SYSNAME;
    DECLARE @stmt    NVARCHAR(MAX);

    DECLARE tbl_cur CURSOR FAST_FORWARD FOR
        SELECT s.name, t.name
        FROM   sys.tables  t
        JOIN   sys.schemas s ON s.schema_id = t.schema_id
        WHERE  t.is_ms_shipped = 0
        ORDER  BY s.name, t.name;

    OPEN tbl_cur;
    FETCH NEXT FROM tbl_cur INTO @sName, @tblName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @stmt = N''UPDATE STATISTICS ''
                  + QUOTENAME(@sName) + N''.'' + QUOTENAME(@tblName)
                  + N'' WITH FULLSCAN;'';
        PRINT @stmt;
        EXEC sp_executesql @stmt;
        FETCH NEXT FROM tbl_cur INTO @sName, @tblName;
    END;

    CLOSE tbl_cur;
    DEALLOCATE tbl_cur;';

    EXEC sp_executesql @sql;
    FETCH NEXT FROM db_cur INTO @dbName;
END;

CLOSE db_cur;
DEALLOCATE db_cur;
GO
