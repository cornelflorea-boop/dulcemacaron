@{
    # Cohesity Cluster
    CohesityCluster = 'vbkpcoh-fra1'
    CohesitySecretID = 36408  # Server Admin account for Cohesity

    # Backup Job Configuration
    JobName = 'DB_FRA1'

    # SQL Server Configuration
    DefaultInstance = 'MSSQLSERVER'
    RestoreSuffix = '-restored'

    # Box Configuration
    BoxSecretID = 31699  # Box JWT authentication credentials
    BoxFolderID = '350749748450'  # Target Box folder for test results and sources CSV
    BoxSourcesFilename = 'RestoreTestsSources.csv'  # Sources CSV file in Box folder
    BoxReportFilename = 'Cohesity-SQL-Restore-Tests-Results.csv'

    # vCenter Configuration
    VCenterServer   = 'vcenter-fra001'
    VCenterSecretId = 8236  # vCenter credentials for deleting restored VMs

    # Monitoring
    StatusCheckIntervalSeconds = 6

    # Email Notification Settings
    EmailEnabled = $true
    SmtpSecretId = 36655  # SMTP authentication credentials
    EmailTo      = @('citd-eu-svr@mail.rakuten.com')
    EmailFrom    = 'sv-exch-bat-smtp@rakuten.com'
    SmtpServer   = 'mail.intra.rakuten.co.jp'
    SmtpPort     = 587
}
