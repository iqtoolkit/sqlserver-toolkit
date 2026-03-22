-- ============================================================
-- Script: Create a SQL Agent Job
-- Description: Template for creating a new SQL Agent job
--              with a T-SQL step, a daily schedule, and
--              failure email notification.
--              Replace all <placeholder> values before running.
-- Applies to: SQL Server 2008 and later
-- ============================================================

USE msdb;
GO

-- -------------------------------------------------------
-- 1. Create the job
-- -------------------------------------------------------
DECLARE @jobId UNIQUEIDENTIFIER;

EXEC dbo.sp_add_job
    @job_name           = N'<JobName, sysname, MyMaintenanceJob>',
    @enabled            = 1,
    @description        = N'<Description>',
    @category_name      = N'[Uncategorized (Local)]',
    @owner_login_name   = N'sa',
    @notify_level_eventlog = 2,     -- 2 = On failure
    @notify_level_email    = 2,     -- 2 = On failure
    @notify_email_operator_name = N'<OperatorName>',   -- must exist
    @job_id             = @jobId OUTPUT;

-- -------------------------------------------------------
-- 2. Add a T-SQL job step
-- -------------------------------------------------------
EXEC dbo.sp_add_jobstep
    @job_id             = @jobId,
    @step_name          = N'Step 1 – Execute Maintenance',
    @step_id            = 1,
    @subsystem          = N'TSQL',
    @command            = N'
-- Replace with your T-SQL command
EXEC [dbo].[YourStoredProcedure];
',
    @database_name      = N'<DatabaseName, sysname, master>',
    @on_success_action  = 1,    -- 1 = Quit with success
    @on_fail_action     = 2,    -- 2 = Quit with failure
    @retry_attempts     = 1,
    @retry_interval     = 5;    -- minutes

-- -------------------------------------------------------
-- 3. Set the starting step
-- -------------------------------------------------------
EXEC dbo.sp_update_job
    @job_id         = @jobId,
    @start_step_id  = 1;

-- -------------------------------------------------------
-- 4. Create a daily schedule
-- -------------------------------------------------------
EXEC dbo.sp_add_jobschedule
    @job_id             = @jobId,
    @name               = N'Daily at 02:00',
    @enabled            = 1,
    @freq_type          = 4,        -- 4 = Daily
    @freq_interval      = 1,        -- every 1 day
    @freq_subday_type   = 1,        -- 1 = At the specified time
    @active_start_time  = 020000,   -- 02:00:00
    @active_end_time    = 235959;

-- -------------------------------------------------------
-- 5. Assign the job to the local server
-- -------------------------------------------------------
EXEC dbo.sp_add_jobserver
    @job_id     = @jobId,
    @server_name = N'(local)';

GO

-- -------------------------------------------------------
-- 6. Create an operator for email notifications (if needed)
-- -------------------------------------------------------
-- EXEC dbo.sp_add_operator
--     @name                   = N'<OperatorName>',
--     @enabled                = 1,
--     @email_address          = N'dba-team@example.com',
--     @weekday_pager_start_time   = 090000,
--     @weekday_pager_end_time     = 180000;
-- GO
