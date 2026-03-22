-- ============================================================
-- Script: SQL Agent Job Inventory & Status
-- Description: Lists all SQL Agent jobs with their schedules,
--              last execution result, next run time, and
--              duration history.
-- Applies to: SQL Server 2008 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. All jobs with current status and last run result
-- -------------------------------------------------------
SELECT
    j.name                                  AS job_name,
    j.enabled                               AS is_enabled,
    j.description,
    c.name                                  AS category,
    SUSER_SNAME(j.owner_sid)                AS owner,
    j.date_created,
    j.date_modified,
    CASE ja.last_run_outcome
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
        WHEN 5 THEN 'Unknown'
        ELSE 'Never run'
    END                                     AS last_run_result,
    msdb.dbo.agent_datetime(ja.last_run_date, ja.last_run_time) AS last_run_time,
    ja.last_run_duration                    AS last_run_hhmmss,
    CASE ja.next_run_date
        WHEN 0 THEN NULL
        ELSE msdb.dbo.agent_datetime(ja.next_run_date, ja.next_run_time)
    END                                     AS next_scheduled_run,
    CASE jact.run_status
        WHEN 4 THEN 'Running'
        ELSE 'Idle'
    END                                     AS current_status
FROM msdb.dbo.sysjobs             j
LEFT JOIN msdb.dbo.sysjobactivity jact ON jact.job_id       = j.job_id
                                      AND jact.session_id   =
                                          (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
LEFT JOIN msdb.dbo.sysjobservers  ja   ON ja.job_id         = j.job_id
LEFT JOIN msdb.dbo.syscategories  c    ON c.category_id     = j.category_id
ORDER BY j.name;
GO

-- -------------------------------------------------------
-- 2. Jobs that failed in the last 24 hours
-- -------------------------------------------------------
SELECT
    j.name                                  AS job_name,
    jh.step_id,
    jh.step_name,
    msdb.dbo.agent_datetime(jh.run_date, jh.run_time) AS run_datetime,
    jh.run_duration                         AS hhmmss,
    jh.message
FROM msdb.dbo.sysjobhistory     jh
JOIN msdb.dbo.sysjobs            j  ON j.job_id = jh.job_id
WHERE jh.run_status = 0                         -- 0 = Failed
  AND msdb.dbo.agent_datetime(jh.run_date, jh.run_time) >= DATEADD(HOUR, -24, GETDATE())
ORDER BY run_datetime DESC;
GO

-- -------------------------------------------------------
-- 3. Average job duration by job (last 30 days)
-- -------------------------------------------------------
SELECT
    j.name                                  AS job_name,
    COUNT(*)                                AS executions,
    AVG(  (jh.run_duration / 10000) * 3600
        + ((jh.run_duration % 10000) / 100) * 60
        + (jh.run_duration % 100)
    )                                       AS avg_duration_seconds,
    MAX(  (jh.run_duration / 10000) * 3600
        + ((jh.run_duration % 10000) / 100) * 60
        + (jh.run_duration % 100)
    )                                       AS max_duration_seconds
FROM msdb.dbo.sysjobhistory     jh
JOIN msdb.dbo.sysjobs            j  ON j.job_id = jh.job_id
WHERE jh.step_id = 0                            -- job-level record
  AND msdb.dbo.agent_datetime(jh.run_date, jh.run_time) >= DATEADD(DAY, -30, GETDATE())
GROUP BY j.name
ORDER BY avg_duration_seconds DESC;
GO

-- -------------------------------------------------------
-- 4. Enable / disable a job
-- -------------------------------------------------------
-- EXEC msdb.dbo.sp_update_job @job_name = N'<JobName>', @enabled = 1;  -- enable
-- EXEC msdb.dbo.sp_update_job @job_name = N'<JobName>', @enabled = 0;  -- disable
-- GO

-- -------------------------------------------------------
-- 5. Start a job manually
-- -------------------------------------------------------
-- EXEC msdb.dbo.sp_start_job @job_name = N'<JobName>';
-- GO
