-- ============================================================
-- Script: Login & User Audit
-- Description: Lists all server-level logins and their
--              corresponding database users, roles, and
--              permissions.
-- Applies to: SQL Server 2008 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. All server-level logins
-- -------------------------------------------------------
SELECT
    sp.name                             AS login_name,
    sp.type_desc                        AS login_type,
    sp.is_disabled,
    sp.create_date,
    sp.modify_date,
    sp.default_database_name,
    sp.is_policy_checked,
    sp.is_expiration_checked,
    ISNULL(spe.permission_name, N'(none)') AS server_permission,
    ISNULL(spe.state_desc, N'')         AS permission_state
FROM sys.server_principals          sp
LEFT JOIN sys.server_permissions    spe ON spe.grantee_principal_id = sp.principal_id
WHERE sp.type IN ('S', 'U', 'G')    -- SQL login, Windows user, Windows group
ORDER BY sp.name, spe.permission_name;
GO

-- -------------------------------------------------------
-- 2. Server role members
-- -------------------------------------------------------
SELECT
    r.name                              AS server_role,
    m.name                              AS member_login,
    m.type_desc                         AS member_type
FROM sys.server_principals              r
JOIN sys.server_role_members            srm ON srm.role_principal_id  = r.principal_id
JOIN sys.server_principals              m   ON m.principal_id          = srm.member_principal_id
WHERE r.type = 'R'
ORDER BY r.name, m.name;
GO

-- -------------------------------------------------------
-- 3. Database users and their roles (current database)
-- -------------------------------------------------------
SELECT
    dp.name                             AS database_user,
    dp.type_desc                        AS user_type,
    sp.name                             AS mapped_login,
    dr.name                             AS database_role
FROM sys.database_principals            dp
LEFT JOIN sys.server_principals         sp  ON sp.sid = dp.sid
LEFT JOIN sys.database_role_members     drm ON drm.member_principal_id = dp.principal_id
LEFT JOIN sys.database_principals       dr  ON dr.principal_id         = drm.role_principal_id
WHERE dp.type IN ('S', 'U', 'G')
ORDER BY dp.name, dr.name;
GO

-- -------------------------------------------------------
-- 4. Object-level permissions (current database)
-- -------------------------------------------------------
SELECT
    dp.name                             AS grantee,
    p.permission_name,
    p.state_desc                        AS state,
    OBJECT_NAME(p.major_id)             AS object_name,
    OBJECTPROPERTY(p.major_id, 'SchemaId') AS schema_id
FROM sys.database_permissions           p
JOIN sys.database_principals            dp ON dp.principal_id = p.grantee_principal_id
WHERE p.class = 1   -- object-level
ORDER BY dp.name, OBJECT_NAME(p.major_id), p.permission_name;
GO
