$ModuleRoot = $PSScriptRoot

$Private = Get-ChildItem -Path "$ModuleRoot\Private\*.ps1" -Exclude '*.Tests.*' -ErrorAction SilentlyContinue
$Public  = Get-ChildItem -Path "$ModuleRoot\Public\*.ps1"  -Exclude '*.Tests.*' -ErrorAction SilentlyContinue

foreach ($import in @($Private + $Public)) {
    try {
        . $import.FullName
    }
    catch {
        Write-Error "Failed to import function $($import.FullName): $_"
    }
}

Export-ModuleMember -Function $Public.Basename
