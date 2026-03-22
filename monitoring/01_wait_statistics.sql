-- ============================================================
-- Script: Top Wait Statistics
-- Description: Reports cumulative wait statistics since the
--              last SQL Server restart, excluding benign waits.
--              Use to identify the primary bottleneck category.
-- Applies to: SQL Server 2008 and later
-- ============================================================

-- Waits to exclude (benign / background)
IF OBJECT_ID('tempdb..#ExcludeWaits') IS NOT NULL
    DROP TABLE #ExcludeWaits;

CREATE TABLE #ExcludeWaits (wait_type NVARCHAR(120) PRIMARY KEY);
INSERT INTO #ExcludeWaits VALUES
    (N'SLEEP_TASK'),          (N'SLEEP_SYSTEMTASK'),
    (N'SLEEP_DBSTARTUP'),     (N'SLEEP_DCOMSTARTUP'),
    (N'SLEEP_MASTERDBREADY'), (N'SLEEP_MASTERMDREADY'),
    (N'SLEEP_MASTERUPGRADED'),(N'SLEEP_MSDBSTARTUP'),
    (N'SLEEP_TEMPDBSTARTUP'), (N'SLEEP_WORKER_START'),
    (N'SLEEP_LAZYWRITER'),    (N'SLEEP_MEMORYPOOL_SHRINK'),
    (N'WAITFOR'),             (N'DISPATCHER_QUEUE_SEMAPHORE'),
    (N'CLR_AUTO_EVENT'),      (N'CLR_MANUAL_EVENT'),
    (N'DBMIRROR_EVENTS_QUEUE'),(N'SQLTRACE_BUFFER_FLUSH'),
    (N'XE_TIMER_EVENT'),      (N'XE_DISPATCHER_WAIT'),
    (N'FT_IFTS_SCHEDULER_IDLE_WAIT'),
    (N'BROKER_TO_FLUSH'),     (N'BROKER_TASK_STOP'),
    (N'BROKER_EVENTHANDLER'), (N'CHECKPOINT_QUEUE'),
    (N'DBMIRROR_WORKER_QUEUE'),(N'REQUEST_FOR_DEADLOCK_SEARCH'),
    (N'RESOURCE_QUEUE'),      (N'SERVER_IDLE_CHECK'),
    (N'HADR_WORK_QUEUE'),     (N'HADR_FILESTREAM_IOMGR_IOCOMPLETION'),
    (N'HADR_CLUSAPI_CALL'),   (N'HADR_LOGCAPTURE_WAIT'),
    (N'HADR_NOTIFICATION_DEQUEUE'), (N'HADR_TIMER_TASK'),
    (N'HADR_TRANSPORT_DBRLIST'), (N'HADR_WORK_POOL'),
    (N'SNI_HTTP_ACCEPT'),     (N'SP_SERVER_DIAGNOSTICS_SLEEP'),
    (N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP'),
    (N'ONDEMAND_TASK_MANAGER'),(N'PARALLEL_REDO_DRAIN_WORKER'),
    (N'PARALLEL_REDO_LOG_CACHE'), (N'PARALLEL_REDO_TRAN_LIST'),
    (N'PARALLEL_REDO_WORKER_SYNC'), (N'PARALLEL_REDO_WORKER_WAIT_WORK'),
    (N'DIRTY_PAGE_POLL'),     (N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG'),
    (N'XTP_PREEMPTIVE_TASK'),  (N'REDO_THREAD_PENDING_WORK');

;WITH
    waits AS
    (
        SELECT
            wait_type,
            wait_time_ms / 1000.0                               AS wait_time_s,
            (wait_time_ms - signal_wait_time_ms) / 1000.0       AS resource_wait_s,
            signal_wait_time_ms / 1000.0                        AS signal_wait_s,
            waiting_tasks_count
        FROM sys.dm_os_wait_stats
        WHERE wait_type NOT IN (SELECT wait_type FROM #ExcludeWaits)
          AND wait_time_ms > 0
    ),
    total AS
    (
        SELECT SUM(wait_time_s) AS total_wait_s FROM waits
    )
SELECT TOP 25
    w.wait_type,
    CAST(w.wait_time_s    AS DECIMAL(18,2))                     AS total_wait_s,
    CAST(w.resource_wait_s AS DECIMAL(18,2))                    AS resource_wait_s,
    CAST(w.signal_wait_s  AS DECIMAL(18,2))                     AS signal_wait_s,
    w.waiting_tasks_count,
    CAST(w.wait_time_s / NULLIF(w.waiting_tasks_count, 0) * 1000
        AS DECIMAL(18,2))                                       AS avg_wait_ms,
    CAST(100.0 * w.wait_time_s / NULLIF(t.total_wait_s, 0)
        AS DECIMAL(5,2))                                        AS pct_of_total
FROM waits w
CROSS JOIN total t
ORDER BY w.wait_time_s DESC;

DROP TABLE #ExcludeWaits;
GO
