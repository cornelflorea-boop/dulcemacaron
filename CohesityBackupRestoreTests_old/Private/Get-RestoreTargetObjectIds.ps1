function Get-RestoreTargetObjectIds {
    <#
    .SYNOPSIS
        Retrieves Cohesity target object IDs for the specified server

    .DESCRIPTION
        Looks up the target server in Cohesity and returns its parent object ID.
        Uses the shared Get-RestoreServerParentId helper function.

    .PARAMETER TargetServer
        The target SQL Server hostname

    .PARAMETER ServerIdCache
        Optional hashtable for caching server IDs to improve performance with multiple databases

    .OUTPUTS
        String representing the target server's parent object ID

    .EXAMPLE
        $targetId = Get-RestoreTargetObjectIds -TargetServer "server02"

    .EXAMPLE
        $cache = @{}
        $targetId = Get-RestoreTargetObjectIds -TargetServer "server02" -ServerIdCache $cache
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

    # Use helper function to get parent ID with optional cache
    $targetParentId = Get-RestoreServerParentId -ServerName $TargetServer -Cache $ServerIdCache

    return $targetParentId
}
