-- ============================================================
-- Script: AG Endpoint & Mirroring Status
-- Description: Checks the health of database-mirroring / AG
--              endpoints on the local instance.
-- Applies to: SQL Server 2012 and later
-- ============================================================

-- Endpoint configuration
SELECT
    e.name              AS endpoint_name,
    e.state_desc        AS endpoint_state,
    e.type_desc         AS endpoint_type,
    tcp.port            AS tcp_port,
    e.is_admin_endpoint,
    sp.name             AS service_principal
FROM sys.endpoints          e
JOIN sys.tcp_endpoints      tcp ON tcp.endpoint_id = e.endpoint_id
LEFT JOIN sys.server_principals sp  ON sp.principal_id = e.principal_id
WHERE e.type_desc = N'DATABASE_MIRRORING'
ORDER BY e.name;
GO

-- Endpoint connection stats (messages sent / received)
SELECT
    e.name              AS endpoint_name,
    c.connection_id,
    c.connect_time,
    c.num_reads,
    c.num_writes,
    c.last_read,
    c.last_write,
    c.net_transport,
    c.client_net_address
FROM sys.endpoints              e
JOIN sys.dm_exec_connections    c ON c.endpoint_id = e.endpoint_id
WHERE e.type_desc = N'DATABASE_MIRRORING'
ORDER BY e.name;
GO
