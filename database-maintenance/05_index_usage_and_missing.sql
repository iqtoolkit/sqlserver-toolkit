-- ============================================================
-- Script: Identify and Disable Unused Indexes
-- Description: Lists indexes with zero or very low seeks/scans
--              since the last server restart, ordered by the
--              maintenance cost (writes) descending.
--              Review carefully before disabling anything.
-- Applies to: SQL Server 2008 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. Index usage statistics (since last SQL Server restart)
-- -------------------------------------------------------
SELECT
    DB_NAME()                               AS database_name,
    OBJECT_SCHEMA_NAME(i.object_id)         AS schema_name,
    OBJECT_NAME(i.object_id)                AS table_name,
    i.name                                  AS index_name,
    i.type_desc                             AS index_type,
    i.is_unique,
    i.is_primary_key,
    i.is_unique_constraint,
    ISNULL(us.user_seeks,  0)               AS user_seeks,
    ISNULL(us.user_scans,  0)               AS user_scans,
    ISNULL(us.user_lookups, 0)              AS user_lookups,
    ISNULL(us.user_updates, 0)              AS user_updates,   -- maintenance cost
    us.last_user_seek,
    us.last_user_scan,
    us.last_user_lookup,
    us.last_user_update
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats us
    ON  us.object_id   = i.object_id
    AND us.index_id    = i.index_id
    AND us.database_id = DB_ID()
WHERE i.object_id > 100                         -- exclude system objects
  AND i.index_id   > 0                          -- exclude heaps
  AND i.is_primary_key   = 0
  AND i.is_unique_constraint = 0
  AND ISNULL(us.user_seeks, 0) + ISNULL(us.user_scans, 0) + ISNULL(us.user_lookups, 0) = 0
ORDER BY ISNULL(us.user_updates, 0) DESC;
GO

-- -------------------------------------------------------
-- 2. Disable a specific unused index (review output above first)
-- -------------------------------------------------------
-- ALTER INDEX [<IndexName>] ON [<SchemaName>].[<TableName>] DISABLE;
-- GO

-- -------------------------------------------------------
-- 3. Drop a disabled index
-- -------------------------------------------------------
-- DROP INDEX [<IndexName>] ON [<SchemaName>].[<TableName>];
-- GO

-- -------------------------------------------------------
-- 4. Missing index suggestions (from the query optimizer)
-- -------------------------------------------------------
SELECT
    DB_NAME(mid.database_id)                AS database_name,
    mid.statement                           AS table_name,
    migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) AS improvement_measure,
    migs.user_seeks,
    migs.user_scans,
    migs.avg_total_user_cost,
    migs.avg_user_impact,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    N'CREATE INDEX [IX_' + REPLACE(REPLACE(mid.statement, N'[', N''), N']', N'')
        + N'_' + REPLACE(ISNULL(mid.equality_columns, N'') + ISNULL(N'_' + mid.inequality_columns, N''), N', ', N'_')
        + N'] ON ' + mid.statement
        + N' (' + ISNULL(mid.equality_columns, N'')
        + CASE WHEN mid.inequality_columns IS NOT NULL AND mid.equality_columns IS NOT NULL THEN N', ' ELSE N'' END
        + ISNULL(mid.inequality_columns, N'') + N')'
        + ISNULL(N' INCLUDE (' + mid.included_columns + N')', N'') AS create_index_statement
FROM sys.dm_db_missing_index_groups          mig
JOIN sys.dm_db_missing_index_group_stats     migs ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details         mid  ON mid.index_handle  = mig.index_handle
ORDER BY improvement_measure DESC;
GO
