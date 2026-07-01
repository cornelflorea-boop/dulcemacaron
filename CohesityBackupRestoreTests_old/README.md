# CohesityBackupRestoreTests

Automated restore testing for Cohesity backups (SQL Server databases and VMware VMs). This module performs daily restore tests to validate backup recoverability, uploads results to Box, and reports failures through CITIDAuto monitoring.

## Overview

This PowerShell module automates the process of:
1. Connecting to Box for configuration and results
2. Downloading restore test definitions from Box
3. Retrieving credentials from Secret Server
4. Connecting to Cohesity cluster
5. Restoring SQL databases from latest backups, running DBCC CHECKDB, then dropping the restored copies
6. Restoring each unique source VM as a powered-off, network-disabled clone in vCenter, then deleting it (including datastore files) after a successful restore test
7. Uploading test results to Box
8. Sending an HTML email notification
9. Reporting success/failure statistics
10. Creating CITIDAuto Jira tickets on failures with automatic deduplication

## Module Structure

```
CohesityBackupRestoreTests/
├── CohesityBackupRestoreTests.psd1     # Module manifest
├── CohesityBackupRestoreTests.psm1     # Module loader
├── Settings.psd1                       # Configuration (auto-loaded by cronjob)
├── job-metadata.json                   # Cron schedule configuration
├── README.md                           # Documentation
├── Public/
│   └── CohesityBackupRestoreTests.ps1  # Main exported function
└── Private/
    ├── Connect-RestoreCohesityCluster.ps1  # Cohesity authentication
    ├── Get-RestoreLatestBackupJob.ps1      # Backup job retrieval
    ├── Get-RestoreSourceObjectIds.ps1      # Source object ID lookup
    ├── Get-RestoreTargetObjectIds.ps1      # Target object ID lookup
    ├── Get-RestoreServerParentId.ps1       # Server parent ID lookup with caching
    ├── Get-RestoreTargetPaths.ps1          # SQL Server path queries
    ├── Get-RestoreTestSources.ps1          # CSV validation and loading
    ├── Invoke-RestoreCheckDB.ps1           # DBCC CHECKDB integrity verification
    ├── Invoke-RestoreSingleDatabase.ps1    # SQL database restore orchestration
    ├── Invoke-VMRestoreTest.ps1            # VMware VM restore orchestration
    ├── Remove-RestoredDatabase.ps1         # Post-test database cleanup
    ├── Remove-RestoredVM.ps1               # Post-test VM deletion from vCenter
    ├── Send-RestoreTestNotification.ps1    # HTML email report
    └── Wait-RestoreTaskCompletion.ps1      # Restore task monitoring
```

## Prerequisites

### Required Modules
The following PowerShell modules must be installed on the execution server:
- **Cohesity.Powershell** (v1.0+) - Cohesity API integration
- **SqlServer** (v21.0+) - SQL Server management
- **Rakuten.IT.SecretServer** (v3.1+) - Credential retrieval
- **Rakuten.IT.CITIDAuto** (v1.35+) - Jira integration with ticket deduplication
- **Rakuten.IT.Box** (v6.8+) - Box API access for results upload
- **Rakuten.IT.Utils** (v2.1+) - `Send-BetterMailMessage` for email notifications

### Required Permissions
The service account running the script needs:
- Read access to Secret Server secret ID **36408** (Cohesity credentials)
- Read access to Secret Server secret ID **31699** (Box JWT credentials)
- Read access to Secret Server secret ID **35786** (SMTP credentials)
- Read access to Secret Server secret ID **8236** (vCenter credentials)
- Network access to Cohesity cluster **vbkpcoh-fra1**
- Network access to all source and target SQL Servers
- Network access to Box API (internet connectivity)
- Read/Write access to Box folder ID **350749748450**

### Box Folder Requirements
The Box folder must contain:
- **RestoreTestsSources.csv** - Source file defining which databases/VMs to test (read by script)
- The script will upload **Cohesity-SQL-Restore-Tests-Results.csv** - Test results (written by script)

