-- ============================================================
-- Script: Top CPU-Consuming Queries
-- Description: Returns the top queries by total CPU time from
--              the plan cache, along with execution counts and
--              the first 200 characters of the query text.
-- Applies to: SQL Server 2008 and later
-- ============================================================

SELECT TOP 25
    qs.total_worker_time / 1000                         AS total_cpu_ms,
    qs.execution_count,
    qs.total_worker_time / 1000 / qs.execution_count    AS avg_cpu_ms,
    qs.total_elapsed_time / 1000                        AS total_elapsed_ms,
    qs.total_elapsed_time / 1000 / qs.execution_count   AS avg_elapsed_ms,
    qs.total_logical_reads,
    qs.total_logical_reads / qs.execution_count         AS avg_logical_reads,
    qs.total_physical_reads,
    qs.creation_time                                    AS plan_created,
    qs.last_execution_time,
    SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
          END - qs.statement_start_offset) / 2) + 1)   AS query_text,
    DB_NAME(st.dbid)                                    AS database_name,
    OBJECT_NAME(st.objectid, st.dbid)                   AS object_name,
    qp.query_plan
FROM sys.dm_exec_query_stats          qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle)     st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle)  qp
ORDER BY qs.total_worker_time DESC;
GO

-- ============================================================
-- Top queries by average CPU (identifies single-run offenders)
-- ============================================================
SELECT TOP 25
    qs.total_worker_time / 1000 / qs.execution_count    AS avg_cpu_ms,
    qs.total_worker_time / 1000                         AS total_cpu_ms,
    qs.execution_count,
    qs.last_execution_time,
    SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
          END - qs.statement_start_offset) / 2) + 1)   AS query_text,
    DB_NAME(st.dbid)                                    AS database_name
FROM sys.dm_exec_query_stats          qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE qs.execution_count > 0
ORDER BY avg_cpu_ms DESC;
GO
