# SQL Server Toolkit

A curated collection of T-SQL scripts for SQL Server DBAs, organized into logical folders by topic.  
Each script is self-contained, heavily commented, and uses parameterized variables at the top so it is easy to adapt to any environment.

---

## Folder Structure

```
sqlserver-toolkit/
├── availability-groups/       # Always On Availability Group management
├── backup-restore/            # Backup, restore, and backup verification
├── database-maintenance/      # Index maintenance, statistics, CHECKDB
├── jobs/                      # SQL Agent job inventory and creation
├── monitoring/                # Waits, blocking, CPU, memory, I/O
├── security/                  # Logins, users, roles, auditing
├── server-configuration/      # sp_configure, database properties, tempdb
└── storage/                   # Disk space, file growth, VLFs
```

---

## Scripts at a Glance

### `availability-groups/`

| Script | Description |
|--------|-------------|
| `01_ag_status_overview.sql` | Full AG / replica / database status overview |
| `02_ag_failover.sql` | Planned manual failover and forced failover with data loss |
| `03_ag_add_remove_database.sql` | Add or remove a database from an AG |
| `04_ag_synchronization_lag.sql` | Redo/send queue sizes and estimated sync time |
| `05_ag_listener_info.sql` | Listener DNS names, ports, and IP addresses |
| `06_ag_endpoint_status.sql` | Mirroring endpoint configuration and connection stats |

### `backup-restore/`

| Script | Description |
|--------|-------------|
| `01_full_backup.sql` | Compressed full backup for all (or one) user database(s) |
| `02_log_backup.sql` | Transaction-log backup for FULL / BULK_LOGGED databases |
| `03_differential_backup.sql` | Compressed differential backup |
| `04_restore_database.sql` | Restore from full + differential + log chain |
| `05_verify_backup_integrity.sql` | RESTORE VERIFYONLY and missing-backup report |

### `database-maintenance/`

| Script | Description |
|--------|-------------|
| `01_index_rebuild_reorganize.sql` | Rebuild (≥ 30 % frag) or reorganize (≥ 10 % frag) indexes |
| `02_update_statistics.sql` | FULLSCAN statistics update for all tables |
| `03_dbcc_checkdb.sql` | Integrity check across all user databases |
| `04_shrink_database.sql` | File size report and selective shrink (use sparingly) |
| `05_index_usage_and_missing.sql` | Unused index detection and missing index recommendations |

### `jobs/`

| Script | Description |
|--------|-------------|
| `01_job_inventory_and_status.sql` | All jobs, last run result, next run, duration history |
| `02_create_agent_job.sql` | Template: create a job with a T-SQL step and daily schedule |
| `03_job_schedule_report.sql` | All active schedules with next/last run datetimes |

### `monitoring/`

| Script | Description |
|--------|-------------|
| `01_wait_statistics.sql` | Top 25 wait types (benign waits excluded) |
| `02_top_cpu_queries.sql` | Top queries by total and average CPU from plan cache |
| `03_active_sessions_blocking.sql` | Active requests, blocking chain, and KILL template |
| `04_memory_usage.sql` | Memory clerks, buffer pool by database, ad-hoc plan size |
| `05_error_log_events.sql` | Error log reader, Agent log, and failed job history |
| `06_io_latency.sql` | Per-file read/write latency and high-latency alert |

### `security/`

| Script | Description |
|--------|-------------|
| `01_login_user_audit.sql` | Server logins, role memberships, database users, object permissions |
| `02_create_login_user.sql` | Template: create login → user → grant roles / permissions |
| `03_orphaned_users.sql` | Detect and fix orphaned database users |
| `04_login_audit_and_failures.sql` | Failed logins, sysadmin members, weak-password check |

### `server-configuration/`

| Script | Description |
|--------|-------------|
| `01_server_config_review.sql` | All sp_configure values, hardware overview, SQL version |
| `02_database_properties.sql` | Recovery model, compatibility, owner, last backup per database |
| `03_linked_servers.sql` | Linked server inventory and connectivity test template |
| `04_tempdb_configuration.sql` | TempDB file layout, PAGELATCH contention, top space consumers |

### `storage/`

| Script | Description |
|--------|-------------|
| `01_disk_space_and_file_growth.sql` | Volume free space, file growth settings, auto-growth events |
| `02_database_size_by_table.sql` | Top tables by reserved/data/index space; VLF count per database |
| `03_add_files_and_autogrowth.sql` | Templates: add data/log files, configure auto-growth |

---

## Usage

1. Open the desired `.sql` file in **SQL Server Management Studio (SSMS)** or **Azure Data Studio**.
2. Review the `DECLARE` block at the top of each script and set the variables for your environment (database name, backup path, thresholds, etc.).
3. Lines commented out with `--` are optional steps or templates — uncomment and adjust as needed.
4. Run against your target instance.

> **Note:** Scripts that modify data (failovers, backups, shrinks, permission changes) should be reviewed and tested in a non-production environment first.

---

## Requirements

- SQL Server 2012 or later (most scripts; a few target 2008 R2+).
- Availability Group scripts require the **AlwaysOn** feature to be enabled.
- Some monitoring queries require **VIEW SERVER STATE** permission.
- Backup scripts require **db_backupoperator** or **sysadmin**.
- Security scripts require **securityadmin** or **sysadmin** for login changes.

---

## Contributing

Pull requests are welcome. Please keep scripts self-contained, add a header comment block explaining purpose and requirements, and place them in the appropriate folder.

---

## License

See [LICENSE](LICENSE).