function Get-RestoreLatestBackupJob {
    <#
    .SYNOPSIS
        Retrieves the latest backup job run for the specified job name

    .DESCRIPTION
        Queries Cohesity for the most recent successful backup job run. Uses -NumRuns parameter
        for efficient API calls by limiting results to only the latest run.

    .PARAMETER JobName
        The Cohesity protection job name to query

    .PARAMETER SourceDatabase
        The source database name (used for logging)

    .OUTPUTS
        Object representing the latest job run with jobId and other properties

    .EXAMPLE
        $latestJob = Get-RestoreLatestBackupJob -JobName "DB_FRA1" -SourceDatabase "MyDB"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [String]$JobName,

        [Parameter(Mandatory = $True)]
        [String]$SourceDatabase
    )

    $ErrorActionPreference = 'Stop'

    Write-Information "Retrieving latest backup job for '$SourceDatabase'"

    # Use -NumRuns to efficiently get only the latest run
    $latestJobRun = Get-CohesityProtectionJobRun -JobName $JobName -RunTypes 'kRegular' -NumRuns 1

    if ($null -eq $latestJobRun) {
        throw "No backup jobs found for job '$JobName'"
    }

    Write-Information "Found backup job run ID: $($latestJobRun.jobId)"
    return $latestJobRun
}
