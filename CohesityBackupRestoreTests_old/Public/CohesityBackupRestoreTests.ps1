function CohesityBackupRestoreTests {
    <#
    .SYNOPSIS
        Automated restore testing for Cohesity backups (SQL databases and VMware VMs)

    .DESCRIPTION
        This function performs automated restore testing of SQL Server databases and VMware VMs
        backed up to Cohesity. It reads a CSV file containing source and target server information,
        performs SQL and VM restore operations, monitors completion, and reports success/failure
        statistics. Results are uploaded to Box and optionally sent via email.

    .PARAMETER CohesityCluster
        The Cohesity cluster hostname or IP address

    .PARAMETER CohesitySecretID
        Secret Server ID containing Cohesity credentials

    .PARAMETER JobName
        The Cohesity protection job name to restore from

    .PARAMETER DefaultInstance
        Default SQL Server instance name (default: MSSQLSERVER)

    .PARAMETER RestoreSuffix
        Suffix to append to restored database names (default: -restored)

    .PARAMETER StatusCheckIntervalSeconds
        Seconds to wait between restore status checks (default: 6)

    .PARAMETER BoxSecretID
        Secret Server ID for Box authentication (JWT credentials)

    .PARAMETER BoxFolderID
        Box folder ID where test results and sources CSV are stored

    .PARAMETER BoxSourcesFilename
        Filename of sources CSV file in Box folder

    .PARAMETER BoxReportFilename
        Filename for test results report in Box

    .EXAMPLE
        # Using Settings.psd1
        $settings = Import-PowerShellDataFile .\Settings.psd1
        CohesityBackupRestoreTests @settings

    .EXAMPLE
        # Direct parameters
        CohesityBackupRestoreTests -CohesityCluster 'vbkpcoh-fra1' -CohesitySecretID 36408 -JobName 'DB_FRA1' -BoxSecretID 31699 -BoxFolderID '350749748450' -BoxSourcesFilename 'RestoreTestsSources.csv' -BoxReportFilename 'results.csv'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [String]$CohesityCluster,

        [Parameter(Mandatory = $True)]
        [ValidateRange(1, 999999)]
        [Int]$CohesitySecretID,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [String]$JobName,

        [Parameter(Mandatory = $False)]
        [ValidateNotNullOrEmpty()]
        [String]$DefaultInstance = 'MSSQLSERVER',

        [Parameter(Mandatory = $False)]
        [ValidateNotNullOrEmpty()]
        [String]$RestoreSuffix = '-restored',

        [Parameter(Mandatory = $False)]
        [ValidateRange(1, 300)]
        [Int]$StatusCheckIntervalSeconds = 6,

        [Parameter(Mandatory = $True)]
        [Int]$BoxSecretID,

        [Parameter(Mandatory = $True)]
        [String]$BoxFolderID,

        [Parameter(Mandatory = $True)]
        [String]$BoxSourcesFilename,

        [Parameter(Mandatory = $True)]
        [String]$BoxReportFilename,

        [Parameter(Mandatory = $False)]
        [bool]$EmailEnabled = $false,

        [Parameter(Mandatory = $False)]
        [int]$SmtpSecretId,

        [Parameter(Mandatory = $False)]
        [string[]]$EmailTo,

        [Parameter(Mandatory = $False)]
        [string]$EmailFrom,

        [Parameter(Mandatory = $False)]
        [string]$EmailSubject,

        [Parameter(Mandatory = $False)]
        [string]$SmtpServer,

        [Parameter(Mandatory = $False)]
        [int]$SmtpPort,

        [Parameter(Mandatory = $False)]
        [string]$VCenterServer,

        [Parameter(Mandatory = $False)]
        [int]$VCenterSecretId
    )

    # Set PowerShell preferences
    $Script:ErrorActionPreference = 'Stop'
    $Script:InformationPreference = 'Continue'
    $Script:ProgressPreference = 'SilentlyContinue'

    # Error tracking
    $foundError = $false
    $successCount = 0
    $failureCount = 0
    $skippedCount = 0
    $testResults = @()
    $boxConnected = $false
    $sourcesCSVPath = $null
    $jobStartTime = Get-Date

    try {
        Write-Information "========================================="
        Write-Information "Start - Cohesity Backup Restore Tests"
        Write-Information "========================================="

        # ===== BOX CONNECTION =====
        Write-Information ""
        Write-Information "[0/6] Establishing Box Connection..."
        try {
            Write-Information "Checking for Rakuten.IT.Box module"
            if (-not (Get-Module -ListAvailable -Name Rakuten.IT.Box)) {
                throw "Rakuten.IT.Box module not found. Please install the module before running this script."
            }

            Import-Module Rakuten.IT.Box -ErrorAction Stop
            Write-Information "Rakuten.IT.Box module loaded successfully"

            Write-Information "Retrieving Box credentials from Secret Server (ID: $BoxSecretID)"
            $boxSecret = Get-SSSecret -Id $BoxSecretID -As PlainText -ErrorAction Stop

            if ([string]::IsNullOrEmpty($boxSecret.Password)) {
                throw "Box credentials not found or empty in Secret Server ID: $BoxSecretID"
            }

            Write-Information "Connecting to Box with JWT authentication"
            Connect-Box -Json $boxSecret.Password -ErrorAction Stop
            $boxConnected = $true
            Write-Information "Successfully connected to Box"

            Write-Information "Verifying access to target Box folder: $BoxFolderID"
            $boxFolder = Get-BoxFolder -Item $BoxFolderID -ErrorAction Stop
            Write-Information "Target folder confirmed: $($boxFolder.name)"
            Write-Information "Box connection established successfully"
        }
        catch {
            throw "Box connection failed: $($_.Exception.Message). Cannot proceed without Box access."
        }

        # ===== DOWNLOAD SOURCES CSV FROM BOX =====
        Write-Information ""
        Write-Information "[1/6] Downloading Sources CSV from Box..."
        try {
            Write-Information "Searching for file '$BoxSourcesFilename' in Box folder: $BoxFolderID"

            # Get all files in the folder
            $folderItems = Get-BoxFolderItems -Id $BoxFolderID -ErrorAction Stop

            # Find the sources CSV file
            $sourcesFile = $folderItems | Where-Object { $_.type -eq 'file' -and $_.name -eq $BoxSourcesFilename } | Select-Object -First 1

            if (-not $sourcesFile) {
                throw "Sources CSV file '$BoxSourcesFilename' not found in Box folder $BoxFolderID"
            }

            Write-Information "Found file: $($sourcesFile.name) (ID: $($sourcesFile.id))"

            # Download to temporary location
            $sourcesCSVPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$BoxSourcesFilename-$([System.IO.Path]::GetRandomFileName()).csv")
            Write-Information "Downloading to temporary file: $sourcesCSVPath"

            Get-BoxFileContent -Id $sourcesFile.id -OutFile $sourcesCSVPath
            Write-Information "Successfully downloaded sources CSV from Box"

            # Verify file was downloaded and is not empty
            if (-not (Test-Path $sourcesCSVPath)) {
                throw "Downloaded sources CSV file not found at: $sourcesCSVPath"
            }

            $fileSize = (Get-Item $sourcesCSVPath).Length
            if ($fileSize -eq 0) {
                throw "Downloaded sources CSV file is empty"
            }

            Write-Information "File size: $([math]::Round($fileSize / 1KB, 2)) KB"
        }
        catch {
            throw "Failed to download sources CSV from Box: $($_.Exception.Message)"
        }

        # ===== COHESITY CONNECTION =====
        Write-Information ""
        Write-Information "[2/6] Connecting to Cohesity Cluster..."
        $sqlCreds = Connect-RestoreCohesityCluster -Cluster $CohesityCluster -SecretID $CohesitySecretID
        Write-Information "Connected to Cohesity cluster '$CohesityCluster'"

        # Create PSCredential object for SQL Server authentication
        $sqlUsername = "$($sqlCreds.Domain)\$($sqlCreds.Username)"
        $sqlPassword = ConvertTo-SecureString -String $sqlCreds.Password -AsPlainText -Force
        $sqlCredential = New-Object System.Management.Automation.PSCredential ($sqlUsername, $sqlPassword)
        Write-Information "SQL Server credentials prepared for user: $sqlUsername"

        # ===== LOAD TEST SOURCES =====
        Write-Information ""
        Write-Information "[3/6] Loading Restore Test Sources..."
        Write-Information "Loading restore test list from temporary file"
        $restoreTestsList = Get-RestoreTestSources -CSVPath $sourcesCSVPath
        Write-Information "Found '$($restoreTestsList.Count)' entries in CSV"

        # ===== PROCESS RESTORE TESTS =====
        Write-Information ""
        Write-Information "[4/6] Processing SQL Restore Tests..."

        # Initialize server ID cache for performance optimization
        # Prevents redundant lookups when multiple databases share the same server
        $serverIdCache = @{}

        # Process each database restore test
        foreach ($item in $restoreTestsList) {
            $sourceServer = $item.sourceServer
            $sourceDatabase = $item.sourceDatabase
            $targetServer = $item.targetServer
            $testStatus = 'Unknown'
            $errorMessage = ''
            $databaseSizeMB = 'N/A'
            $checkDBStatus = 'N/A'
            $startTime = Get-Date

            # Skip if no target server specified
            if ([string]::IsNullOrWhiteSpace($targetServer)) {
                Write-Information "Skipping '$sourceDatabase' on '$sourceServer' - no target server specified"
                $skippedCount++
                $testStatus = 'Skipped'
                $errorMessage = 'No target server specified'
            }
            else {
                Write-Information "Processing restore test for '$sourceDatabase' from '$sourceServer' to '$targetServer'"

                try {
                    # Invoke the restore operation for this database with server ID caching
                    $result = Invoke-RestoreSingleDatabase `
                        -SourceServer $sourceServer `
                        -SourceDatabase $sourceDatabase `
                        -TargetServer $targetServer `
                        -JobName $JobName `
                        -DefaultInstance $DefaultInstance `
                        -RestoreSuffix $RestoreSuffix `
                        -StatusCheckIntervalSeconds $StatusCheckIntervalSeconds `
                        -SqlCredential $sqlCredential `
                        -ServerIdCache $serverIdCache

                    if ($result.Success) {
                        $successCount++
                        $testStatus = 'Success'

                        # Attempt to retrieve the restored database size
                        try {
                            $targetDatabase = "$sourceDatabase$RestoreSuffix"
                            $databaseSizeMB = Get-RestoredDatabaseSizeMB `
                                -TargetServer $targetServer `
                                -DatabaseName $targetDatabase `
                                -SqlCredential $sqlCredential
                        }
                        catch {
                            Write-Warning "Could not retrieve size for '$sourceDatabase$RestoreSuffix' on '$targetServer': $($_.Exception.Message)"
                        }

                        # Run DBCC CHECKDB integrity check
                        try {
                            $checkDBResult = Invoke-RestoreCheckDB `
                                -TargetServer $targetServer `
                                -DatabaseName "$sourceDatabase$RestoreSuffix" `
                                -SqlCredential $sqlCredential
                            $checkDBStatus = if ($checkDBResult.Passed) { 'Passed' } else { "Failed: $($checkDBResult.Message)" }
                        }
                        catch {
                            $checkDBStatus = "Error: $($_.Exception.Message)"
                            Write-Warning "DBCC CHECKDB error for '$sourceDatabase$RestoreSuffix': $($_.Exception.Message)"
                        }
                    }
                    else {
                        $failureCount++
                        $foundError = $true
                        $testStatus = 'Failed'
                        $errorMessage = $result.Error
                    }
                }
                catch {
                    Write-Warning "Error processing '$sourceDatabase' on '$sourceServer': $($_.Exception.Message)"
                    $failureCount++
                    $foundError = $true
                    $testStatus = 'Failed'
                    $errorMessage = $_.Exception.Message
                }
            }

            # Cleanup: drop the restored database from target server (always attempted if a target was specified)
            if (-not [string]::IsNullOrWhiteSpace($targetServer)) {
                try {
                    Remove-RestoredDatabase `
                        -TargetServer $targetServer `
                        -DatabaseName "$sourceDatabase$RestoreSuffix" `
                        -SqlCredential $sqlCredential
                }
                catch {
                    Write-Warning "Cleanup warning - could not drop '$sourceDatabase$RestoreSuffix' on '$targetServer': $($_.Exception.Message)"
                }
            }

            # Collect result for Box upload
            $endTime = Get-Date
            $duration = [math]::Round(($endTime - $startTime).TotalMinutes, 2)
            $testResults += [PSCustomObject]@{
                RestoreType     = 'SQL'
                SourceServer    = $sourceServer
                SourceDatabase  = $sourceDatabase
                TargetServer    = $targetServer
                Status          = $testStatus
                DurationMinutes = $duration
                DatabaseSizeMB  = $databaseSizeMB
                CheckDBStatus   = $checkDBStatus
                StartTime       = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
                EndTime         = $endTime.ToString('yyyy-MM-dd HH:mm:ss')
                ErrorMessage    = $errorMessage
            }
        }

        # ===== VM RESTORE TESTS =====
        Write-Information ""
        Write-Information "[5/6] Processing VM Restore Tests..."

        $vmSources = $restoreTestsList |
            Select-Object -ExpandProperty sourceServer -Unique |
            Where-Object { $_ }

        Write-Information "Found $($vmSources.Count) unique VM(s) to restore: $($vmSources -join ', ')"

        foreach ($vmName in $vmSources) {
            $vmStartTime = Get-Date

            Write-Information "Processing VM restore for '$vmName'"

            $vmResult = Invoke-VMRestoreTest `
                -VMName $vmName `
                -RestoreSuffix $RestoreSuffix `
                -CheckIntervalSeconds $StatusCheckIntervalSeconds

            $vmEndTime = Get-Date

            if ($vmResult.Success) {
                $successCount++
                $vmStatus = 'Success'

                # Delete restored VM from vCenter
                if ($VCenterServer -and $VCenterSecretId) {
                    $restoredVMName = $vmResult.RestoredVMName
                    Write-Information "Deleting restored VM '$restoredVMName' from vCenter..."
                    $deleteResult = Remove-RestoredVM `
                        -VMName $restoredVMName `
                        -VCenterServer $VCenterServer `
                        -SecretId $VCenterSecretId

                    if (-not $deleteResult.Success) {
                        Write-Warning "Failed to delete restored VM '$restoredVMName': $($deleteResult.Error)"
                        # non-fatal: VM restore still counted as success
                    }
                }
                else {
                    Write-Warning "VCenterServer or VCenterSecretId not configured — restored VM '$($vmResult.RestoredVMName)' left in vCenter."
                }
            }
            else {
                $failureCount++
                $foundError = $true
                $vmStatus = 'Failed'
            }

            $testResults += [PSCustomObject]@{
                RestoreType     = 'VM'
                SourceServer    = $vmName
                SourceDatabase  = '(VM restore)'
                TargetServer    = 'N/A'
                Status          = $vmStatus
                DurationMinutes = [math]::Round(($vmEndTime - $vmStartTime).TotalMinutes, 1)
                DatabaseSizeMB  = 'N/A'
                CheckDBStatus   = 'N/A'
                StartTime       = $vmStartTime.ToString('yyyy-MM-dd HH:mm:ss')
                EndTime         = $vmEndTime.ToString('yyyy-MM-dd HH:mm:ss')
                ErrorMessage    = $vmResult.Error
            }
        }

        # ===== UPLOAD RESULTS TO BOX =====
        Write-Information ""
        Write-Information "[6/6] Uploading Test Results to Box..."
        $csvPath = $null
        try {
            # Validate Box connection before upload (reconnect if needed)
            Write-Information "Validating Box connection"
            try {
                Get-BoxFolder -Item $BoxFolderID -ErrorAction Stop | Out-Null
                Write-Information "Box connection is active"
            }
            catch {
                Write-Warning "Box connection lost, attempting to reconnect..."
                $boxSecret = Get-SSSecret -Id $BoxSecretID -As PlainText -ErrorAction Stop
                Connect-Box -Json $boxSecret.Password -ErrorAction Stop
                Write-Information "Successfully reconnected to Box"
            }

            # Export current run results to temporary CSV (overwrites existing Box file)
            $csvPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$BoxReportFilename-$([System.IO.Path]::GetRandomFileName())")
            $testResults | Export-Csv -Path $csvPath -NoTypeInformation -Force
            Write-Information "Exported $($testResults.Count) row(s) to temporary file"

            # Upload file with overwrite
            Write-Information "Uploading to Box: $BoxReportFilename"
            $uploadResult = Send-BoxFile -Path $csvPath -ParentId $BoxFolderID -Name $BoxReportFilename -Overwrite -ErrorAction Stop
            Write-Information "Upload completed successfully"

            # Extract file ID
            $uploadedFile = $null
            if ($uploadResult.PSObject.Properties['entries'] -and $uploadResult.entries.Count -gt 0) {
                $uploadedFile = $uploadResult.entries[0]
            }
            elseif ($uploadResult.PSObject.Properties['id']) {
                $uploadedFile = $uploadResult
            }

            if ($uploadedFile -and $uploadedFile.id) {
                Write-Information "  File ID: $($uploadedFile.id)"
                Write-Information "  Box URL: https://rak.app.box.com/file/$($uploadedFile.id)"
            }
        }
        catch {
            Write-Warning "Box upload failed: $($_.Exception.Message)"
        }
        finally {
            # Cleanup temporary CSV file
            if ($csvPath -and (Test-Path $csvPath)) {
                Remove-Item $csvPath -Force -ErrorAction SilentlyContinue
                Write-Information "Cleaned up temporary file: $csvPath"
            }
        }

        # ===== EMAIL NOTIFICATION =====
        if ($EmailEnabled -and $null -ne $EmailTo -and $EmailTo.Count -gt 0) {
            Write-Information ""
            Write-Information "Sending email notification..."

            $emailData = @{
                CohesityCluster = $CohesityCluster
                JobName         = $JobName
                TotalCount      = $testResults.Count
                SuccessCount    = $successCount
                FailureCount    = $failureCount
                SkippedCount    = $skippedCount
                TestResults     = $testResults
                StartTime       = $jobStartTime
                EndTime         = Get-Date
            }

            $emailSettings = @{
                SmtpSecretId = $SmtpSecretId
                To           = $EmailTo
            }
            if ($EmailFrom)    { $emailSettings['From']       = $EmailFrom }
            if ($EmailSubject) { $emailSettings['Subject']    = $EmailSubject }
            if ($SmtpServer)   { $emailSettings['SmtpServer'] = $SmtpServer }
            if ($SmtpPort)     { $emailSettings['SmtpPort']   = $SmtpPort }

            Send-RestoreTestNotification -EmailData $emailData -EmailSettings $emailSettings
        }

        # ===== SUMMARY =====
        Write-Information ""
        Write-Information "========================================="
        Write-Information "Restore Tests Summary:"
        Write-Information "  SQL Entries: $($restoreTestsList.Count)"
        Write-Information "  VM Entries:  $($vmSources.Count)"
        Write-Information "  Successful: $successCount"
        Write-Information "  Failed: $failureCount"
        Write-Information "  Skipped: $skippedCount"
        Write-Information "========================================="

        if ($foundError) {
            throw "Restore tests completed with $failureCount failures. Please review logs."
        }
    }
    catch {
        # CITIDAuto integration for error reporting
        Write-Warning "Restore tests encountered errors. Creating CITIDAuto Jira ticket..."

        New-CITIDAutoTicket `
            -Priority 'Critical' `
            -JobName 'CohesityBackupRestoreTests' `
            -Summary "[CohesityBackupRestoreTests] Backup Restore Tests failed" `
            -Description (
@"
Cohesity Backup Restore Tests failed with errors.

Test Results Summary:
- Total Entries: $($restoreTestsList.Count)
- Successful: $successCount
- Failed: $failureCount
- Skipped: $skippedCount

Configuration:
- Cohesity Cluster: $CohesityCluster
- Backup Job: $JobName
- Box Folder ID: $BoxFolderID
- Box Sources File: $BoxSourcesFilename

Error Details:
$_

Please investigate Secret Server credentials and system connectivity:
- Cohesity Secret: $CohesitySecretID
- Box Secret: $BoxSecretID
"@) `
            -Components @('IssueHandler: IOC', 'IssueOwner: Core', 'IssueType: Incident') `
            -CheckIfExists `
            -AdditionalData $testResults `
            -BoxFileName "CohesityBackupRestoreTests-Error-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
            -InformationAction 'Continue'

        throw
    }
    finally {
        # Cleanup temporary sources CSV file
        if ($sourcesCSVPath -and (Test-Path $sourcesCSVPath)) {
            Remove-Item $sourcesCSVPath -Force -ErrorAction SilentlyContinue
            Write-Information "Cleaned up temporary sources CSV file"
        }

        # Disconnect from Box
        if ($boxConnected) {
            try {
                Disconnect-Box
                Write-Information "Disconnected from Box"
            }
            catch {
                Write-Warning "Box disconnect warning: $($_.Exception.Message)"
            }
        }

        # Always disconnect from Cohesity
        Write-Information "Disconnecting from Cohesity cluster"
        try { Disconnect-CohesityCluster -ErrorAction SilentlyContinue } catch { }
        Write-Information "End - Cohesity Backup Restore Tests"
    }
}
