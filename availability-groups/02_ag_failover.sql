-- ============================================================
-- Script: AG Planned & Forced Failover
-- Description: Performs a planned manual failover or, in an
--              emergency, a forced failover with data loss.
-- Applies to: SQL Server 2012 and later
-- IMPORTANT:  Run planned failover on the TARGET (new primary)
--             replica. Run forced failover only as a last resort.
-- ============================================================

-- -------------------------------------------------------
-- 1. Planned manual failover (no data loss)
--    Execute on the SECONDARY replica you want to promote.
-- -------------------------------------------------------
DECLARE @AgName SYSNAME = N'<AGName, sysname, MyAG>';
DECLARE @sql    NVARCHAR(500);

SET @sql = N'ALTER AVAILABILITY GROUP ' + QUOTENAME(@AgName) + N' FAILOVER;';
EXEC sp_executesql @sql;
GO

-- -------------------------------------------------------
-- 2. Forced failover WITH potential data loss
--    Use ONLY when the primary is unavailable and
--    no automatic failover partner is reachable.
--    Execute on the target SECONDARY replica.
-- -------------------------------------------------------
-- DECLARE @AgName SYSNAME = N'<AGName, sysname, MyAG>';
-- DECLARE @sql    NVARCHAR(500);
-- SET @sql = N'ALTER AVAILABILITY GROUP ' + QUOTENAME(@AgName) + N' FORCE_FAILOVER_ALLOW_DATA_LOSS;';
-- EXEC sp_executesql @sql;
-- GO

-- -------------------------------------------------------
-- 3. After a forced failover: resume data movement on
--    all former secondaries that are still accessible.
-- -------------------------------------------------------
-- ALTER DATABASE [<DatabaseName, sysname, MyDB>]
--     SET HADR RESUME;
-- GO
