#Get public and private function definition files.
$Public  = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -Exclude '*.Tests.*' -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -Exclude '*.Tests.*' -ErrorAction SilentlyContinue)

#Dot source the files
foreach ($import in @($Public + $Private)) {
    try {
        . $import
    } catch {
        Write-Warning "Failed to import function $($import.fullname): $_"
    }
}
Export-ModuleMember -Function $Public.Basename
