param([int]$MaxLines = 300)

$oversized = Get-ChildItem -Path src -Recurse -Filter *.zig | ForEach-Object {
    $lines = (Get-Content -LiteralPath $_.FullName).Count
    if ($lines -gt $MaxLines) {
        [pscustomobject]@{ File = $_.FullName; Lines = $lines }
    }
}

if ($oversized) {
    $oversized | Sort-Object Lines -Descending | Format-Table -AutoSize
    exit 1
}
Write-Output "All src Zig modules are at or below $MaxLines lines."
