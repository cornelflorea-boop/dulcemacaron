function Invoke-RestoreCheckDB {
    <#
    .SYNOPSIS
        Runs DBCC CHECKDB on a restored SQL Server database and returns the integrity result

    .DESCRIPTION
        Connects to the target SQL Server via PowerShell Remoting and executes
        DBCC CHECKDB with TABLERESULTS, NO_INFOMSGS. If CHECKDB returns no rows
        the database has no integrity errors (Passed). Any returned rows indicate
        corruption or consistency issues (Failed), and the first error messages are
        included in the result.

    .PARAMETER TargetServer
        The SQL Server hostname where the restored database resides

    .PARAMETER DatabaseName
        The name of the restored database to check (including suffix, e.g. MyDB-restored)

    .PARAMETER SqlCredential
        PSCredential object containing domain credentials for PowerShell Remoting

    .OUTPUTS
        PSCustomObject with Passed (bool) and Message (string) properties

    .EXAMPLE
        $result = Invoke-RestoreCheckDB -TargetServer "srv02" -DatabaseName "MyDB-restored" -SqlCredential $creds
        if ($result.Passed) { Write-Host "Integrity OK" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [String]$TargetServer,

        [Parameter(Mandatory = $True)]
        [String]$DatabaseName,

        [Parameter(Mandatory = $True)]
        [PSCredential]$SqlCredential
    )

    $ErrorActionPreference = 'Stop'

    Write-Information "Running DBCC CHECKDB on '$DatabaseName' at '$TargetServer'"

    # TABLERESULTS returns a result set instead of messages, making it easy to check for errors.
    # NO_INFOMSGS suppresses informational messages so only actual errors are returned.
    $sqlQuery = "DBCC CHECKDB (N'$DatabaseName') WITH TABLERESULTS, NO_INFOMSGS, ALL_ERRORMSGS"

    $checkResults = Invoke-Command -ComputerName $TargetServer -Credential $SqlCredential -ScriptBlock {
        param($Query)
        Invoke-Sqlcmd -ServerInstance 'localhost' -Query $Query -QueryTimeout 600 -ErrorAction Stop
    } -ArgumentList $sqlQuery

    $errorCount = if ($null -eq $checkResults) { 0 } else { @($checkResults).Count }

    if ($errorCount -eq 0) {
        Write-Information "DBCC CHECKDB passed for '$DatabaseName' - no integrity errors"
        return [PSCustomObject]@{ Passed = $true; Message = 'No integrity errors' }
    }

    # Capture first few error messages for the report
    $messages = @($checkResults) |
        Where-Object { $_.PSObject.Properties.Name -contains 'MessageText' -and $_.MessageText } |
        Select-Object -ExpandProperty MessageText |
        Select-Object -First 3

    $summary = if ($messages) { $messages -join ' | ' } else { "CHECKDB returned $errorCount row(s)" }
    Write-Warning "DBCC CHECKDB found $errorCount issue(s) in '$DatabaseName': $summary"
    return [PSCustomObject]@{ Passed = $false; Message = "$errorCount error(s): $summary" }
}
