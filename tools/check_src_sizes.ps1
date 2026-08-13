param([int]$MaxLines = 300)

$temporaryBudgets = @{
    "src/compiler/compiler.zig" = 1050
    "src/vm/vm.zig" = 800
    "src/bytecode/bytecode.zig" = 350
    "src/lsp/jsonrpc.zig" = 500
    "src/concurrency/scheduler.zig" = 350
}

$oversized = Get-ChildItem -Path src -Recurse -Filter *.zig | ForEach-Object {
    $lines = (Get-Content -LiteralPath $_.FullName).Count
    $relative = [System.IO.Path]::GetRelativePath((Get-Location).Path, $_.FullName).Replace('\', '/')
    $limit = if ($temporaryBudgets.ContainsKey($relative)) { $temporaryBudgets[$relative] } else { $MaxLines }
    if ($lines -gt $limit) {
        [pscustomobject]@{ File = $relative; Lines = $lines; Limit = $limit }
    }
}

if ($oversized) {
    $oversized | Sort-Object Lines -Descending | Format-Table -AutoSize
    exit 1
}
Write-Output "All source modules satisfy their line-count budgets."
