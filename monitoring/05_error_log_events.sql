-- ============================================================
-- Script: SQL Server Error Log & Recent Events
-- Description: Reads the current and archived SQL Server error
--              logs, filters for errors / warnings, and shows
--              recent SQL Agent job failures.
-- Applies to: SQL Server 2008 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. Read the current error log (last 500 lines, errors only)
-- -------------------------------------------------------
EXEC master.dbo.xp_readerrorlog
    0,      -- 0 = current log
    1,      -- 1 = SQL Server log
    N'error',
    NULL,
    DATEADD(HOUR, -24, GETDATE()),
    GETDATE(),
    N'desc'; -- newest first
GO

-- -------------------------------------------------------
-- 2. Read SQL Server Agent log
-- -------------------------------------------------------
EXEC master.dbo.xp_readerrorlog
    0,      -- 0 = current log
    2,      -- 2 = SQL Server Agent log
    NULL,
    NULL,
    DATEADD(HOUR, -24, GETDATE()),
    GETDATE(),
    N'desc';
GO

-- -------------------------------------------------------
-- 3. SQL Agent job history — last 24 hours, failed only
-- -------------------------------------------------------
SELECT
    j.name                              AS job_name,
    jh.step_id,
    jh.step_name,
    msdb.dbo.agent_datetime(jh.run_date, jh.run_time) AS run_datetime,
    jh.run_duration                     AS hhmmss,
    CASE jh.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
        WHEN 4 THEN 'In Progress'
        ELSE 'Unknown'
    END                                 AS run_status,
    jh.message
FROM msdb.dbo.sysjobhistory    jh
JOIN msdb.dbo.sysjobs           j  ON j.job_id = jh.job_id
WHERE jh.run_status IN (0, 3)        -- 0 = Failed, 3 = Cancelled
  AND msdb.dbo.agent_datetime(jh.run_date, jh.run_time) >= DATEADD(HOUR, -24, GETDATE())
ORDER BY run_datetime DESC;
GO

-- -------------------------------------------------------
-- 4. Cycle (archive) the error log to start fresh
--    (useful after investigating an incident)
-- -------------------------------------------------------
-- EXEC sp_cycle_errorlog;
-- GO