### Sources CSV File Format
The **RestoreTestsSources.csv** file stored in Box must contain these columns:
```csv
sourceServer,sourceDatabase,targetServer
SQLPROD01,CustomerDB,SQLTEST01
SQLPROD02,InventoryDB,SQLTEST02
SQLPROD03,ReportsDB,
```

**Notes:**
- File is stored in Box folder ID 350749748450
- Filename: `RestoreTestsSources.csv`
- Script downloads this file at runtime
- Rows with empty `targetServer` are skipped for SQL restore (not ready for testing)
- Target database name will be `{sourceDatabase}-restored` (dropped automatically after DBCC CHECKDB)
- Each unique `sourceServer` value is also restored as a VMware VM (suffix `-restored`)
- Downloaded file is automatically deleted after processing

## Configuration

Edit `Settings.psd1` to customize:

```powershell
@{
    # Cohesity Cluster
    CohesityCluster  = 'vbkpcoh-fra1'   # Cohesity cluster hostname
    CohesitySecretID = 36408             # Secret Server ID for credentials

    # Backup Job Configuration
    JobName = 'DB_FRA1'                  # Cohesity protection job name

    # SQL Server Configuration
    DefaultInstance = 'MSSQLSERVER'      # Default SQL instance name
    RestoreSuffix   = '-restored'        # Suffix for restored database/VM names

    # Box Configuration
    BoxSecretID        = 31699                                   # Box JWT authentication credentials
    BoxFolderID        = '350749748450'                          # Box folder for sources CSV and results
    BoxSourcesFilename = 'RestoreTestsSources.csv'               # Sources CSV file in Box
    BoxReportFilename  = 'Cohesity-SQL-Restore-Tests-Results.csv' # Results file to upload

    # vCenter Configuration
    VCenterServer   = 'vcenter-fra001'   # vCenter hostname for VM deletion
    VCenterSecretId = 8236               # Secret Server ID for vCenter credentials

    # Monitoring
    StatusCheckIntervalSeconds = 6       # Seconds between restore status checks

    # Email Notification Settings
    EmailEnabled = $true
    SmtpSecretId = 35786                 # SMTP authentication credentials
    EmailTo      = @('citd-eu-svr@mail.rakuten.com')
    EmailFrom    = 'sv-exch-eutd-sql-ar@rakuten.com'
    SmtpServer   = 'mail.intra.rakuten.co.jp'
    SmtpPort     = 587
}
```

## Automated Execution

The script runs automatically via cronjob based on the schedule defined in `job-metadata.json`:

```json
{
    "CronExpression": "0 19 * * *"
}
```

**Schedule**: Runs daily at **19:00**

**Automated Process:**
1. Cronjob pulls latest code from Git
2. Reads `job-metadata.json` for schedule
3. Imports the module
4. Loads Settings.psd1
5. Executes `CohesityBackupRestoreTests @settings`
6. Uploads results to Box
7. Sends HTML email report
8. Creates Jira ticket if failures occur

**Result Storage:**
- Test results automatically uploaded to Box folder ID 350749748450
- Console output captured by scheduler for logging
- CITIDAuto Jira tickets created on failures

## Output and Logging

The module uses PowerShell information streams:

- **Write-Information**: Normal operation logs
- **Write-Warning**: Non-fatal errors (e.g., skipped databases)
- **Throw**: Fatal errors (triggers CITIDAuto ticket)

**Logging:**
- Module does NOT write to log files directly
- No timestamps in output (scheduler provides timestamps)
- Console output captured automatically by cronjob scheduler
- All test results uploaded to Box as CSV
- Execution follows a 6-phase approach: Box connect → Download sources → Cohesity connect → SQL restore tests → VM restore tests → Upload results

## Error Handling

