-- ============================================================
-- Script: Orphaned Users & Login Fix
-- Description: Identifies database users not mapped to a
--              server login (orphaned users), and provides
--              the fix commands to remap them.
-- Applies to: SQL Server 2005 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. Identify orphaned users in the current database
-- -------------------------------------------------------
EXEC sp_change_users_login 'Report';
GO

-- -------------------------------------------------------
-- 2. Find orphaned users manually (multi-database version)
-- -------------------------------------------------------
SELECT
    dp.name         AS database_user,
    dp.type_desc    AS user_type,
    dp.sid,
    dp.create_date,
    dp.modify_date
FROM sys.database_principals dp
WHERE dp.type   IN ('S', 'U', 'G')
  AND dp.sid    IS NOT NULL
  AND dp.sid    NOT IN (SELECT sid FROM sys.server_principals)
  AND dp.name   NOT IN (N'guest', N'INFORMATION_SCHEMA', N'sys',
                        N'MS_DataCollectorInternalUser');
GO

-- -------------------------------------------------------
-- 3. Auto-fix orphaned SQL login users
--    (maps them to a login with the same name if one exists)
-- -------------------------------------------------------
-- EXEC sp_change_users_login 'Auto_Fix', '<DatabaseUserName>';
-- GO

-- -------------------------------------------------------
-- 4. Manually remap an orphaned user to an existing login
-- -------------------------------------------------------
-- ALTER USER [<DatabaseUserName>] WITH LOGIN = [<LoginName>];
-- GO

-- -------------------------------------------------------
-- 5. Drop an orphaned user that is no longer needed
-- -------------------------------------------------------
-- DROP USER [<DatabaseUserName>];
-- GO
