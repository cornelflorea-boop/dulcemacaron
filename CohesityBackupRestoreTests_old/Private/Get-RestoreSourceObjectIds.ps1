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
        PSCustomObject with SourceId, ParentId, AppEntity (full entity from searchvms), and JobUid properties

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

    # Find-CohesityObjectsForRestore is a compiled DLL cmdlet that ignores HttpClientHandler
    # cert bypass on PS7/.NET 6+. Use Invoke-RestApi directly (uses -SkipCertificateCheck on PS6+).
    $searchResult = Invoke-CohesityRestApi -Method Get -Uri "/irisservices/api/v1/searchvms?environment=SQL&entityTypes=kSQL&onlyLatestVersion=true&searchString=$SourceDatabase"

    $source = $searchResult.vms |
        Where-Object { $_.vmDocument.objectId.entity.sqlEntity.databaseName -eq $SourceDatabase } |
        Where-Object { $_.vmDocument.objectId.entity.sqlEntity.ownerId -eq $parentId } |
        Select-Object -First 1

    if ($null -eq $source) {
        throw "Could not find source database object for '$SourceDatabase' on server '$SourceServer'"
    }

    $sourceId  = $source.vmDocument.objectId.entity.id
    $appEntity = $source.vmDocument.objectId.entity
    $jobUid    = $source.vmDocument.objectId.jobUid
    Write-Information "Found database source ID: $sourceId"
    return [PSCustomObject]@{
        SourceId   = $sourceId
        ParentId   = $parentId
        AppEntity  = $appEntity
        JobUid     = $jobUid
    }
}
