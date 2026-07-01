function Get-RestoreServerParentId {
    <#
    .SYNOPSIS
        Retrieves the Cohesity parent object ID for a specified server

    .DESCRIPTION
        Looks up a server in Cohesity and returns its parent object ID. This is a shared
        helper function used by both source and target object ID lookups to eliminate
        code duplication. Supports caching to avoid redundant API calls when multiple
        databases share the same server.

    .PARAMETER ServerName
        The server hostname to look up

    .PARAMETER Cache
        Optional hashtable for caching server IDs. If provided, checks cache first before
        making API call, and stores result in cache for future lookups.

    .OUTPUTS
        String representing the server's parent object ID

    .EXAMPLE
        $parentId = Get-RestoreServerParentId -ServerName "server01"

    .EXAMPLE
        $cache = @{}
        $parentId = Get-RestoreServerParentId -ServerName "server01" -Cache $cache
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [String]$ServerName,

        [Parameter(Mandatory = $False)]
        [Hashtable]$Cache
    )

    $ErrorActionPreference = 'Stop'

    # Check cache first if provided
    if ($Cache -and $Cache.ContainsKey($ServerName)) {
        Write-Information "Using cached parent ID for server '$ServerName'"
        return $Cache[$ServerName]
    }

    Write-Information "Retrieving parent ID for server '$ServerName'"

    $objects = Get-CohesityObject -SearchString $ServerName |
        Select-Object -Property * -ExcludeProperty uuid, logicalSizeInBytes, parentSource

    foreach ($object in $objects) {
        if ($object.source.environment -eq 'kPhysical') {
            $parentId = $object.protectionSourceUidList | Select-Object -ExpandProperty sourceId -First 1
            Write-Information "Found parent ID '$parentId' for server '$ServerName'"

            # Store in cache if provided
            if ($Cache) {
                $Cache[$ServerName] = $parentId
            }

            return $parentId
        }
    }

    throw "Could not find parent ID for server '$ServerName'"
}
