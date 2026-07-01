@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'CohesityBackupRestoreTests.psm1'

    # Version number of this module.
    ModuleVersion = '2.5.8'

    # ID used to uniquely identify this module
    GUID = 'b2c3d4e5-f6a7-8901-bcde-f12345678901'

    # Author of this module
    Author = 'Cornel Florea'

    # Company or vendor of this module
    CompanyName = 'Rakuten'

    # Copyright statement for this module
    Copyright = '(c) 2026 Cornel Florea. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Automated restore testing for Cohesity backups (SQL Server databases and VMware VMs) with CITIDAuto monitoring and Box reporting. Runs as scheduled job to validate backup recoverability. PS7 port for new worker servers.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{ ModuleName = 'Cohesity.Powershell'; ModuleVersion = '1.0' }
        @{ ModuleName = 'SqlServer'; ModuleVersion = '21.0' }
        @{ ModuleName = 'Rakuten.IT.SecretServer'; ModuleVersion = '3.1' }
        @{ ModuleName = 'Rakuten.IT.CITIDAuto'; ModuleVersion = '1.39.2080' }
        @{ ModuleName = 'Rakuten.IT.Box'; ModuleVersion = '8.5.2075' }
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

            # ReleaseNotes of this module
            ReleaseNotes = @'
Version 2.5.8 (2026-06-03)
- Fixed VM restore search: /searchvms?environment=VMware returns nothing for these hosts;
  changed to entityTypes=kVMware (same parameter used internally by Restore-CohesityVMwareVM)

Version 2.5.7 (2026-06-03)
- Fixed HTTP 500 on /recoverApplication: payload was missing required fields compared to
  Restore-CohesityRemoteMSSQLObject reference implementation:
  - appEntity: now passes the full entity object from searchvms (not bare {id,type})
  - targetHost: now includes type=6 and physicalEntity block (name/hostType/osName) for physical hosts
  - jobUid: now sourced from searchvms result (not from protectionRun which has a different structure)
  - Get-RestoreTargetObjectIds now returns ProtectionSource object (Get-CohesityProtectionSource)
    so Invoke-RestoreSingleDatabase can build the correct targetHostObject
- Invoke-CohesityRestApi: error handler now reads Cohesity response body on HTTP errors
  so the actual errorCode/message from the cluster appears in logs

Version 2.5.6 (2026-06-03)
- Fixed "Invoke-RestApi not recognized" error: Invoke-RestApi is an internal (non-exported) function
  of Cohesity.PowerShell and cannot be called from outside the module scope. Replaced all 4 call sites
  with a new private function Invoke-CohesityRestApi that reads cohesityUserProfile directly and calls
  Invoke-WebRequest -SkipCertificateCheck (same logic, no module boundary issue).

Version 2.5.5 (2026-06-02)
- Replaced three compiled DLL cmdlets with direct Invoke-RestApi calls to fix SSL PartialChain
  errors on PS7/.NET 6+ (compiled cmdlets bypass HttpClientHandler and ignore -SkipCertificateCheck):
  - Find-CohesityObjectsForRestore -> /irisservices/api/v1/searchvms (Get-RestoreSourceObjectIds, Invoke-VMRestoreTest)
  - Restore-CohesityMSSQLObject   -> /irisservices/api/v1/recoverApplication (Invoke-RestoreSingleDatabase)
  - Get-CohesityRestoreTask       -> /irisservices/api/v1/public/restore/tasks/{id} (Wait-RestoreTaskCompletion)
- Removed temp troubleshooting scripts (decode_restore.ps1, Get-CohesityCACert.ps1)

Version 2.5.4 (2026-06-02)
- Fixed SSL PartialChain error (take 2): Connect-CohesityCluster.ProcessRecord constructs a fresh
  UserProfile(AllowInvalidServerCertificates=false) before auth, overwriting any env var pre-seeded.
  Now bypasses Connect-CohesityCluster entirely — obtains access token via Invoke-RestMethod
  -SkipCertificateCheck and writes session directly into cohesityUserProfile env var, same pattern
  as DomoReportstoBox/Get-CohesityReport.ps1

Version 2.5.3 (2026-06-02)
- Fixed SSL PartialChain error on PS7: replaced ServicePointManager hack (no-op in .NET 6+) with
  pre-seeding the 'cohesityUserProfile' env var (AllowInvalidServerCertificates=true) so the
  Cohesity module's HttpClientHandler is built with cert bypass enabled at connect time
- Removed unused New-InsecureCertCallback helper

Version 2.5.2 (2026-06-02)
- Bumped Rakuten.IT.CITIDAuto to 1.39.2080 (fixes transitive Rakuten.IT.Box RequiredVersion 8.3.2065 dependency that caused JWT assembly conflict with ChronoTrigger worker)

Version 2.5.1 (2026-06-01)
- Bumped Rakuten.IT.CITIDAuto to 1.38.2070 and Rakuten.IT.Box to 8.5.2075 to resolve JWT assembly conflict on PS7 servers

Version 2.5.0 (2026-06-06)
- Updated Rakuten.IT.Box module version to 8.5.2074

Version 2.4.0 (2026-05-27)
- PS7 port for new worker servers (PowerShellVersion bumped to 7.0)
- Added SSL bypass (InfraVersionsTrustAll Add-Type delegate) around Connect-CohesityCluster
  and Connect-VIServer calls — required for self-signed certs on PS7 (.NET 6+)
- Removed ServicePointManager SecurityProtocol lines (no-op in .NET 6+)
- Added VMware.VimAutomation.Core 12.0 as explicit required module

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

Version 2.1.0 (2026-05-06)
- Added HTML email notification after each run (matches RFRAccounting design)
- Email includes overall status banner, run summary, and per-database detail table
- Added DatabaseSizeMB column: queries restored DB size via sys.master_files
- SmtpSecretId 35786 used for SMTP authentication
- Requires Rakuten.IT.Utils 2.1 (Send-BetterMailMessage)

Version 2.0.0 (2026-02-17)
- Replaced MorningCheck with CITIDAuto for error reporting
- Added Box integration for test results upload
- Export results to temp CSV file with automatic upload to Box
- Ticket deduplication to prevent spam on repeated failures

Version 1.0.0 (2024-06-06)
- Initial release
'@
        }
    }
}
