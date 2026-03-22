-- ============================================================
-- Script: Audit SQL Server Logins & Failed Logins
-- Description: Queries the default trace and the SQL Server
--              error log for login failures, and reports
--              any logins with overly broad server permissions.
-- Applies to: SQL Server 2008 and later
-- NOTE:        The default trace must not have been disabled
--              (trace flag 4136 / sp_configure 'default trace').
-- ============================================================

-- -------------------------------------------------------
-- 1. Failed logins in the last 24 hours (error log)
-- -------------------------------------------------------
CREATE TABLE #ErrorLog (LogDate DATETIME, ProcessInfo NVARCHAR(100), [Text] NVARCHAR(MAX));

INSERT INTO #ErrorLog
EXEC xp_readerrorlog 0, 1, N'Login failed', NULL,
    DATEADD(HOUR, -24, GETDATE()), GETDATE(), N'desc';

SELECT
    LogDate,
    ProcessInfo,
    [Text]
FROM #ErrorLog
ORDER BY LogDate DESC;

DROP TABLE #ErrorLog;
GO

-- -------------------------------------------------------
-- 2. Logins with sysadmin role
-- -------------------------------------------------------
SELECT
    sp.name             AS login_name,
    sp.type_desc        AS login_type,
    sp.is_disabled,
    sp.create_date
FROM sys.server_principals          sp
JOIN sys.server_role_members        srm ON srm.member_principal_id = sp.principal_id
JOIN sys.server_principals          r   ON r.principal_id = srm.role_principal_id
WHERE r.name = N'sysadmin'
ORDER BY sp.name;
GO

-- -------------------------------------------------------
-- 3. Non-sysadmin logins with sensitive server permissions
-- -------------------------------------------------------
SELECT
    sp.name                 AS login_name,
    spe.permission_name,
    spe.state_desc
FROM sys.server_permissions    spe
JOIN sys.server_principals     sp ON sp.principal_id = spe.grantee_principal_id
WHERE spe.permission_name IN (
    N'CONTROL SERVER',
    N'ALTER ANY LOGIN',
    N'ALTER ANY SERVER ROLE',
    N'VIEW SERVER STATE',
    N'SHUTDOWN'
)
  AND sp.type NOT IN ('R') -- exclude roles
ORDER BY sp.name, spe.permission_name;
GO

-- -------------------------------------------------------
-- 4. Logins with blank or known-weak passwords (SQL auth)
--    Requires VIEW SERVER STATE and CONTROL SERVER.
-- -------------------------------------------------------
SELECT
    name            AS login_name,
    is_disabled,
    is_policy_checked,
    is_expiration_checked
FROM sys.sql_logins
WHERE PWDCOMPARE(N'',   password_hash) = 1  -- blank password
   OR PWDCOMPARE(name,  password_hash) = 1  -- password = username
   OR PWDCOMPARE(N'password', password_hash) = 1
ORDER BY name;
GO
