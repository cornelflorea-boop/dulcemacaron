function Send-RestoreTestNotification {
    <#
    .SYNOPSIS
        Sends an HTML email report for Cohesity Backup Restore Tests results

    .DESCRIPTION
        Internal helper function that builds and sends a rich HTML email notification
        summarising the outcome of all restore tests. Includes an overall status banner,
        run summary table, and a detailed per-database results table with size on disk.
        Email design matches the RFRAccounting notification style (Rakuten red header).

    .PARAMETER EmailData
        Hashtable containing job details:
          CohesityCluster  - cluster hostname
          JobName          - Cohesity protection job name
          TotalCount       - total databases processed
          SuccessCount     - number of successful restores
          FailureCount     - number of failed restores
          SkippedCount     - number of skipped entries
          TestResults      - array of PSCustomObject restore results
          StartTime        - [DateTime] job start
          EndTime          - [DateTime] job end

    .PARAMETER EmailSettings
        Hashtable containing email configuration:
          SmtpSecretId  - Secret Server ID for SMTP credentials
          To            - recipient address(es)
          From          - (optional) sender address
          Subject       - (optional) subject line override
          SmtpServer    - (optional) SMTP hostname
          SmtpPort      - (optional) SMTP port

    .EXAMPLE
        Send-RestoreTestNotification -EmailData $data -EmailSettings $settings
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [hashtable]$EmailData,

        [Parameter(Mandatory = $True)]
        [hashtable]$EmailSettings
    )

    try {
        Write-Information "Preparing restore test email notification..."

        # Apply defaults
        $smtpServer = if ($EmailSettings.SmtpServer) { $EmailSettings.SmtpServer } else { 'mail.intra.rakuten.co.jp' }
        $smtpPort   = if ($EmailSettings.SmtpPort)   { $EmailSettings.SmtpPort }   else { 587 }
        $from       = if ($EmailSettings.From)       { $EmailSettings.From }       else { 'sv-exch-bat-smtp@rakuten.com' }

        # Build subject line
        $statusWord = if ($EmailData.FailureCount -gt 0) { 'FAILURES DETECTED' } else { 'All Passed' }
        $subject = if ($EmailSettings.Subject) {
            $EmailSettings.Subject
        } else {
            "[Cohesity Backup Restore Tests] $($EmailData.CohesityCluster) / $($EmailData.JobName) - $statusWord"
        }

        # Retrieve SMTP credentials
        Write-Information "Retrieving SMTP credentials from Secret Server (ID: $($EmailSettings.SmtpSecretId))"
        $smtpSecret    = Get-SSSecret -Id $EmailSettings.SmtpSecretId -As Credential
        $smtpCredential = $smtpSecret.Credential

        # Overall status styling
        if ($EmailData.FailureCount -gt 0) {
            $overallStatus     = if ($EmailData.SuccessCount -gt 0) { "Partial Failure - $($EmailData.FailureCount) restore(s) failed out of $($EmailData.TotalCount)" } else { "Failed - $($EmailData.FailureCount) restore(s) failed" }
            $statusColor       = '#f8d7da'
            $statusBorderColor = '#dc3545'
            $statusTextColor   = '#721c24'
            $statusIcon        = '&#x2717;'
        } else {
            $overallStatus     = "Success - All $($EmailData.SuccessCount) restore(s) completed successfully"
            $statusColor       = '#d4edda'
            $statusBorderColor = '#28a745'
            $statusTextColor   = '#155724'
            $statusIcon        = '&#x2713;'
        }

        $duration = "{0:hh\:mm\:ss}" -f ($EmailData.EndTime - $EmailData.StartTime)

        # Build per-database detail rows
        $detailRows = ''
        foreach ($r in $EmailData.TestResults) {
            $rowBg = switch ($r.Status) {
                'Success' { '#f0fff4' }
                'Failed'  { '#fff5f5' }
                'Skipped' { '#fffbf0' }
                default   { '#ffffff' }
            }
            $statusCell = switch ($r.Status) {
                'Success' { "<span style='color:#155724;font-weight:bold;'>&#x2713;&nbsp;Success</span>" }
                'Failed'  { "<span style='color:#721c24;font-weight:bold;'>&#x2717;&nbsp;Failed</span>" }
                'Skipped' { "<span style='color:#856404;font-weight:bold;'>&#x25BA;&nbsp;Skipped</span>" }
                default   { $r.Status }
            }
            $sizeCell  = if ($r.DatabaseSizeMB -and $r.DatabaseSizeMB -ne 'N/A') { "$($r.DatabaseSizeMB) MB" } else { '<span style="color:#999;">N/A</span>' }
            $errorCell = if ($r.ErrorMessage) { "<span style='color:#dc3545;font-size:11px;'>$($r.ErrorMessage)</span>" } else { '' }

            $checkDBCell = switch -Wildcard ($r.CheckDBStatus) {
                'Passed'   { "<span style='color:#155724;font-weight:bold;'>&#x2713;&nbsp;Passed</span>" }
                'Failed*'  { "<span style='color:#721c24;font-weight:bold;'>&#x2717;&nbsp;$($r.CheckDBStatus)</span>" }
                'Error*'   { "<span style='color:#856404;'>&#x26A0;&nbsp;$($r.CheckDBStatus)</span>" }
                default    { "<span style='color:#999;'>$($r.CheckDBStatus)</span>" }
            }

            $detailRows += @"
                <tr style="background-color: $rowBg;">
                    <td style="white-space:nowrap;">$($r.RestoreType)</td>
                    <td style="font-size:12px;">$($r.SourceServer)</td>
                    <td><strong>$($r.SourceDatabase)</strong></td>
                    <td style="font-size:12px;">$($r.TargetServer)</td>
                    <td>$statusCell</td>
                    <td style="text-align:right;">$($r.DurationMinutes) min</td>
                    <td style="text-align:right;">$sizeCell</td>
                    <td>$checkDBCell</td>
                    <td style="font-size:11px;white-space:nowrap;">$($r.StartTime)</td>
                    <td style="font-size:11px;white-space:nowrap;">$($r.EndTime)</td>
                    <td style="font-size:11px;">$errorCell</td>
                </tr>
"@
        }

        # Build full HTML email body
        $emailBody = @"
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 0; }
        .container { max-width: 1100px; margin: 20px auto; }
        .header { background-color: #bf0000; color: white; padding: 20px 24px; }
        .header h2 { margin: 0 0 6px 0; font-size: 20px; }
        .header p  { margin: 0; font-size: 13px; opacity: 0.9; }
        .body-wrap { padding: 10px 24px 24px 24px; }
        .status-box { background-color: $statusColor; color: $statusTextColor; padding: 14px 18px;
                      border-left: 4px solid $statusBorderColor; margin: 20px 0; font-size: 15px; }
        .info-table  { width: 100%; border-collapse: collapse; margin: 16px 0; }
        .info-table th { background-color: #f8f9fa; text-align: left; padding: 10px 14px;
                         border: 1px solid #dee2e6; font-weight: bold; }
        .info-table td { padding: 10px 14px; border: 1px solid #dee2e6; vertical-align: top; }
        .detail-table { width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 13px; }
        .detail-table th { background-color: #343a40; color: white; text-align: left; padding: 10px 12px;
                           border: 1px solid #495057; white-space: nowrap; }
        .detail-table td { padding: 8px 12px; border: 1px solid #dee2e6; vertical-align: top; }
        .footer { padding: 12px 0 0 0; font-size: 12px; color: #666; margin-top: 20px;
                  border-top: 1px solid #dee2e6; }
        h3 { color: #333; margin-top: 24px; margin-bottom: 6px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>Cohesity Backup Restore Tests &mdash; Report</h2>
            <p>Automated Restore Verification &bull; Cluster: $($EmailData.CohesityCluster)</p>
        </div>

        <div class="body-wrap">
            <div class="status-box">
                <strong>$statusIcon &nbsp;$overallStatus</strong>
            </div>

            <h3>Run Summary</h3>
            <table class="info-table">
                <tr>
                    <th style="width: 30%;">Parameter</th>
                    <th>Value</th>
                </tr>
                <tr>
                    <td><strong>Cohesity Cluster</strong></td>
                    <td>$($EmailData.CohesityCluster)</td>
                </tr>
                <tr>
                    <td><strong>Backup Job</strong></td>
                    <td>$($EmailData.JobName)</td>
                </tr>
                <tr>
                    <td><strong>Total Entries Processed</strong></td>
                    <td><strong>$($EmailData.TotalCount)</strong></td>
                </tr>
                <tr>
                    <td><strong>Successful Restores</strong></td>
                    <td style="color: #28a745; font-weight: bold;">$($EmailData.SuccessCount)</td>
                </tr>
                <tr>
                    <td><strong>Failed Restores</strong></td>
                    <td style="color: $(if ($EmailData.FailureCount -gt 0) { '#dc3545' } else { '#28a745' }); font-weight: bold;">$($EmailData.FailureCount)</td>
                </tr>
                <tr>
                    <td><strong>Skipped</strong></td>
                    <td style="color: #856404; font-weight: bold;">$($EmailData.SkippedCount)</td>
                </tr>
                <tr>
                    <td><strong>Run Started</strong></td>
                    <td>$($EmailData.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))</td>
                </tr>
                <tr>
                    <td><strong>Run Completed</strong></td>
                    <td>$($EmailData.EndTime.ToString('yyyy-MM-dd HH:mm:ss'))</td>
                </tr>
                <tr>
                    <td><strong>Total Duration</strong></td>
                    <td>$duration</td>
                </tr>
            </table>

            <h3>Restore Details ($($EmailData.TotalCount) entries)</h3>
            <table class="detail-table">
                <tr>
                    <th>Type</th>
                    <th>Source Server</th>
                    <th>Database</th>
                    <th>Target Server</th>
                    <th>Status</th>
                    <th style="text-align:right;">Duration</th>
                    <th style="text-align:right;">Size on Disk</th>
                    <th>DBCC CheckDB</th>
                    <th>Start Time</th>
                    <th>End Time</th>
                    <th>Error</th>
                </tr>
$detailRows
            </table>
        </div>

        <div class="footer" style="padding: 12px 24px 24px 24px;">
            <p><strong>Cohesity Backup Restore Tests &mdash; Automated Verification System</strong></p>
            <p>This is an automated notification. For issues or questions, contact the infrastructure team.</p>
            <p style="color: #999; font-size: 11px;">Report generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') (JST) &bull; $([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), 'W. Europe Standard Time').ToString('yyyy-MM-dd HH:mm:ss')) (CET)</p>
        </div>
    </div>
</body>
</html>
"@

        # Send email
        Write-Information "Sending email notification to: $($EmailSettings.To -join ', ')"
        $mailParams = @{
            From       = $from
            To         = $EmailSettings.To
            Subject    = $subject
            Body       = $emailBody
            BodyAsHtml = $true
            SmtpServer = $smtpServer
            Port       = $smtpPort
            UseSsl     = $true
            Credential = $smtpCredential
            Encoding   = [System.Text.Encoding]::UTF8
            Retry      = 3
        }

        Send-BetterMailMessage @mailParams
        Write-Information "Email notification sent successfully"
    }
    catch {
        # Don't fail the entire job if email fails
        Write-Warning "Failed to send email notification: $($_.Exception.Message)"
        Write-Warning "Restore tests completed but email notification failed"
    }
}
