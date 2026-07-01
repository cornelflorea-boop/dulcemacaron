@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'CohesityBackupRestoreTests.psm1'

    # Version number of this module.
    ModuleVersion = '2.4.0'

    # ID used to uniquely identify this module
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

    # Author of this module
    Author = 'Cornel Florea'

    # Company or vendor of this module
    CompanyName = 'Rakuten'

    # Copyright statement for this module
    Copyright = '(c) 2026 Cornel Florea. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Automated restore testing for Cohesity backups (SQL Server databases and VMware VMs) with CITIDAuto monitoring and Box reporting. Runs as scheduled job to validate backup recoverability.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{ ModuleName = 'Cohesity.Powershell'; ModuleVersion = '1.0' }
        @{ ModuleName = 'SqlServer'; ModuleVersion = '21.0' }
        @{ ModuleName = 'Rakuten.IT.SecretServer'; ModuleVersion = '3.1' }
        @{ ModuleName = 'Rakuten.IT.CITIDAuto'; ModuleVersion = '1.35' }
        @{ ModuleName = 'Rakuten.IT.Box'; ModuleVersion = '6.8' }
        @{ ModuleName = 'Rakuten.IT.Utils'; ModuleVersion = '2.1' }
    )

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @('CohesityBackupRestoreTests')

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('Cohesity', 'Backup', 'Restore', 'SQL', 'Testing', 'Automation')

            # A URL to the license for this module.
            # LicenseUri = ''

            # A URL to the main website for this project.
            # ProjectUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
Version 2.4.0 (2026-05-13)
- Automated VM cleanup: restored VMs deleted from vCenter (including datastore files) after successful restore
- New private function: Remove-RestoredVM (connects via Secret Server secret 8236, deletes VM permanently)
- New settings: VCenterServer, VCenterSecretId; deletion skipped with warning if absent
- Requires VMware PowerCLI on execution host

Version 2.3.0 (2026-05-07)
- Added VM restore phase [5/6]: restores each unique sourceServer as a VMware VM
- New private function: Invoke-VMRestoreTest (wraps Restore-CohesityVMwareVM + Wait-RestoreTaskCompletion)
- RestoreType column added to all results (SQL / VM) in Box CSV and HTML email
- Type column added as first column in email detail table
- Restored VMs remain in vCenter (powered off, no network) for manual cleanup
- Phase numbers updated from x/5 to x/6

Version 2.2.0 (2026-05-06)
- Added DBCC CHECKDB integrity verification after each successful restore
- CheckDBStatus column added to Box CSV report and HTML email
- Added automatic cleanup: restored databases are dropped after testing
- New private functions: Invoke-RestoreCheckDB, Remove-RestoredDatabase
- New Pester test: test/CohesitySQLBackupRestoreTests.VMRestore.Tests.ps1

Version 2.1.0 (2026-05-06)
- Added HTML email notification after each run (matches RFRAccounting design)
- Email includes overall status banner, run summary, and per-database detail table
- Added DatabaseSizeMB column: queries restored DB size via sys.master_files
- SmtpSecretId 35786 used for SMTP authentication
- Requires Rakuten.IT.Utils 2.1 (Send-BetterMailMessage)

Version 2.0.0 (2026-02-17)
- Replaced MorningCheck with CITIDAuto for error reporting
- Added Box integration for test results upload
- Removed timestamps from log messages (cleaner output)
- Export results to temp CSV file with automatic upload to Box
- Ticket deduplication to prevent spam on repeated failures
- Priority: Critical, Components: IssueHandler: IOC, IssueOwner: Core, IssueType: Incident

Version 1.0.0 (2024-06-06)
- Initial release
- Automated SQL restore testing from Cohesity backups
- SecretServer integration for credential management
- MorningCheck integration for error monitoring
- Batch processing with error tracking and summary reports
'@
        }
    }
}
