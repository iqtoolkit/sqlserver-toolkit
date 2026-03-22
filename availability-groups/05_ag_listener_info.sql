-- ============================================================
-- Script: AG Listener Information
-- Description: Lists all AG listeners with their IP addresses,
--              ports, and current state.
-- Applies to: SQL Server 2012 and later
-- ============================================================

SELECT
    ag.name                         AS ag_name,
    agl.dns_name                    AS listener_dns_name,
    agl.port                        AS listener_port,
    agla.ip_address                 AS ip_address,
    agla.ip_subnet_mask             AS subnet_mask,
    agla.network_subnet_ip          AS network_subnet,
    agla.network_subnet_prefix_length AS prefix_length,
    agla.is_dhcp                    AS is_dhcp,
    agla.state_desc                 AS ip_state
FROM sys.availability_group_listeners       agl
JOIN sys.availability_groups                ag   ON ag.group_id  = agl.group_id
JOIN sys.availability_group_listener_ip_addresses agla ON agla.listener_id = agl.listener_id
ORDER BY
    ag.name,
    agl.dns_name,
    agla.ip_address;
GO
