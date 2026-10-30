param(
    [string]$Executable = 'zig-out/bin/ravi',
    [ValidateRange(1, 10000)][int]$Cases = 128,
    [ValidateRange(1, 30)][int]$TimeoutSeconds = 2,
    [int]$Seed = 20261030
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
if ($IsWindows -and !$Executable.EndsWith('.exe')) { $Executable += '.exe' }
$binary = (Resolve-Path -LiteralPath (Join-Path $workspace $Executable)).Path
$directory = Join-Path $workspace 'zig-out/fuzz-source'
[void][IO.Directory]::CreateDirectory($directory)
$random = [Random]::new($Seed)
$seeds = @(
    "# ravi: language=en`nfunction f(x: int):`n    return x + 1`nf(3)`n",
    "a = [1, 2, 3]`nmudrisu(a[0])`n",
    "kriya f(x):`n    nodu:`n        kodu x / 0`n    tappu:`n        kodu none`n",
    "a = {`"name`":`"ಕನ್ನಡ`"}`n",
    "# ravi: language=en`nf = function(x) => x * 2`nt = spawn f(3)`nwait t`n"
)
$alphabet = @('(', ')', '[', ']', '{', '}', ':', ',', '=', '/', '!', '"', "'", "`n", "`t", ' ', 'a', '0', 'ಕ')
for ($case = 0; $case -lt $Cases; $case++) {
    $text = $seeds[$case % $seeds.Count]
    for ($mutation = 0; $mutation -lt 1 + ($case % 8); $mutation++) {
        $offset = $random.Next($text.Length + 1)
        switch ($random.Next(3)) {
            0 { $text = $text.Insert($offset, $alphabet[$random.Next($alphabet.Count)]) }
            1 { if ($offset -lt $text.Length) { $text = $text.Remove($offset, 1) } }
            2 { $text = $text.Insert($offset, '(' * $random.Next(1, 32)) }
        }
    }
    $file = Join-Path $directory ('case-{0:D5}.rk' -f $case)
    [IO.File]::WriteAllText($file, $text, [Text.UTF8Encoding]::new($false))
    $process = [Diagnostics.Process]::new()
    $process.StartInfo.FileName = $binary
    $process.StartInfo.WorkingDirectory = $workspace
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.ArgumentList.Add('check')
    $process.StartInfo.ArgumentList.Add($file)
    try {
        [void]$process.Start()
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "Fuzz timeout: seed=$Seed case=$case input=$file"
        }
        [void]$output.GetAwaiter().GetResult()
        $diagnostic = $errors.GetAwaiter().GetResult()
        if ($process.ExitCode -notin 0, 1, 2 -or $diagnostic -match 'panic:|Segmentation fault|stack overflow|General protection exception') {
            throw "Fuzz crash: seed=$Seed case=$case exit=$($process.ExitCode) input=$file`n$diagnostic"
        }
    } finally { $process.Dispose() }
}
Write-Output "Bounded source fuzz: $Cases cases completed; seed=$Seed. Inputs retained in zig-out/fuzz-source."
