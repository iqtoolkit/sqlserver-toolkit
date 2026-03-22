-- ============================================================
-- Script: Server Configuration & sp_configure Review
-- Description: Lists all SQL Server configuration settings,
--              highlights non-default values, and provides
--              recommended best-practice settings as comments.
-- Applies to: SQL Server 2008 and later
-- ============================================================

-- -------------------------------------------------------
-- 1. All configuration values (current vs. running)
-- -------------------------------------------------------
SELECT
    name,
    description,
    minimum,
    maximum,
    value           AS configured_value,
    value_in_use    AS running_value,
    is_advanced,
    is_dynamic,
    CASE WHEN value <> value_in_use THEN 'Restart required' ELSE '' END AS restart_needed
FROM sys.configurations
ORDER BY name;
GO

-- -------------------------------------------------------
-- 2. Non-default configuration values
-- -------------------------------------------------------
SELECT
    name,
    value           AS configured_value,
    value_in_use    AS running_value
FROM sys.configurations
WHERE value <> value_in_use
   OR value <> 0   -- 0 is not always the default; adjust as needed
ORDER BY name;
GO

-- -------------------------------------------------------
-- 3. Commonly tuned settings — apply carefully
-- -------------------------------------------------------

-- Enable 'show advanced options' (required before changing advanced settings)
-- EXEC sp_configure 'show advanced options', 1;
-- RECONFIGURE;
-- GO

-- Maximum server memory (replace with 80-90% of physical RAM in MB)
-- EXEC sp_configure 'max server memory (MB)', <TargetMB>;
-- RECONFIGURE;
-- GO

-- Max degree of parallelism (MAXDOP)
-- EXEC sp_configure 'max degree of parallelism', <MAXDOP>;
-- RECONFIGURE;
-- GO

-- Cost threshold for parallelism (default 5 is usually too low; try 50)
-- EXEC sp_configure 'cost threshold for parallelism', 50;
-- RECONFIGURE;
-- GO

-- Optimize for ad hoc workloads (reduces single-use plan bloat)
-- EXEC sp_configure 'optimize for ad hoc workloads', 1;
-- RECONFIGURE;
-- GO

-- -------------------------------------------------------
-- 4. Hardware & instance overview
-- -------------------------------------------------------
SELECT
    cpu_count                               AS logical_cpus,
    hyperthread_ratio,
    cpu_count / hyperthread_ratio           AS physical_cores,
    physical_memory_kb / 1024              AS total_ram_mb,
    virtual_machine_type_desc              AS vm_type,
    softnuma_configuration_desc,
    sql_memory_model_desc,
    committed_kb / 1024                    AS committed_mb,
    committed_target_kb / 1024             AS committed_target_mb
FROM sys.dm_os_sys_info;
GO

SELECT
    @@SERVERNAME                            AS server_name,
    @@VERSION                               AS sql_version,
    SERVERPROPERTY('Edition')               AS edition,
    SERVERPROPERTY('ProductVersion')        AS product_version,
    SERVERPROPERTY('ProductLevel')          AS product_level,
    SERVERPROPERTY('ProductUpdateLevel')    AS update_level,
    SERVERPROPERTY('Collation')             AS server_collation,
    SERVERPROPERTY('IsClustered')           AS is_clustered,
    SERVERPROPERTY('IsHadrEnabled')         AS is_hadr_enabled,
    SERVERPROPERTY('HadrManagerStatus')     AS hadr_manager_status;
GO
