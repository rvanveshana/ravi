param([string]$Executable = 'zig-out/bin/ravi')

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
if ($IsWindows -and !$Executable.EndsWith('.exe')) { $Executable += '.exe' }
$binary = (Resolve-Path -LiteralPath (Join-Path $workspace $Executable)).Path
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixtureRoot = Join-Path $tempRoot ('ravi-cli-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $fixtureRoot)
$passed = 0

function Write-Fixture([string]$Name, [string]$Source) {
    $target = Join-Path $fixtureRoot $Name
    [IO.File]::WriteAllText($target, $Source, [Text.UTF8Encoding]::new($false))
    return $target
}

function Invoke-Ravi([string[]]$Arguments) {
    $process = [Diagnostics.Process]::new()
    $process.StartInfo.FileName = $binary
    $process.StartInfo.WorkingDirectory = $workspace
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $process.StartInfo.ArgumentList.Add($argument) }
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(10000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw 'CLI regression timed out'
        }
        return @{ Code = $process.ExitCode; Output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult() }
    } finally { $process.Dispose() }
}

function Assert-Result($Result, [int]$Code, [string]$Contains, [string]$Name) {
    if ($Result.Code -ne $Code -or !$Result.Output.Contains($Contains)) {
        throw "$Name failed (exit $($Result.Code)): $($Result.Output)"
    }
    $script:passed++
}

try {
    $english = Write-Fixture 'english.rk' "function square(x: int):`n    return x * x`nprint(square(6))`n"
    foreach ($mode in @('check', 'run', 'trace', 'bytecode')) {
        $result = Invoke-Ravi @($mode, '--lang', 'en', $english)
        Assert-Result $result 0 $(if ($mode -eq 'check') { 'valid Ravi module' } elseif ($mode -eq 'bytecode') { 'call_value' } else { '36' }) "English override / $mode"
    }
    $unknown = Write-Fixture 'unknown.rk' "# ravi: language=en`nprint(missing)`n"
    $missing = Write-Fixture 'missing.rk' "absent inda x tago`nmudrisu(36)`n"
    foreach ($mode in @('check', 'run', 'trace', 'bytecode')) {
        Assert-Result (Invoke-Ravi @($mode, $unknown)) 1 'InvalidName' "Unresolved name / $mode"
        Assert-Result (Invoke-Ravi @($mode, $missing)) 1 'FileNotFound' "Missing dependency / $mode"
    }
    $overflow = Write-Fixture 'overflow.rk' "# ravi: language=en`nprint(140737488355328 - 1)`n"
    foreach ($mode in @('run', 'trace')) {
        Assert-Result (Invoke-Ravi @($mode, $overflow)) 1 'OverflowError' "Integer boundary / $mode"
    }
    $literal = Write-Fixture 'literal.rk' "# ravi: language=en`nx = `"`"`"first  `r`n`tsecond`t `r`n`"`"`"`nprint(x)`n"
    $before = Invoke-Ravi @('run', $literal)
    Assert-Result (Invoke-Ravi @('fmt', $literal)) 0 '' 'Literal formatting'
    $after = Invoke-Ravi @('run', $literal)
    if ($before.Code -ne 0 -or $after.Code -ne 0 -or $before.Output -cne $after.Output) { throw 'Formatting changed literal output' }
    $passed++
    Assert-Result (Invoke-Ravi @('fmt-check', $literal)) 0 '' 'Formatter idempotence'
    [void](Write-Fixture 'math.rk' "# ravi: language=en`nfunction fail():`n    return 1 / 0`n")
    $importer = Write-Fixture 'importer.rk' "math inda fail tago`nfail()`n"
    foreach ($mode in @('run', 'trace')) {
        Assert-Result (Invoke-Ravi @($mode, $importer)) 1 'math.rk:3:' "Imported fault source / $mode"
    }
    [void](Write-Fixture 'math.rk' "# ravi: language=en`nfunction bad(:`n    return 1`n")
    $brokenDependency = Invoke-Ravi @('check', $importer)
    Assert-Result $brokenDependency 1 'math.rk:2:' 'Imported parser diagnostic'
    if (!$brokenDependency.Output.Contains('function bad(')) { throw 'Imported parser diagnostic used the wrong source text' }
    $passed++
    $libraryErrors = @(
        @{ Name = 'abs-boundary'; Import = 'ravi.math'; Call = 'abs(0 - 140737488355327 - 1)'; Error = 'OverflowError' },
        @{ Name = 'gcd-boundary'; Import = 'ravi.math'; Call = 'gcd(0 - 140737488355327 - 1, 1)'; Error = 'OverflowError' },
        @{ Name = 'gcd-type'; Import = 'ravi.math'; Call = 'gcd(1.5, 2)'; Error = 'TypeMismatch' },
        @{ Name = 'clamp-bounds'; Import = 'ravi.math'; Call = 'clamp(5, 10, 0)'; Error = 'lower bound exceeds upper bound' },
        @{ Name = 'sum-overflow'; Import = 'ravi.collections'; Call = 'sum([140737488355327, 1])'; Error = 'OverflowError' },
        @{ Name = 'sum-type'; Import = 'ravi.collections'; Call = 'sum([1, [2]])'; Error = 'TypeError' }
    )
    foreach ($case in $libraryErrors) {
        $functionName = $case.Call.Split('(')[0]
        $fixture = Write-Fixture ($case.Name + '.rk') "# ravi: language=en`n$($case.Import) from $functionName import`n$($case.Call)`n"
        Assert-Result (Invoke-Ravi @('run', $fixture)) 1 $case.Error $case.Name
    }
    Write-Output "CLI regressions: $passed passed"
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    if (!$resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or !(Split-Path -Leaf $resolvedFixture).StartsWith('ravi-cli-')) {
        throw 'Invalid fixture cleanup path'
    }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
