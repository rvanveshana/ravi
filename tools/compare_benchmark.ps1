param(
    [Parameter(Mandatory = $true)][string]$Baseline,
    [Parameter(Mandatory = $true)][string]$Current,
    [double]$MaxRegressionPct = 10.0,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
if ($MaxRegressionPct -lt 0) { throw "MaxRegressionPct must be non-negative." }
foreach ($path in @($Baseline, $Current)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Benchmark report not found: $path" }
}

$before = Get-Content -LiteralPath $Baseline -Raw | ConvertFrom-Json
$after = Get-Content -LiteralPath $Current -Raw | ConvertFrom-Json
$rows = @()
foreach ($result in @($after.results)) {
    $prior = @($before.results | Where-Object { $_.program -eq $result.program }) | Select-Object -First 1
    if ($null -eq $prior -or [double]$prior.median_ms -le 0) { continue }
    $change = (($result.median_ms - [double]$prior.median_ms) / [double]$prior.median_ms) * 100.0
    $rows += [pscustomobject]@{
        program = $result.program
        baseline_median_ms = [double]$prior.median_ms
        current_median_ms = [double]$result.median_ms
        change_pct = [Math]::Round($change, 2)
        regression = ($change -gt $MaxRegressionPct)
    }
}

$report = [pscustomobject]@{
    schema = "ravi-benchmark-comparison-v1"
    baseline = $Baseline
    current = $Current
    max_regression_pct = $MaxRegressionPct
    results = $rows
    regressions = @($rows | Where-Object regression)
}
if ($Json) { $report | ConvertTo-Json -Depth 6 } else { $rows | Format-Table -AutoSize }
if (@($report.regressions).Count -gt 0) { exit 2 }
