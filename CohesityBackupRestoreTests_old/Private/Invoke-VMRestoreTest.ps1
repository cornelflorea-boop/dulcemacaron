function Invoke-VMRestoreTest {
    <#
    .SYNOPSIS
        Restores a single VMware VM from a Cohesity backup and waits for completion

    .DESCRIPTION
        Searches for the VM in Cohesity, extracts the latest restore point, triggers a
        Restore-CohesityVMwareVM task with network disabled, and polls until the task
        reaches a terminal state. Returns a result object compatible with the main loop.

    .PARAMETER VMName
        The exact VM name as it appears in Cohesity backups

    .PARAMETER RestoreSuffix
        Suffix to append to the restored VM name (e.g. '-restored')

    .PARAMETER MaxWaitMinutes
        Maximum minutes to wait for the restore task to complete (default: 120)

    .PARAMETER CheckIntervalSeconds
        Seconds between status poll calls (default: 6)

    .OUTPUTS
        PSCustomObject with Success (bool), RestoredVMName (string), Error (string)

    .EXAMPLE
        Invoke-VMRestoreTest -VMName 'sqlsrv01' -RestoreSuffix '-restored'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [string]$VMName,

        [Parameter(Mandatory = $True)]
        [string]$RestoreSuffix,

        [Parameter(Mandatory = $False)]
        [int]$MaxWaitMinutes = 120,

        [Parameter(Mandatory = $False)]
        [int]$CheckIntervalSeconds = 6
    )

    try {
        Write-Information "Searching Cohesity for VM: '$VMName'"
        # Find-CohesityObjectsForRestore is a compiled DLL cmdlet that ignores HttpClientHandler
        # cert bypass on PS7/.NET 6+. Use Invoke-RestApi directly (uses -SkipCertificateCheck on PS6+).
        $searchResult = Invoke-CohesityRestApi -Method Get -Uri "/irisservices/api/v1/searchvms?entityTypes=kVMware&onlyLatestVersion=true&searchString=$VMName"

        $vm = $searchResult.vms |
            Where-Object { $_.vmDocument.objectId.entity.displayName -eq $VMName -or $_.vmDocument.objectAliases -contains $VMName } |
            Select-Object -First 1

        if (-not $vm) {
            return [PSCustomObject]@{
                Success        = $false
                RestoredVMName = $null
                Error          = "VM '$VMName' not found in Cohesity backups"
            }
        }

        $sourceId         = $vm.vmDocument.objectId.entity.id
        $jobId            = $vm.vmDocument.objectId.jobId
        $latestVersion    = $vm.vmDocument.versions | Select-Object -First 1
        $jobRunId         = $latestVersion.instanceId.jobInstanceId
        $startedTimeUsecs = $latestVersion.instanceId.jobStartTimeUsecs

        Write-Information "Found VM '$VMName' (SourceId: $sourceId, JobId: $jobId). Starting restore..."

        $restoreTask = Restore-CohesityVMwareVM `
            -SourceId $sourceId `
            -JobId $jobId `
            -JobRunId $jobRunId `
            -StartTime $startedTimeUsecs `
            -VmNameSuffix $RestoreSuffix `
            -DisableNetwork `
            -ErrorAction Stop

        $waitResult = Wait-RestoreTaskCompletion `
            -TaskId $restoreTask.id `
            -DatabaseName $VMName `
            -CheckIntervalSeconds $CheckIntervalSeconds `
            -MaxWaitMinutes $MaxWaitMinutes

        return [PSCustomObject]@{
            Success        = $waitResult.Success
            RestoredVMName = "$VMName$RestoreSuffix"
            Error          = $waitResult.Error
        }
    }
    catch {
        return [PSCustomObject]@{
            Success        = $false
            RestoredVMName = $null
            Error          = $_.Exception.Message
        }
    }
}
