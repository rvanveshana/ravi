param([switch]$ExamplesOnly, [string]$Optimize = "Debug")

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot
zig build "-Doptimize=$Optimize"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (!$ExamplesOnly) {
    zig build test "-Doptimize=$Optimize"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& ./tools/test_examples.ps1
exit $LASTEXITCODE
