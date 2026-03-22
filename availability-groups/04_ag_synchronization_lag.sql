-- ============================================================
-- Script: AG Synchronization Lag & Estimated Recovery Time
-- Description: Reports redo-queue size, log-send queue, and
--              estimated time to synchronize each replica.
-- Applies to: SQL Server 2012 and later
-- ============================================================

SELECT
    ag.name                                         AS ag_name,
    ar.replica_server_name                          AS replica_server,
    adb.database_name                               AS database_name,
    ars.role_desc                                   AS replica_role,
    drs.synchronization_state_desc                  AS sync_state,
    drs.log_send_queue_size                         AS log_send_queue_kb,
    drs.log_send_rate                               AS log_send_rate_kb_s,
    drs.redo_queue_size                             AS redo_queue_kb,
    drs.redo_rate                                   AS redo_rate_kb_s,
    -- Estimated seconds to drain the redo queue
    CASE
        WHEN drs.redo_rate > 0
        THEN drs.redo_queue_size / drs.redo_rate
        ELSE NULL
    END                                             AS estimated_redo_seconds,
    -- Estimated seconds to drain the log-send queue
    CASE
        WHEN drs.log_send_rate > 0
        THEN drs.log_send_queue_size / drs.log_send_rate
        ELSE NULL
    END                                             AS estimated_send_seconds,
    drs.last_received_time                          AS last_received,
    drs.last_hardened_time                          AS last_hardened,
    drs.last_redone_time                            AS last_redone,
    drs.last_commit_time                            AS last_commit
FROM sys.availability_groups                        ag
JOIN sys.availability_replicas                      ar   ON ar.group_id         = ag.group_id
JOIN sys.dm_hadr_availability_replica_states        ars  ON ars.replica_id      = ar.replica_id
JOIN sys.availability_databases_cluster             adb  ON adb.group_id        = ag.group_id
JOIN sys.dm_hadr_database_replica_states            drs  ON drs.replica_id      = ar.replica_id
                                                       AND drs.group_database_id = adb.group_database_id
WHERE ars.role_desc = N'SECONDARY'
ORDER BY
    drs.redo_queue_size DESC,
    ag.name,
    ar.replica_server_name;
GO
