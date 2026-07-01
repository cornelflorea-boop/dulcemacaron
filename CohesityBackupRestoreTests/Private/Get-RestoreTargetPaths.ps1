function Get-RestoreTargetPaths {
    <#
    .SYNOPSIS
        Queries target SQL Server for default data and log file paths

    .DESCRIPTION
        Connects to target SQL Server using PowerShell Remoting with provided credentials
        and queries for default data and log file paths. These paths are used when restoring
        databases to ensure files are placed in the correct locations.

    .PARAMETER TargetServer
        The target SQL Server hostname

    .PARAMETER SqlCredential
        PSCredential object containing domain credentials for SQL Server authentication

    .OUTPUTS
        PSCustomObject with DataPath and LogPath properties (strings with trailing backslash removed)

    .EXAMPLE
        $paths = Get-RestoreTargetPaths -TargetServer "server02" -SqlCredential $creds
        # Returns: @{DataPath = "D:\SQLData"; LogPath = "E:\SQLLogs"}
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [String]$TargetServer,

        [Parameter(Mandatory = $True)]
        [PSCredential]$SqlCredential
    )

    $ErrorActionPreference = 'Stop'

    Write-Information "Querying target server '$TargetServer' for default file paths (using Windows authentication via Invoke-Command)"

    $sqlQuery = @"
SELECT
    SERVERPROPERTY('InstanceDefaultDataPath') AS DefaultDataPath,
    SERVERPROPERTY('InstanceDefaultLogPath') AS DefaultLogPath
"@

    # Use Invoke-Command to run query remotely on SQL server with specified credentials
    $pathResults = Invoke-Command -ComputerName $TargetServer -Credential $SqlCredential -ScriptBlock {
        param($Query)
        Invoke-Sqlcmd -ServerInstance 'localhost' -Query $Query
    } -ArgumentList $sqlQuery

    $dataPath = $pathResults.DefaultDataPath.TrimEnd('\')
    $logPath = $pathResults.DefaultLogPath.TrimEnd('\')

    Write-Information "Target paths - Data: '$dataPath', Log: '$logPath'"

    return [PSCustomObject]@{
        DataPath = $dataPath
        LogPath  = $logPath
    }
}
