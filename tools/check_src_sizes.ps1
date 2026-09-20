param([ValidateRange(1, 10000)][int]$MaxLines = 300)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$files = @(Get-ChildItem -LiteralPath (Join-Path $workspace 'src'), (Join-Path $workspace 'tests'), (Join-Path $workspace 'build'), (Join-Path $workspace 'config'), (Join-Path $workspace 'tools') -Recurse -File |
    Where-Object { $_.Extension -in '.zig', '.ps1' })
$files += Get-Item -LiteralPath (Join-Path $workspace 'build.zig'), (Join-Path $workspace 'test.ps1')
$oversized = @($files | ForEach-Object {
    $lines = (Get-Content -LiteralPath $_.FullName).Count
    if ($lines -gt $MaxLines) {
        [pscustomobject]@{
            File = [IO.Path]::GetRelativePath($workspace, $_.FullName)
            Lines = $lines
            Limit = $MaxLines
        }
    }
})
if ($oversized.Count -gt 0) {
    $oversized | Sort-Object Lines -Descending | Format-Table -AutoSize
    exit 1
}
Write-Output "All maintained source, test, build, and script files satisfy the $MaxLines-line budget."
