function Invoke-RestoreSingleDatabase {
    <#
    .SYNOPSIS
        Orchestrates the restore of a single database from Cohesity backup

    .DESCRIPTION
        Performs complete restore workflow for a single SQL Server database:
        1. Retrieves target SQL Server default paths
        2. Gets latest backup job from Cohesity
        3. Looks up source and target object IDs
        4. Initiates restore operation
        5. Monitors restore task until completion
        Returns success/failure status with error details.

    .PARAMETER SourceServer
        The source SQL Server hostname where the database was backed up

    .PARAMETER SourceDatabase
        The source database name to restore

    .PARAMETER TargetServer
        The target SQL Server hostname where the database will be restored

    .PARAMETER JobName
        The Cohesity protection job name containing the backup

    .PARAMETER DefaultInstance
        SQL Server instance name (default: MSSQLSERVER)

    .PARAMETER RestoreSuffix
        Suffix to append to restored database name (default: -restored)

    .PARAMETER StatusCheckIntervalSeconds
        Seconds to wait between restore status checks (default: 6)

    .PARAMETER SqlCredential
        PSCredential object for SQL Server authentication via PowerShell Remoting

    .PARAMETER ServerIdCache
        Optional hashtable for caching server IDs to improve performance with multiple databases

    .OUTPUTS
        PSCustomObject with Success (bool), Status (object), and Error (string) properties

    .EXAMPLE
        $result = Invoke-RestoreSingleDatabase -SourceServer "srv01" -SourceDatabase "DB1" -TargetServer "srv02" -JobName "SQL_Backup" -SqlCredential $creds

    .EXAMPLE
        $cache = @{}
        $result = Invoke-RestoreSingleDatabase -SourceServer "srv01" -SourceDatabase "DB1" -TargetServer "srv02" -JobName "SQL_Backup" -SqlCredential $creds -ServerIdCache $cache
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [String]$SourceServer,

        [Parameter(Mandatory = $True)]
        [String]$SourceDatabase,

        [Parameter(Mandatory = $True)]
        [String]$TargetServer,

        [Parameter(Mandatory = $True)]
        [String]$JobName,

        [Parameter(Mandatory = $False)]
        [String]$DefaultInstance = 'MSSQLSERVER',

        [Parameter(Mandatory = $False)]
        [String]$RestoreSuffix = '-restored',

        [Parameter(Mandatory = $False)]
        [Int]$StatusCheckIntervalSeconds = 6,

        [Parameter(Mandatory = $True)]
        [PSCredential]$SqlCredential,

        [Parameter(Mandatory = $False)]
        [Hashtable]$ServerIdCache
    )

    $ErrorActionPreference = 'Stop'

    try {
        # Build target database name
        $targetDatabase = "$SourceDatabase$RestoreSuffix"

        # Get target SQL Server default paths (uses Windows authentication via Invoke-Command)
        $targetPaths = Get-RestoreTargetPaths -TargetServer $TargetServer -SqlCredential $SqlCredential

        # Get latest backup job
        $latestJobRun = Get-RestoreLatestBackupJob -JobName $JobName -SourceDatabase $SourceDatabase

        # Get source object IDs with optional cache
        $sourceIds = Get-RestoreSourceObjectIds -SourceServer $SourceServer -SourceDatabase $SourceDatabase -ServerIdCache $ServerIdCache

        # Get target object (full protection source info needed for targetHost payload)
        $targetInfo = Get-RestoreTargetObjectIds -TargetServer $TargetServer -ServerIdCache $ServerIdCache

        # Build targetHostObject matching Restore-CohesityRemoteMSSQLObject payload structure.
        # Physical hosts need type=6 and a physicalEntity block; VMware hosts need type=1 and vmwareEntity.
        $targetHostObject = @{ id = $targetInfo.ParentId }
        $targetHostParentSource = $null
        $protSrc = $targetInfo.ProtectionSource
        if ($protSrc -and $protSrc.environment -eq 'kVMware') {
            $targetHostObject['type'] = 1
            $targetHostObject['parentId'] = $protSrc.parentId
            $targetHostObject['vmwareEntity'] = @{ type = 8; name = $protSrc.vmWareProtectionSource.name }
            $targetHostParentSource = @{ id = $protSrc.parentId }
        } else {
            $targetHostObject['type'] = 6
            if ($protSrc -and $protSrc.physicalProtectionSource) {
                $targetHostObject['physicalEntity'] = @{
                    type     = 1
                    name     = $protSrc.physicalProtectionSource.name
                    hostType = 1
                    osName   = $protSrc.physicalProtectionSource.osName
                }
            }
        }

        # Start the restore operation
        # Restore-CohesityMSSQLObject is a compiled DLL cmdlet that ignores HttpClientHandler
        # cert bypass on PS7/.NET 6+. Build the REST payload directly and use Invoke-CohesityRestApi,
        # same structure as Restore-CohesityRemoteMSSQLObject.
        Write-Information "Starting restore task for '$SourceDatabase' to '$TargetServer'"
        $jobRunId     = $latestJobRun.backupRun.jobRunId
        $startTimeUs  = $latestJobRun.copyRun[0].runStartTimeUsecs
        # jobUid: prefer from searchvms result (sourceIds.JobUid), fall back to protectionRun
        $jobUid = if ($sourceIds.JobUid) { $sourceIds.JobUid } else { $latestJobRun.jobUid }
        $payload = @{
            action           = 'kRecoverApp'
            name             = "SQL Restore test - $SourceDatabase"
            restoreAppParams = @{
                type             = 3  # kSQL
                ownerRestoreInfo = @{
                    ownerObject        = @{
                        jobUid         = $jobUid
                        jobId          = $latestJobRun.jobId
                        jobInstanceId  = $jobRunId
                        startTimeUsecs = $startTimeUs
                        entity         = @{ id = $sourceIds.ParentId }
                    }
                    ownerRestoreParams = @{
                        action           = 'kRecoverVMs'
                        powerStateConfig = @{}
                    }
                    performRestore     = $false
                }
                restoreAppObjectVec = @(@{
                    appEntity     = $sourceIds.AppEntity
                    restoreParams = @{
                        sqlRestoreParams = @{
                            captureTailLogs     = $false
                            dataFileDestination = $targetPaths.DataPath
                            logFileDestination  = $targetPaths.LogPath
                            newDatabaseName     = $targetDatabase
                            instanceName        = $DefaultInstance
                            isMultiStageRestore = $false
                        }
                        targetHost             = $targetHostObject
                        targetHostParentSource = $targetHostParentSource
                    }
                })
            }
        }
        $resp = Invoke-CohesityRestApi -Method Post -Uri '/irisservices/api/v1/recoverApplication' -Body ($payload | ConvertTo-Json -Depth 20)

        if ($Global:CohesityAPIStatus.StatusCode -ne 200) {
            throw "Failed to start restore task for '$SourceDatabase': $($Global:CohesityAPIStatus.ErrorMessage)"
        }

        $taskId = $resp.restoreTask.performRestoreTaskState.base.taskId
        if ($null -eq $taskId) {
            throw "Failed to start restore task for '$SourceDatabase': no taskId in response"
        }
        $restoreTask = @{ id = $taskId }

        # Monitor restore task until completion
        $result = Wait-RestoreTaskCompletion `
            -TaskId $restoreTask.id `
            -DatabaseName $SourceDatabase `
            -CheckIntervalSeconds $StatusCheckIntervalSeconds

        return $result
    }
    catch {
        Write-Warning "Error during restore of '$SourceDatabase': $($_.Exception.Message)"
        return [PSCustomObject]@{
            Success = $false
            Status  = $null
            Error   = $_.Exception.Message
        }
    }
}
