param(
    [int]$Iterations = 10,
    [string]$Output = "",
    [string]$Baseline = "",
    [double]$MaxRegressionPct = 10.0,
    [string[]]$Programs = @(
        "examples/arithmetic.rk",
        "examples/functions.rk",
        "examples/closures.rk",
        "examples/collections.rk",
        "examples/collections_advanced.rk",
        "examples/strings.rk",
        "examples/gradual_typing.rk",
        "bench_3.rk",
        "typed_loop.rk",
        "dynamic_loop.rk"
    )
)

$ErrorActionPreference = "Stop"
if ($Iterations -lt 1) { throw "Iterations must be positive." }
if ($MaxRegressionPct -lt 0) { throw "MaxRegressionPct must be non-negative." }
if ($Baseline -ne "" -and -not (Test-Path -LiteralPath $Baseline)) { throw "Baseline report not found: $Baseline" }

zig build -Doptimize=ReleaseFast
if ($LASTEXITCODE -ne 0) { throw "ReleaseFast build failed." }

$isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$ravi = if ($isWindowsHost) { ".\zig-out\bin\ravi.exe" } else { "./zig-out/bin/ravi" }
$results = @()

foreach ($program in $Programs) {
    if (-not (Test-Path -LiteralPath $program)) { continue }
    $samples = @()
    for ($iteration = 0; $iteration -lt $Iterations + 1; $iteration++) {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        # Ravi intentionally writes program output through stderr (Zig's
        # debug printer). Redirect both streams explicitly; PowerShell's
        # combined `*>` turns ordinary program output into terminating native
        # errors when `$ErrorActionPreference` is Stop.
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & $ravi run $program 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorAction
        $timer.Stop()
        if ($exitCode -ne 0) { throw "Benchmark failed: $program (exit $exitCode)" }
        if ($iteration -gt 0) { $samples += $timer.Elapsed.TotalMilliseconds }
    }
    $ordered = @($samples | Sort-Object)
    $median = $ordered[[Math]::Floor(($ordered.Count - 1) * 0.50)]
    $p95 = $ordered[[Math]::Floor(($ordered.Count - 1) * 0.95)]
    $results += [pscustomobject]@{
        program = $program
        iterations = $Iterations
        median_ms = [Math]::Round($median, 3)
        p95_ms = [Math]::Round($p95, 3)
        min_ms = [Math]::Round($ordered[0], 3)
        max_ms = [Math]::Round($ordered[-1], 3)
    }
}

$report = [pscustomobject]@{
    schema = "ravi-benchmark-v1"
    generated_utc = [DateTime]::UtcNow.ToString("o")
    optimize = "ReleaseFast"
    iterations = $Iterations
    results = $results
}
$regressions = @()
if ($Baseline -ne "") {
    $baselineReport = Get-Content -LiteralPath $Baseline -Raw | ConvertFrom-Json
    foreach ($result in $results) {
        $prior = @($baselineReport.results | Where-Object { $_.program -eq $result.program }) | Select-Object -First 1
        if ($null -eq $prior -or [double]$prior.median_ms -le 0) { continue }
        $change = (($result.median_ms - [double]$prior.median_ms) / [double]$prior.median_ms) * 100.0
        if ($change -gt $MaxRegressionPct) {
            $regressions += [pscustomobject]@{ program = $result.program; baseline_median_ms = $prior.median_ms; current_median_ms = $result.median_ms; change_pct = [Math]::Round($change, 2) }
        }
    }
    $report | Add-Member -NotePropertyName regressions -NotePropertyValue $regressions
}
$json = $report | ConvertTo-Json -Depth 5
if ($Output -ne "") {
    $parent = Split-Path -Parent $Output
    if ($parent -ne "" -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Set-Content -LiteralPath $Output -Value $json -Encoding utf8
}
$json
if ($regressions.Count -gt 0) { throw "Benchmark regression exceeds $MaxRegressionPct%: $($regressions.program -join ', ')" }
