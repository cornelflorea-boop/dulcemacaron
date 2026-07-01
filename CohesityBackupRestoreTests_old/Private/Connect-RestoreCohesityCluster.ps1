function Connect-RestoreCohesityCluster {
    <#
    .SYNOPSIS
        Connects to Cohesity cluster using credentials from Secret Server

    .DESCRIPTION
        Retrieves credentials from Secret Server and establishes connection to Cohesity cluster.
        Returns credential object for use in SQL Server authentication operations.

    .PARAMETER Cluster
        The Cohesity cluster hostname or IP address

    .PARAMETER SecretID
        Secret Server ID containing Cohesity credentials (domain, username, password)

    .OUTPUTS
        PSCustomObject with Username, Password, and Domain properties for SQL authentication

    .EXAMPLE
        $creds = Connect-RestoreCohesityCluster -Cluster "cohesity01" -SecretID 12345
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [String]$Cluster,

        [Parameter(Mandatory = $True)]
        [Int]$SecretID
    )

    $ErrorActionPreference = 'Stop'

    try {
        Write-Information "Retrieving credentials from Secret Server (Secret ID: $SecretID)"
        $cohesitySecret = Get-SSSecret -SecretId $SecretID -As PlainText

        # Combine domain and username for Active Directory authentication
        $cohesityUsername = "$($cohesitySecret.Domain)\$($cohesitySecret.Username)"
        $cohesityPassword = ConvertTo-SecureString -String $cohesitySecret.Password -AsPlainText -Force
        $cohesityCreds = New-Object System.Management.Automation.PSCredential ($cohesityUsername, $cohesityPassword)

        Write-Information "Connecting to Cohesity cluster '$Cluster' as '$cohesityUsername'"
        Connect-CohesityCluster -Server $Cluster -Credential $cohesityCreds
        Write-Information "Successfully connected to Cohesity cluster"

        # Return credentials object for SQL Server authentication
        return [PSCustomObject]@{
            Username = $cohesitySecret.Username
            Password = $cohesitySecret.Password
            Domain   = $cohesitySecret.Domain
        }
    }
    catch {
        Write-Warning "Failed to connect to Cohesity cluster '$Cluster': $($_.Exception.Message)"
        throw
    }
}
