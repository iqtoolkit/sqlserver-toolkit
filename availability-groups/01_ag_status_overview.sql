-- ============================================================
-- Script: AG Status Overview
-- Description: Provides a comprehensive overview of all
--              Availability Groups, replicas, and databases.
-- Applies to: SQL Server 2012 and later
-- ============================================================

SELECT
    ag.name                                 AS ag_name,
    ar.replica_server_name                  AS replica_server,
    ar.availability_mode_desc               AS availability_mode,
    ar.failover_mode_desc                   AS failover_mode,
    ars.role_desc                           AS current_role,
    ars.operational_state_desc              AS operational_state,
    ars.connected_state_desc                AS connected_state,
    ars.synchronization_health_desc         AS sync_health,
    ars.last_connect_error_description      AS last_connect_error,
    agl.dns_name                            AS listener_dns,
    agl.port                                AS listener_port
FROM sys.availability_groups                ag
JOIN sys.availability_replicas              ar  ON ar.group_id  = ag.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ars.replica_id = ar.replica_id
LEFT JOIN sys.availability_group_listeners  agl ON agl.group_id = ag.group_id
ORDER BY
    ag.name,
    ars.role_desc,
    ar.replica_server_name;
GO

-- ============================================================
-- Per-database synchronization state
-- ============================================================
SELECT
    ag.name                             AS ag_name,
    ar.replica_server_name              AS replica_server,
    adb.database_name                   AS database_name,
    drs.synchronization_state_desc      AS sync_state,
    drs.synchronization_health_desc     AS sync_health,
    drs.is_suspended                    AS is_suspended,
    drs.suspend_reason_desc             AS suspend_reason,
    drs.log_send_queue_size             AS log_send_queue_kb,
    drs.log_send_rate                   AS log_send_rate_kb_s,
    drs.redo_queue_size                 AS redo_queue_kb,
    drs.redo_rate                       AS redo_rate_kb_s,
    drs.last_received_time              AS last_received,
    drs.last_hardened_time              AS last_hardened,
    drs.last_redone_time                AS last_redone
FROM sys.availability_groups                ag
JOIN sys.availability_replicas              ar  ON ar.group_id   = ag.group_id
JOIN sys.availability_databases_cluster     adb ON adb.group_id  = ag.group_id
JOIN sys.dm_hadr_database_replica_states    drs ON drs.replica_id = ar.replica_id
                                               AND drs.group_database_id = adb.group_database_id
ORDER BY
    ag.name,
    ar.replica_server_name,
    adb.database_name;
GO
