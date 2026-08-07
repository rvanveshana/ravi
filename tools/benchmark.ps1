param(
    [int]$Iterations = 30,
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
if ($Iterations -lt 10) { throw "Iterations must be at least 10 for stable percentile estimates." }
if ($MaxRegressionPct -lt 0) { throw "MaxRegressionPct must be non-negative." }
if ($Baseline -ne "" -and -not (Test-Path -LiteralPath $Baseline)) { throw "Baseline report not found: $Baseline" }

function Get-Percentile([double[]]$Values, [double]$Percentile) {
    if ($Values.Count -eq 0) { throw "Cannot calculate a percentile from no samples." }
    if ($Percentile -lt 0 -or $Percentile -gt 1) { throw "Percentile must be between 0 and 1." }
    $rank = ($Values.Count - 1) * $Percentile
    $lower = [Math]::Floor($rank)
    $upper = [Math]::Ceiling($rank)
    if ($lower -eq $upper) { return [double]$Values[$lower] }
    $fraction = $rank - $lower
    return [double]$Values[$lower] + ([double]$Values[$upper] - [double]$Values[$lower]) * $fraction
}

zig build -Doptimize=ReleaseFast
if ($LASTEXITCODE -ne 0) { throw "ReleaseFast build failed." }

$isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$ravi = if ($isWindowsHost) { ".\zig-out\bin\ravi.exe" } else { "./zig-out/bin/ravi" }
$zigVersion = (& zig version).Trim()
$platform = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
$binaryPath = (Resolve-Path -LiteralPath $ravi).Path
$binaryBytes = (Get-Item -LiteralPath $binaryPath).Length
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
    $median = Get-Percentile $ordered 0.50
    $p95 = Get-Percentile $ordered 0.95
    $mean = ($samples | Measure-Object -Average).Average
    $variance = (($samples | ForEach-Object { ($_ - $mean) * ($_ - $mean) } | Measure-Object -Sum).Sum) / $samples.Count
    $results += [pscustomobject]@{
        program = $program
        iterations = $Iterations
        median_ms = [Math]::Round($median, 3)
        p95_ms = [Math]::Round($p95, 3)
        stddev_ms = [Math]::Round([Math]::Sqrt($variance), 3)
        min_ms = [Math]::Round($ordered[0], 3)
        max_ms = [Math]::Round($ordered[-1], 3)
        peak_memory_bytes = $null
        gc_pause_p95_ms = $null
    }
}

$report = [pscustomobject]@{
    schema = "ravi-benchmark-v1"
    generated_utc = [DateTime]::UtcNow.ToString("o")
    optimize = "ReleaseFast"
    max_median_regression_pct = $MaxRegressionPct
    max_p95_regression_pct = $MaxRegressionPct
    zig_version = $zigVersion
    platform = $platform
    architecture = $architecture
    warmup_iterations = 1
    iterations = $Iterations
    binary_bytes = $binaryBytes
    phase_metrics = [pscustomobject]@{
        lexer_ms = $null
        parser_ms = $null
        semantic_ms = $null
        compiler_ms = $null
        verifier_ms = $null
        vm_ms = $null
        calls_ms = $null
        closures_ms = $null
        collections_ms = $null
        strings_ms = $null
        exceptions_ms = $null
        allocation_gc_ms = $null
        modules_ms = $null
        scheduler_ms = $null
        startup_ms = $null
    }
    results = $results
}
$regressions = @()
if ($Baseline -ne "") {
    $baselineReport = Get-Content -LiteralPath $Baseline -Raw | ConvertFrom-Json
    foreach ($result in $results) {
        $prior = @($baselineReport.results | Where-Object { $_.program -eq $result.program }) | Select-Object -First 1
        if ($null -eq $prior -or [double]$prior.median_ms -le 0) { continue }
        $change = (($result.median_ms - [double]$prior.median_ms) / [double]$prior.median_ms) * 100.0
        $priorP95 = if ($null -ne $prior.p95_ms) { [double]$prior.p95_ms } else { 0.0 }
        $p95Change = if ($priorP95 -gt 0) { (($result.p95_ms - $priorP95) / $priorP95) * 100.0 } else { 0.0 }
        if ($change -gt $MaxRegressionPct -or $p95Change -gt $MaxRegressionPct) {
            $regressions += [pscustomobject]@{
                program = $result.program
                baseline_median_ms = $prior.median_ms
                current_median_ms = $result.median_ms
                median_change_pct = [Math]::Round($change, 2)
                baseline_p95_ms = $priorP95
                current_p95_ms = $result.p95_ms
                p95_change_pct = [Math]::Round($p95Change, 2)
            }
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
