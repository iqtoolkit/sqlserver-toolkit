-- ============================================================
-- Script: Memory Usage & Buffer Pool Analysis
-- Description: Reports SQL Server memory configuration,
--              current allocation, buffer pool usage by
--              database, and top memory-consuming queries.
-- Applies to: SQL Server 2008 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. SQL Server memory configuration
-- -------------------------------------------------------
SELECT
    physical_memory_in_use_kb / 1024        AS sql_physical_memory_mb,
    locked_page_allocations_kb / 1024       AS locked_pages_mb,
    virtual_address_space_committed_kb / 1024 AS virt_committed_mb,
    memory_utilization_percentage
FROM sys.dm_os_process_memory;
GO

SELECT
    name,
    value_in_use                            AS configured_value
FROM sys.configurations
WHERE name IN (N'max server memory (MB)', N'min server memory (MB)',
               N'optimize for ad hoc workloads', N'max degree of parallelism',
               N'cost threshold for parallelism')
ORDER BY name;
GO

-- -------------------------------------------------------
-- 2. Memory clerks (top 15 by memory allocated)
-- -------------------------------------------------------
SELECT TOP 15
    type                                    AS clerk_type,
    name                                    AS clerk_name,
    pages_kb / 1024                         AS allocated_mb
FROM sys.dm_os_memory_clerks
ORDER BY pages_kb DESC;
GO

-- -------------------------------------------------------
-- 3. Buffer pool usage by database
-- -------------------------------------------------------
SELECT
    ISNULL(DB_NAME(database_id), N'(other/resourceDB)') AS database_name,
    COUNT(*) * 8 / 1024                     AS buffer_pool_mb,
    SUM(CAST(is_modified AS BIGINT)) * 8 / 1024 AS dirty_pages_mb
FROM sys.dm_os_buffer_descriptors
GROUP BY database_id
ORDER BY COUNT(*) DESC;
GO

-- -------------------------------------------------------
-- 4. Top memory-consuming cached query plans
-- -------------------------------------------------------
SELECT TOP 20
    total_worker_time / 1000               AS total_cpu_ms,
    total_logical_reads,
    execution_count,
    size_in_bytes / 1024                   AS plan_size_kb,
    SUBSTRING(t.text, 1, 200)              AS query_snippet,
    DB_NAME(t.dbid)                        AS database_name
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) t
LEFT JOIN sys.dm_exec_query_stats qs ON qs.plan_handle = cp.plan_handle
WHERE cp.objtype IN (N'Adhoc', N'Prepared', N'Proc')
ORDER BY size_in_bytes DESC;
GO
