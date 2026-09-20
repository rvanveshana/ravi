param(
    [string]$Executable = "zig-out/bin/ravi",
    [string]$Path = "examples",
    [ValidateRange(1, 300)][int]$TimeoutSeconds = 10
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and !$Executable.EndsWith('.exe')) {
    $Executable += '.exe'
}
$binary = (Resolve-Path -LiteralPath (Join-Path $root $Executable)).Path
$examplePath = Join-Path $root $Path
$files = @(Get-ChildItem -LiteralPath $examplePath -Recurse -File -Filter '*.rk' | Sort-Object FullName)
if ($files.Count -eq 0) { throw "No examples found in $Path" }
$passed = 0
$failed = 0
foreach ($file in $files) {
    $name = [IO.Path]::GetRelativePath($root, $file.FullName)
    $snapshot = [IO.Path]::ChangeExtension($file.FullName, '.out')
    if (!(Test-Path -LiteralPath $snapshot)) {
        Write-Output "FAIL $name (missing expected-output file)"
        $failed++
        continue
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo.FileName = $binary
    $process.StartInfo.WorkingDirectory = $root
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
    $process.StartInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process.StartInfo.ArgumentList.Add('run')
    $process.StartInfo.ArgumentList.Add($file.FullName)
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            Write-Output "FAIL $name (timeout after $TimeoutSeconds seconds)"
            $failed++
            continue
        }
        $output = ($stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()).Replace("`r`n", "`n").TrimEnd("`n")
        $expected = [IO.File]::ReadAllText($snapshot).Replace("`r`n", "`n").TrimEnd("`n")
        if ($process.ExitCode -eq 0 -and $output -ceq $expected) {
            Write-Output "PASS $name"
            $passed++
        } else {
            Write-Output "FAIL $name (exit $($process.ExitCode))"
            Write-Output "Expected: $expected"
            Write-Output "Actual: $output"
            $failed++
        }
    } finally {
        $process.Dispose()
    }
}
Write-Output "Examples: $passed passed, $failed failed, $($files.Count) total"
if ($failed -gt 0) { exit 1 }
