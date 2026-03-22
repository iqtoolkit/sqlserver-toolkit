-- ============================================================
-- Script: SQL Agent Schedule Report
-- Description: Lists all job schedules with their next run
--              time and frequency details, so you can verify
--              maintenance windows and avoid overlapping jobs.
-- Applies to: SQL Server 2008 and later
-- ============================================================

SELECT
    j.name                                          AS job_name,
    j.enabled                                       AS job_enabled,
    sch.name                                        AS schedule_name,
    sch.enabled                                     AS schedule_enabled,
    CASE sch.freq_type
        WHEN 1   THEN 'Once'
        WHEN 4   THEN 'Daily'
        WHEN 8   THEN 'Weekly'
        WHEN 16  THEN 'Monthly'
        WHEN 32  THEN 'Monthly (relative)'
        WHEN 64  THEN 'Agent starts'
        WHEN 128 THEN 'Idle CPU'
        ELSE 'Unknown'
    END                                             AS frequency_type,
    sch.freq_interval,
    CASE sch.freq_subday_type
        WHEN 1 THEN 'Once at ' + STUFF(STUFF(RIGHT('000000' + CAST(sch.active_start_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':')
        WHEN 2 THEN 'Every ' + CAST(sch.freq_subday_interval AS VARCHAR) + ' second(s)'
        WHEN 4 THEN 'Every ' + CAST(sch.freq_subday_interval AS VARCHAR) + ' minute(s)'
        WHEN 8 THEN 'Every ' + CAST(sch.freq_subday_interval AS VARCHAR) + ' hour(s)'
        ELSE ''
    END                                             AS run_frequency,
    STUFF(STUFF(RIGHT('000000' + CAST(sch.active_start_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':') AS start_time,
    STUFF(STUFF(RIGHT('000000' + CAST(sch.active_end_time   AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':') AS end_time,
    CASE ja.next_run_date
        WHEN 0 THEN NULL
        ELSE msdb.dbo.agent_datetime(ja.next_run_date, ja.next_run_time)
    END                                             AS next_run_datetime,
    msdb.dbo.agent_datetime(ja.last_run_date, ja.last_run_time) AS last_run_datetime
FROM msdb.dbo.sysjobs                j
JOIN msdb.dbo.sysjobschedules        jsch ON jsch.job_id     = j.job_id
JOIN msdb.dbo.sysschedules           sch  ON sch.schedule_id = jsch.schedule_id
LEFT JOIN msdb.dbo.sysjobservers     ja   ON ja.job_id       = j.job_id
WHERE j.enabled  = 1
  AND sch.enabled = 1
ORDER BY j.name, sch.name;
GO
