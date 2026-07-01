function Invoke-CohesityRestApi {
    <#
    .SYNOPSIS
        Sends a REST request to the connected Cohesity cluster with SSL bypass

    .DESCRIPTION
        Drop-in replacement for the Cohesity module's internal Invoke-RestApi, which is not
        exported and therefore inaccessible from outside the Cohesity module scope.
        Reads the session from the cohesityUserProfile process env var written by
        Connect-RestoreCohesityCluster, constructs the full URI, and calls
        Invoke-WebRequest -SkipCertificateCheck (required for self-signed Cohesity certs on PS7).
        Sets $Global:CohesityAPIStatus for callers that check StatusCode after POST calls.

    .PARAMETER Method
        HTTP method: Get, Post, Put, Delete

    .PARAMETER Uri
        Relative URI path, e.g. '/irisservices/api/v1/searchvms?...'

    .PARAMETER Body
        Optional JSON string body for POST/PUT requests

    .OUTPUTS
        Deserialized response object (ConvertFrom-Json), or $null for empty responses

    .EXAMPLE
        $result = Invoke-CohesityRestApi -Method Get -Uri '/irisservices/api/v1/searchvms?environment=SQL'

    .EXAMPLE
        $resp = Invoke-CohesityRestApi -Method Post -Uri '/irisservices/api/v1/recoverApplication' -Body ($payload | ConvertTo-Json -Depth 20)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [ValidateSet('Get', 'Post', 'Put', 'Delete')]
        [string]$Method,

        [Parameter(Mandatory = $True)]
        [string]$Uri,

        [Parameter(Mandatory = $False)]
        [string]$Body
    )

    $sessionJson = [System.Environment]::GetEnvironmentVariable('cohesityUserProfile', 'Process')
    if (-not $sessionJson) {
        throw 'Not connected to Cohesity cluster (cohesityUserProfile env var not set). Call Connect-RestoreCohesityCluster first.'
    }

    $session  = $sessionJson | ConvertFrom-Json
    $token    = $session.AccessToken.AccessToken
    $fullUri  = $session.ClusterUri + $Uri
    $headers  = @{ 'Authorization' = "Bearer $token" }

    $Global:CohesityAPIStatus = $null

    $iwrParams = @{
        Uri                  = $fullUri
        Method               = $Method
        Headers              = $headers
        UseBasicParsing      = $true
        SkipCertificateCheck = $true
        SslProtocol          = 'Tls12'
        ContentType          = 'application/json'
        ErrorAction          = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $iwrParams.Body = $Body
    }

    try {
        $result = Invoke-WebRequest @iwrParams
        $Global:CohesityAPIStatus = [PSCustomObject]@{
            StatusCode   = [int]$result.StatusCode
            ErrorMessage = $null
        }
        if ($result.Content) {
            return $result.Content | ConvertFrom-Json
        }
        return $null
    }
    catch {
        $statusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        # Read the response body — it contains Cohesity's error detail (errorCode + message)
        $responseBody = $null
        if ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                $responseBody = $stream
            } catch { }
        }
        $errorMessage = if ($responseBody) { "$($_.Exception.Message) | Body: $responseBody" } else { $_.Exception.Message }
        $Global:CohesityAPIStatus = [PSCustomObject]@{
            StatusCode   = $statusCode
            ErrorMessage = $errorMessage
        }
        throw [System.Exception]::new($errorMessage, $_.Exception)
    }
}
