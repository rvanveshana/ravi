# PowerShell Test Suite Runner for Ravi Language Examples
# Runs check and execution for all examples across all language modes

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Building Ravi Compiler & VM...        " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

zig build
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed!"
    exit 1
}

$isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$RAVI = if ($isWindowsHost) { ".\zig-out\bin\ravi.exe" } else { "./zig-out/bin/ravi" }
$EXAMPLES_DIR = ".\examples"
$PASSED = 0
$FAILED = 0
$EXPECTED_FAILED = 0

# Features represented by executable examples but not implemented yet belong
# here until their milestone is complete. An unexpected success is treated as
# a failure so the example cannot silently remain misclassified.
$EXPECTED_FAILURES = @{}

Write-Host "`nRunning Unit Tests via zig build test..." -ForegroundColor Yellow
zig build test
if ($LASTEXITCODE -eq 0) {
    Write-Host "[SUCCESS] Unit tests passed!`n" -ForegroundColor Green
} else {
    Write-Error "[FAILURE] Unit tests failed!"
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Executing All Ravi Examples...         " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

foreach ($example in (Get-ChildItem -Path $EXAMPLES_DIR -Filter "*.rk")) {
    $file = $example.FullName
    $name = $example.Name
    
    Write-Host "Testing $name ... " -NoNewline
    
    $langFlag = @()
    if ($name -eq "english.rk") {
        $langFlag = @("--lang", "en")
    }

    $output = (& $RAVI run @langFlag $file 2>&1) -join "`n"
    $exitCode = $LASTEXITCODE
    $expectedError = $EXPECTED_FAILURES[$name]
    if ($null -ne $expectedError) {
        if ($exitCode -ne 0 -and $output -match [regex]::Escape($expectedError)) {
            Write-Host "[EXPECTED FAILURE: $expectedError]" -ForegroundColor DarkYellow
            $EXPECTED_FAILED++
        } else {
            Write-Host "[FAIL: expected '$expectedError']" -ForegroundColor Red
            Write-Host "Exit: $exitCode Output: $output" -ForegroundColor Red
            $FAILED++
        }
    } elseif ($exitCode -eq 0) {
        Write-Host "[PASS]" -ForegroundColor Green
        $PASSED++
    } else {
        Write-Host "[FAIL: Execution or result mismatch]" -ForegroundColor Red
        Write-Host "Exit: $exitCode Output: $output" -ForegroundColor Red
        $FAILED++
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Test Summary                           " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed: $PASSED" -ForegroundColor Green
Write-Host "Expected failures: $EXPECTED_FAILED" -ForegroundColor DarkYellow
Write-Host "Failed: $FAILED" -ForegroundColor Red

if ($FAILED -gt 0) {
    exit 1
} else {
    Write-Host "All supported examples executed successfully!" -ForegroundColor Green
    exit 0
}