### Non-Fatal Errors (Continue Processing)
- Missing target server in CSV (SQL restore skipped)
- SQL Server connection failures (skipped)
- Backup job not found (skipped)
- Object ID retrieval failures (skipped)
- Individual SQL restore or DBCC CHECKDB failures (logged, continue to next)
- VM not found in Cohesity (logged, continue to next)
- Individual VM restore failures (logged, continue to next)

### Fatal Errors (Stop Processing + Create CITIDAuto Ticket)
- Box connection failure
- CSV file not found
- Secret Server access failure
- Cohesity connection failure
- Module import failures

When fatal errors occur, a Jira ticket is automatically created via `New-CITIDAutoTicket`:
- **Priority**: Critical
- **Summary**: `[CohesityBackupRestoreTests] Backup Restore Tests failed`
- **Description**: Error details + success/failure counts + configuration
- **Components**: IssueHandler: IOC, IssueOwner: Core, IssueType: Incident
- **Deduplication**: Prevents duplicate tickets for repeated failures
- **Data Attachment**: Excel file with test results automatically uploaded to Box and linked in ticket

## Troubleshooting

### Module Import Fails
```powershell
# Check if required modules are installed
Get-Module -ListAvailable Cohesity.Powershell, SqlServer, Rakuten.IT.SecretServer, Rakuten.IT.CITIDAuto, Rakuten.IT.Box, Rakuten.IT.Utils

# Import dependencies manually first
Import-Module Cohesity.Powershell
Import-Module SqlServer
Import-Module Rakuten.IT.SecretServer
Import-Module Rakuten.IT.CITIDAuto
Import-Module Rakuten.IT.Box
Import-Module Rakuten.IT.Utils
```

> **Note**: The Cohesity module causes a TypeData conflict on import (ObjectSecurity defined twice). This is expected and handled internally — the module will still function correctly.

### Secret Server Access Denied
```powershell
# Test Secret Server access
Import-Module Rakuten.IT.SecretServer
Get-SSSecret -SecretId 36408 -As PlainText
```

### Sources CSV File Not Found
**Error**: "Sources CSV file 'RestoreTestsSources.csv' not found in Box folder"
- **Solution**: Upload RestoreTestsSources.csv to Box folder ID 350749748450
- **Check**: Verify filename is exactly `RestoreTestsSources.csv` (case-sensitive on some systems)
- **Check**: Verify Box service account has read access to the file

### Restore Failures
- Check Cohesity cluster connectivity
- Verify backup jobs exist and are recent
- Confirm target SQL Servers are accessible
- Review Cohesity restore task logs

### VM Not Found in Cohesity
- Verify the VM name in `sourceServer` column matches exactly the VM name in Cohesity (case-sensitive)
- Confirm the VM is included in a Cohesity VMware protection job

## Maintenance

### Adding New Databases to Test
1. Download `RestoreTestsSources.csv` from Box folder ID 350749748450
2. Add new rows:
```csv
sourceServer,sourceDatabase,targetServer
SQLPROD04,NewDB,SQLTEST03
```
3. Upload the updated file back to Box (overwrite existing file)
4. Next scheduled run will use the updated list

> **Note**: Each unique `sourceServer` in the CSV is also restored as a VMware VM. If you add a new server row, a VM restore will be attempted for that server name.

### Changing Configuration
Edit `Settings.psd1` and commit changes to Git. The cronjob will automatically pull the latest changes on the next scheduled run.

### Box Upload Fails
- Verify Secret ID 31699 contains valid JWT credentials
- Check network access to Box API
- Verify folder permissions for Box Folder ID 350749748450

## Box Integration

### Test Results Upload
After each run, test results are uploaded to Box as a CSV file. Each row contains:
- **RestoreType**: `SQL` for database restores, `VM` for VMware VM restores
- **SourceServer**: SQL Server or VM name from the sources CSV
- **SourceDatabase**: Database name (SQL restores) or `(VM restore)` (VM restores)
- **TargetServer**: SQL Server where database was restored, or `N/A` for VM restores
- **Status**: Success, Failed, or Skipped
- **DurationMinutes**: Time taken for the restore operation
- **DatabaseSizeMB**: Restored database size in MB (SQL only; `N/A` for VM restores)
- **CheckDBStatus**: DBCC CHECKDB result (SQL only; `N/A` for VM restores)
- **StartTime**: When the restore started
- **EndTime**: When the restore completed
- **ErrorMessage**: Error details if restore failed

