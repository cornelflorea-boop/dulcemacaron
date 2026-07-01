function Get-RestoreTargetObjectIds {
    <#
    .SYNOPSIS
        Retrieves Cohesity target object info for the specified server

    .DESCRIPTION
        Looks up the target server in Cohesity and returns the full object needed to build
        the targetHost block in a /recoverApplication payload. Returns the parent ID plus
        the physicalProtectionSource details (name, hostType, osName) required by the API.

    .PARAMETER TargetServer
        The target SQL Server hostname

    .PARAMETER ServerIdCache
        Optional hashtable for caching server IDs to improve performance with multiple databases

    .OUTPUTS
        PSCustomObject with ParentId (int) and ProtectionSource (object) properties

    .EXAMPLE
        $target = Get-RestoreTargetObjectIds -TargetServer "server02"

    .EXAMPLE
        $cache = @{}
        $target = Get-RestoreTargetObjectIds -TargetServer "server02" -ServerIdCache $cache
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [String]$TargetServer,

        [Parameter(Mandatory = $False)]
        [Hashtable]$ServerIdCache
    )

    $ErrorActionPreference = 'Stop'

    Write-Information "Retrieving target object IDs for '$TargetServer'"

    $cacheKey = "fullobj_$TargetServer"
    if ($ServerIdCache -and $ServerIdCache.ContainsKey($cacheKey)) {
        Write-Information "Using cached target object for server '$TargetServer'"
        return $ServerIdCache[$cacheKey]
    }

    $objects = Get-CohesityObject -SearchString $TargetServer |
        Select-Object -Property * -ExcludeProperty uuid, logicalSizeInBytes, parentSource

    $targetObject = $null
    foreach ($object in $objects) {
        if ($object.source.environment -eq 'kPhysical') {
            $parentId = $object.protectionSourceUidList | Select-Object -ExpandProperty sourceId -First 1
            Write-Information "Found parent ID '$parentId' for server '$TargetServer'"

            $protSource = Get-CohesityProtectionSource -Id $parentId
            $targetObject = [PSCustomObject]@{
                ParentId         = $parentId
                ProtectionSource = $protSource
            }
            break
        }
    }

    if (-not $targetObject) {
        throw "Could not find target object for server '$TargetServer'"
    }

    if ($ServerIdCache) {
        $ServerIdCache[$cacheKey] = $targetObject
        $ServerIdCache[$TargetServer] = $targetObject.ParentId
    }

    return $targetObject
}
