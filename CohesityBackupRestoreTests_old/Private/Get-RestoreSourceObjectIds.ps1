function Get-RestoreSourceObjectIds {
    <#
    .SYNOPSIS
        Retrieves Cohesity source object IDs for the specified server and database

    .DESCRIPTION
        Looks up the Cohesity object IDs needed for restore operations. First finds the server's
        parent ID, then locates the specific database object ID. Uses -Search parameter for
        efficient API calls.

    .PARAMETER SourceServer
        The source SQL Server hostname

    .PARAMETER SourceDatabase
        The source database name to find

    .PARAMETER ServerIdCache
        Optional hashtable for caching server IDs to improve performance with multiple databases

    .OUTPUTS
        PSCustomObject with SourceId (database object ID) and ParentId (server object ID) properties

    .EXAMPLE
        $ids = Get-RestoreSourceObjectIds -SourceServer "server01" -SourceDatabase "MyDB"

    .EXAMPLE
        $cache = @{}
        $ids = Get-RestoreSourceObjectIds -SourceServer "server01" -SourceDatabase "MyDB" -ServerIdCache $cache
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [String]$SourceServer,

        [Parameter(Mandatory = $True)]
        [String]$SourceDatabase,

        [Parameter(Mandatory = $False)]
        [Hashtable]$ServerIdCache
    )

    $ErrorActionPreference = 'Stop'

    Write-Information "Retrieving source object IDs for server '$SourceServer' and database '$SourceDatabase'"

    # Get Source's Parent ID using helper function with optional cache
    $parentId = Get-RestoreServerParentId -ServerName $SourceServer -Cache $ServerIdCache

    # Get Source database object ID - use -Search parameter for efficiency
    $Source = Find-CohesityObjectsForRestore -Search $SourceDatabase -Environments kSQL |
        Where-Object { $_.ObjectName -like "*/$SourceDatabase" } |
        Select-Object -ExpandProperty SnapshottedSource |
        Where-Object { $_.ParentId -eq $parentId } |
        Select-Object -First 1 -Property Id

    if ($null -eq $Source) {
        throw "Could not find source database object for '$SourceDatabase' on server '$SourceServer'"
    }

    Write-Information "Found database source ID: $($Source.Id)"
    return [PSCustomObject]@{
        SourceId = $Source.Id
        ParentId = $parentId
    }
}
