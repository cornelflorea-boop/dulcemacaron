function Get-RestoredDatabaseSizeMB {
    <#
    .SYNOPSIS
        Queries the total on-disk size of a restored SQL Server database in MB

    .DESCRIPTION
        Connects to the target SQL Server via PowerShell Remoting and queries
        sys.master_files to calculate the total size (data + log files) of the
        specified database. Returns size in MB rounded to 2 decimal places.

    .PARAMETER TargetServer
        The target SQL Server hostname where the database was restored

    .PARAMETER DatabaseName
        The name of the restored database to measure (including suffix, e.g. MyDB-restored)

    .PARAMETER SqlCredential
        PSCredential object containing domain credentials for PowerShell Remoting

    .OUTPUTS
        Decimal - database size in MB, or $null if the query fails

    .EXAMPLE
        $sizeMB = Get-RestoredDatabaseSizeMB -TargetServer "srv02" -DatabaseName "MyDB-restored" -SqlCredential $creds
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

    Write-Information "Querying database size for '$DatabaseName' on '$TargetServer'"

    $sqlQuery = @"
SELECT CAST(SUM(size * 8.0 / 1024) AS DECIMAL(10,2)) AS SizeMB
FROM sys.master_files
WHERE database_id = DB_ID('$DatabaseName')
"@

    $result = Invoke-Command -ComputerName $TargetServer -Credential $SqlCredential -ScriptBlock {
        param($Query)
        Invoke-Sqlcmd -ServerInstance 'localhost' -Query $Query -QueryTimeout 600
    } -ArgumentList $sqlQuery

    if ($null -eq $result -or $null -eq $result.SizeMB) {
        throw "Size query returned no result for '$DatabaseName' - database may not exist on '$TargetServer'"
    }

    $sizeMB = [math]::Round([decimal]$result.SizeMB, 2)
    Write-Information "Database '$DatabaseName' size on disk: $sizeMB MB"
    return $sizeMB
}
