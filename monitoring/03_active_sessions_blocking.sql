-- ============================================================
-- Script: Active Sessions & Blocking
-- Description: Shows all active sessions, their current wait,
--              blocking chain, and the SQL text being executed.
-- Applies to: SQL Server 2008 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. All active requests with blocking info
-- -------------------------------------------------------
SELECT
    r.session_id,
    r.blocking_session_id,
    r.status,
    r.wait_type,
    r.wait_time                             AS wait_time_ms,
    r.total_elapsed_time                    AS elapsed_ms,
    r.cpu_time                              AS cpu_ms,
    r.logical_reads,
    r.reads,
    r.writes,
    r.granted_query_memory / 128            AS granted_memory_mb,
    r.command,
    r.percent_complete,
    DB_NAME(r.database_id)                  AS database_name,
    s.login_name,
    s.host_name,
    s.program_name,
    s.login_time,
    s.last_request_start_time,
    SUBSTRING(t.text,
        (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(t.text)
            ELSE r.statement_end_offset
          END - r.statement_start_offset) / 2) + 1) AS current_statement,
    t.text                                  AS full_batch
FROM sys.dm_exec_requests       r
JOIN sys.dm_exec_sessions        s ON s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id <> @@SPID
ORDER BY r.blocking_session_id DESC, r.session_id;
GO

-- -------------------------------------------------------
-- 2. Blocking chain hierarchy
-- -------------------------------------------------------
;WITH BlockingChain AS
(
    -- Root blocker (not blocked by anyone)
    SELECT
        r.session_id,
        r.blocking_session_id,
        CAST(r.session_id AS NVARCHAR(MAX))  AS chain,
        0                                    AS depth
    FROM sys.dm_exec_requests r
    WHERE r.blocking_session_id = 0
      AND EXISTS (SELECT 1 FROM sys.dm_exec_requests r2 WHERE r2.blocking_session_id = r.session_id)

    UNION ALL

    -- Blocked sessions
    SELECT
        r.session_id,
        r.blocking_session_id,
        bc.chain + N' -> ' + CAST(r.session_id AS NVARCHAR(10)),
        bc.depth + 1
    FROM sys.dm_exec_requests r
    JOIN BlockingChain bc ON bc.session_id = r.blocking_session_id
)
SELECT
    bc.depth,
    bc.chain                            AS blocking_chain,
    bc.session_id,
    bc.blocking_session_id,
    s.login_name,
    s.host_name,
    r.wait_type,
    r.wait_time                         AS wait_ms,
    SUBSTRING(t.text,
        (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(t.text)
            ELSE r.statement_end_offset
          END - r.statement_start_offset) / 2) + 1) AS current_statement
FROM BlockingChain bc
JOIN sys.dm_exec_sessions s ON s.session_id = bc.session_id
LEFT JOIN sys.dm_exec_requests r ON r.session_id = bc.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
ORDER BY bc.depth, bc.session_id;
GO

-- -------------------------------------------------------
-- 3. Kill a specific blocking session (use with caution)
-- -------------------------------------------------------
-- KILL <session_id>;
-- GO
