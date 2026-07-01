function Connect-RestoreCohesityCluster {
    <#
    .SYNOPSIS
        Connects to Cohesity cluster using credentials from Secret Server

    .DESCRIPTION
        Retrieves credentials from Secret Server and establishes connection to Cohesity cluster.
        Returns credential object for use in SQL Server authentication operations.
        Obtains Cohesity access token via REST (-SkipCertificateCheck) to bypass PartialChain SSL errors on PS7.

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

        $cohesityUsername = "$($cohesitySecret.Domain)\$($cohesitySecret.Username)"
        Write-Information "Connecting to Cohesity cluster '$Cluster' as '$cohesityUsername'"

        # Connect-CohesityCluster is a compiled DLL cmdlet that uses HttpClient internally and
        # ignores ServicePointManager — cert bypass via that mechanism is a no-op on PS7/.NET 6+.
        # Additionally, ProcessRecord constructs a fresh UserProfile (AllowInvalidServerCertificates=false)
        # and calls SetUserProfile before auth, overwriting any env var we pre-seed.
        # Solution (same as DomoReportstoBox): obtain the access token directly via
        # Invoke-RestMethod -SkipCertificateCheck, then write the session into the
        # 'cohesityUserProfile' env var that all subsequent Cohesity cmdlets read.
        $tokenBody = @{
            domain   = $cohesitySecret.Domain
            username = $cohesitySecret.Username
            password = $cohesitySecret.Password
        } | ConvertTo-Json
        $tokenResp = Invoke-RestMethod -Uri "https://$Cluster/irisservices/api/v1/public/accessTokens" `
            -Method POST -Body $tokenBody -ContentType 'application/json' `
            -SkipCertificateCheck -ErrorAction Stop
        $sessionObj = [PSCustomObject]@{
            ClusterUri  = "https://$Cluster"
            AccessToken = [PSCustomObject]@{ AccessToken = $tokenResp.accessToken }
        }
        [System.Environment]::SetEnvironmentVariable(
            'cohesityUserProfile',
            ($sessionObj | ConvertTo-Json -Compress),
            'Process'
        )

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
