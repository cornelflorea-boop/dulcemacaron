function Wait-RestoreTaskCompletion {
    <#
    .SYNOPSIS
        Monitors a Cohesity restore task until completion

    .DESCRIPTION
        Polls a Cohesity restore task status until it reaches a terminal state (kFinished, kError, kCanceled).
        Includes timeout protection to prevent infinite loops. Returns success/failure status with error details.

    .PARAMETER TaskId
        The Cohesity restore task ID to monitor

    .PARAMETER DatabaseName
        The database name being restored (used for logging)

    .PARAMETER CheckIntervalSeconds
        Seconds to wait between status checks (default: 6)

    .PARAMETER MaxWaitMinutes
        Maximum time to wait for restore completion in minutes (default: 120)

    .OUTPUTS
        PSCustomObject with Success (bool), Status (object), and Error (string) properties

    .EXAMPLE
        Wait-RestoreTaskCompletion -TaskId "12345" -DatabaseName "MyDB" -CheckIntervalSeconds 10
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [String]$TaskId,

        [Parameter(Mandatory = $True)]
        [String]$DatabaseName,

        [Parameter(Mandatory = $False)]
        [Int]$CheckIntervalSeconds = 6,

        [Parameter(Mandatory = $False)]
        [Int]$MaxWaitMinutes = 120
    )

    $ErrorActionPreference = 'Stop'

    Write-Information "Restore task started with ID: '$TaskId' (timeout: $MaxWaitMinutes minutes)"

    # Get-CohesityRestoreTask is a compiled DLL cmdlet that ignores HttpClientHandler cert bypass
    # on PS7/.NET 6+. Use Invoke-RestApi directly (uses -SkipCertificateCheck on PS6+).
    $status = (Invoke-CohesityRestApi -Method Get -Uri "/irisservices/api/v1/public/restore/tasks/$TaskId")
    $startTime = Get-Date

    while ($status.status -notin @('kFinished', 'kError', 'kCanceled')) {
        $elapsed = ((Get-Date) - $startTime).TotalMinutes

        if ($elapsed -ge $MaxWaitMinutes) {
            Write-Warning "Restore task timeout after $MaxWaitMinutes minutes for '$DatabaseName'"
            return [PSCustomObject]@{
                Success = $false
                Status  = $status
                Error   = "Restore task timeout after $MaxWaitMinutes minutes"
            }
        }

        Write-Information "Restoring '$DatabaseName' - Status: $($status.status) (Elapsed: $([math]::Round($elapsed, 1)) min)"
        Start-Sleep -Seconds $CheckIntervalSeconds
        $status = (Invoke-CohesityRestApi -Method Get -Uri "/irisservices/api/v1/public/restore/tasks/$TaskId")
    }

    Write-Information "Restore task completed for '$DatabaseName' with status: $($status.status)"

    # Check final status
    if ($status.status -eq 'kError' -or $status.status -eq 'kCanceled') {
        $errorMessage = if ($status.Error) { $status.Error } else { "Task ended with status: $($status.status)" }
        Write-Warning "Restore failed for '$DatabaseName': $errorMessage"
        return [PSCustomObject]@{
            Success = $false
            Status  = $status
            Error   = $errorMessage
        }
    }

    # Check for errors even on kFinished status
    if ($status.Error) {
        Write-Warning "Restore job for '$DatabaseName' finished with errors: $($status.Error)"
        return [PSCustomObject]@{
            Success = $false
            Status  = $status
            Error   = $status.Error
        }
    }

    Write-Information "Successfully restored '$DatabaseName'"
    return [PSCustomObject]@{
        Success = $true
        Status  = $status
        Error   = $null
    }
}
