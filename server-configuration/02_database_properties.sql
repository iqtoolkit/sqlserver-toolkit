-- ============================================================
-- Script: Database Properties Review
-- Description: Summarizes key properties for all databases:
--              recovery model, compatibility level, collation,
--              owner, last backup, size, and state.
-- Applies to: SQL Server 2008 and later
-- ============================================================

SELECT
    d.name                                  AS database_name,
    d.database_id,
    d.state_desc,
    d.recovery_model_desc,
    d.compatibility_level,
    d.collation_name,
    SUSER_SNAME(d.owner_sid)                AS database_owner,
    d.create_date,
    d.is_read_only,
    d.is_auto_close_on,
    d.is_auto_shrink_on,
    d.is_auto_update_stats_on,
    d.is_auto_create_stats_on,
    d.is_fulltext_enabled,
    d.is_cdc_enabled,
    d.is_encrypted,
    d.page_verify_option_desc,
    d.log_reuse_wait_desc,
    -- Last full backup
    (SELECT MAX(backup_finish_date)
     FROM msdb.dbo.backupset bs
     WHERE bs.database_name = d.name
       AND bs.type = 'D')                   AS last_full_backup,
    -- Last log backup
    (SELECT MAX(backup_finish_date)
     FROM msdb.dbo.backupset bs
     WHERE bs.database_name = d.name
       AND bs.type = 'L')                   AS last_log_backup
FROM sys.databases d
ORDER BY d.name;
GO

-- -------------------------------------------------------
-- Change recovery model (adjust per database needs)
-- -------------------------------------------------------
-- ALTER DATABASE [<DatabaseName>] SET RECOVERY FULL;       -- Log backups required
-- ALTER DATABASE [<DatabaseName>] SET RECOVERY SIMPLE;     -- No log backups
-- ALTER DATABASE [<DatabaseName>] SET RECOVERY BULK_LOGGED;
-- GO

-- -------------------------------------------------------
-- Change compatibility level
-- -------------------------------------------------------
-- ALTER DATABASE [<DatabaseName>]
--     SET COMPATIBILITY_LEVEL = 160;  -- SQL Server 2022
-- GO

-- -------------------------------------------------------
-- Disable auto-shrink (recommended)
-- -------------------------------------------------------
-- ALTER DATABASE [<DatabaseName>] SET AUTO_SHRINK OFF;
-- GO
