function Get-RestoreTestSources {
    <#
    .SYNOPSIS
        Loads and validates restore test sources from CSV file

    .DESCRIPTION
        Reads a CSV file containing database restore test definitions. Validates the file
        exists, is not empty, and contains all required columns (sourceServer, sourceDatabase, targetServer).
        Trims whitespace from entries and validates required fields are not empty.

    .PARAMETER CSVPath
        Full path to the CSV file containing restore test definitions

    .OUTPUTS
        System.Array
        Returns array of PSCustomObjects with sourceServer, sourceDatabase, targetServer properties

    .EXAMPLE
        $tests = Get-RestoreTestSources -CSVPath '\\server\share\tests.csv'

    .NOTES
        Required CSV columns: sourceServer, sourceDatabase, targetServer
        targetServer can be empty to skip the restore test
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [String]$CSVPath
    )

    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path $CSVPath)) {
        throw "CSV file not found: $CSVPath"
    }

    Write-Information "Reading CSV file from '$CSVPath'"
    $data = Import-Csv -LiteralPath $CSVPath

    if ($data.Count -eq 0) {
        throw "CSV file is empty: $CSVPath"
    }

    # Validate required columns
    $requiredColumns = @('sourceServer', 'sourceDatabase', 'targetServer')
    $firstRow = $data | Select-Object -First 1
    $missingColumns = $requiredColumns | Where-Object { -not $firstRow.PSObject.Properties.Name.Contains($_) }

    if ($missingColumns) {
        throw "CSV file is missing required columns: $($missingColumns -join ', ')"
    }

    # Trim whitespace and validate entries
    $rowNumber = 1
    foreach ($row in $data) {
        $rowNumber++

        # Trim whitespace from all fields
        if ($row.sourceServer) {
            $row.sourceServer = $row.sourceServer.Trim()
        }
        if ($row.sourceDatabase) {
            $row.sourceDatabase = $row.sourceDatabase.Trim()
        }
        if ($row.targetServer) {
            $row.targetServer = $row.targetServer.Trim()
        }

        # Validate required fields are not empty
        if ([string]::IsNullOrWhiteSpace($row.sourceServer)) {
            throw "CSV row $rowNumber has empty sourceServer"
        }
        if ([string]::IsNullOrWhiteSpace($row.sourceDatabase)) {
            throw "CSV row $rowNumber has empty sourceDatabase"
        }
    }

    Write-Information "Successfully loaded and validated $($data.Count) entries from CSV"
    return $data
}
