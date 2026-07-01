function Remove-RestoredDatabase {
    <#
    .SYNOPSIS
        Drops a restored SQL Server database from the target server

    .DESCRIPTION
        Connects to the target SQL Server via PowerShell Remoting and drops the specified
        database. Uses SET SINGLE_USER WITH ROLLBACK IMMEDIATE to force-close any open
        connections before dropping. Safe to call even if the database does not exist
        (existence is checked first).

    .PARAMETER TargetServer
        The SQL Server hostname where the restored database resides

    .PARAMETER DatabaseName
        The name of the database to drop (e.g. MyDB-restored)

    .PARAMETER SqlCredential
        PSCredential object containing domain credentials for PowerShell Remoting

    .EXAMPLE
        Remove-RestoredDatabase -TargetServer "srv02" -DatabaseName "MyDB-restored" -SqlCredential $creds
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

    Write-Information "Dropping database '$DatabaseName' from '$TargetServer'"

    $sqlQuery = @"
IF EXISTS (SELECT name FROM sys.databases WHERE name = N'$DatabaseName')
BEGIN
    ALTER DATABASE [$DatabaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$DatabaseName];
    PRINT 'Database $DatabaseName dropped successfully.';
END
ELSE
BEGIN
    PRINT 'Database $DatabaseName does not exist - nothing to drop.';
END
"@

    Invoke-Command -ComputerName $TargetServer -Credential $SqlCredential -ScriptBlock {
        param($Query)
        Invoke-Sqlcmd -ServerInstance 'localhost' -Query $Query -ErrorAction Stop
    } -ArgumentList $sqlQuery

    Write-Information "Cleanup complete for '$DatabaseName' on '$TargetServer'"
}