**Filename**: `Cohesity-SQL-Restore-Tests-Results.csv`
**Location**: Box Folder ID 350749748450
**Mode**: Appended — previous results are preserved across runs

### Authentication
Uses JWT (JSON Web Token) authentication stored in Secret Server ID 31699.

## Version History

### Version 2.4.0 (2026-05-13)
- **New**: Automated VM cleanup — restored VMs are deleted from vCenter (including datastore files) after a successful restore test
- **New**: `Remove-RestoredVM` private function (connects to vCenter via Secret Server, deletes VM permanently)
- **New**: `VCenterServer` / `VCenterSecretId` settings keys; deletion is skipped with a warning if these are absent
- **Requires**: VMware PowerCLI (`VMware.PowerCLI` or `VMware.VimAutomation.Core`) on the execution host
- **Requires**: Read access to Secret Server secret ID **8236** (vCenter credentials)

### Version 2.3.0 (2026-05-07)
- **New**: VM restore phase — restores each unique `sourceServer` as a VMware VM after SQL phase
- **New**: `Invoke-VMRestoreTest` private function (wraps `Restore-CohesityVMwareVM` + `Wait-RestoreTaskCompletion`)
- **New**: `RestoreType` column (`SQL` / `VM`) in Box CSV and HTML email detail table
- **New**: `Type` column added as first column in email detail table
- **Change**: Phase numbers updated from x/5 to x/6
- **Change**: Module renamed from `CohesitySQLBackupRestoreTests` to `CohesityBackupRestoreTests`
- Restored VMs remain in vCenter (powered off, no network) — cleanup is manual (automated in v2.4.0)

### Version 2.2.0 (2026-05-06)
- **New**: DBCC CHECKDB integrity verification after each successful SQL restore
- **New**: `CheckDBStatus` column in Box CSV and HTML email
- **New**: Automatic cleanup — restored databases are dropped after testing
- **New**: `Invoke-RestoreCheckDB` and `Remove-RestoredDatabase` private functions

### Version 2.1.0 (2026-05-06)
- **New**: HTML email notification after each run (Rakuten red header design)
- **New**: `DatabaseSizeMB` column — queries restored DB size via `sys.master_files`
- **New**: `Send-RestoreTestNotification` private function
- Requires `Rakuten.IT.Utils` 2.1 (`Send-BetterMailMessage`)

### Version 2.0.0 (2026-02-17)
- **Breaking**: Replaced MorningCheck with CITIDAuto for error reporting
- **Breaking**: Sources CSV now stored in Box instead of SMB file share
- **Enhancement**: Added Box integration for test results upload
- **Enhancement**: Removed timestamps from all log messages (scheduler provides them)
- **Enhancement**: Ticket deduplication to prevent spam on repeated failures

### Version 1.0.0 (2024-06-06)
- Initial release
- Modular PowerShell module structure
- SecretServer integration for credentials
- MorningCheck integration for monitoring
- Batch processing with error tracking and summary reports

## Monitoring and Support

**Automated Monitoring:**
- CITIDAuto automatically creates Jira tickets on failures
- Tickets include full error diagnostics and test results
- Ticket deduplication prevents spam on repeated failures
- Check CITIDAUTO project for any reported issues

**Manual Checks:**
- View test results: Box folder ID 350749748450
- Review execution logs: Check cronjob scheduler logs
- Verify schedule: `job-metadata.json` (daily at 19:00)

**Support Contact:** Cornel Florea

## License

Copyright (c) 2026 Cornel Florea. All rights reserved.
