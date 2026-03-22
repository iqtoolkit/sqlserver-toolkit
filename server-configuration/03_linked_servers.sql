-- ============================================================
-- Script: Linked Server Inventory
-- Description: Lists all linked servers, their provider,
--              connection settings, and tests connectivity.
-- Applies to: SQL Server 2008 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. Linked server configuration
-- -------------------------------------------------------
SELECT
    s.name                              AS linked_server_name,
    s.product,
    s.provider,
    s.data_source,
    s.location,
    s.provider_string,
    s.catalog,
    s.is_remote_login_enabled,
    s.is_rpc_out_enabled,
    s.is_data_access_enabled,
    s.is_collation_compatible,
    s.uses_remote_collation,
    s.modify_date,
    l.remote_name                       AS remote_login_name,
    l.uses_self_credential              AS uses_self_credential
FROM sys.servers            s
LEFT JOIN sys.linked_logins l ON l.server_id = s.server_id
WHERE s.is_linked = 1
ORDER BY s.name;
GO

-- -------------------------------------------------------
-- 2. Test connectivity to a specific linked server
-- -------------------------------------------------------
-- EXEC sp_testlinkedserver N'<LinkedServerName>';
-- GO

-- -------------------------------------------------------
-- 3. Create a new linked server (SQL Server to SQL Server)
-- -------------------------------------------------------
-- EXEC master.dbo.sp_addlinkedserver
--     @server     = N'<LinkedServerName>',
--     @srvproduct = N'SQL Server';
-- GO
-- EXEC master.dbo.sp_addlinkedsrvlogin
--     @rmtsrvname  = N'<LinkedServerName>',
--     @useself     = N'False',
--     @locallogin  = NULL,
--     @rmtuser     = N'<RemoteLogin>',
--     @rmtpassword = N'<Password>';
-- GO

-- -------------------------------------------------------
-- 4. Drop a linked server
-- -------------------------------------------------------
-- EXEC master.dbo.sp_dropserver
--     @server       = N'<LinkedServerName>',
--     @droplogins   = N'droplogins';
-- GO
