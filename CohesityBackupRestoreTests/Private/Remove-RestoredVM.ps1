function Remove-RestoredVM {
    <#
    .SYNOPSIS
        Deletes a restored VMware VM from vCenter, including its datastore files

    .DESCRIPTION
        Connects to vCenter using credentials from Secret Server, deletes the specified VM
        permanently (including datastore files), then disconnects. Returns a result object
        indicating success or failure.

    .PARAMETER VMName
        The exact name of the VM to delete from vCenter

    .PARAMETER VCenterServer
        The vCenter hostname or IP address

    .PARAMETER SecretId
        Secret Server ID containing vCenter credentials (Domain, Username, Password)

    .OUTPUTS
        PSCustomObject with Success (bool) and Error (string or null)

    .EXAMPLE
        Remove-RestoredVM -VMName 'sqlsrv01-restored' -VCenterServer 'vcenter-fra001' -SecretId 8235
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]  [string]$VMName,
        [Parameter(Mandatory = $true)]  [string]$VCenterServer,
        [Parameter(Mandatory = $true)]  [int]$SecretId
    )

    $vcSecret = Get-SSSecret -SecretId $SecretId -As PlainText -ErrorAction Stop
    $vcSecure = New-Object System.Security.SecureString
    foreach ($char in $vcSecret.Password.ToCharArray()) { $vcSecure.AppendChar($char) }
    $vcUser = if ($vcSecret.Domain) { "$($vcSecret.Domain)\$($vcSecret.Username)" } else { $vcSecret.Username }
    $vcCred = New-Object System.Management.Automation.PSCredential($vcUser, $vcSecure)

    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null
    Connect-VIServer -Server $VCenterServer -Credential $vcCred -ErrorAction Stop

    try {
        $vm = Get-VM -Name $VMName -ErrorAction Stop
        Remove-VM -VM $vm -DeletePermanently -Confirm:$false -ErrorAction Stop
        Write-Information "Restored VM '$VMName' deleted from vCenter."
        return [PSCustomObject]@{ Success = $true; Error = $null }
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Error = $_.Exception.Message }
    }
    finally {
        Disconnect-VIServer -Server $VCenterServer -Confirm:$false -ErrorAction SilentlyContinue
    }
}
