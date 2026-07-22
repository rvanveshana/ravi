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

$RAVI = ".\zig-out\bin\ravi.exe"
$EXAMPLES_DIR = ".\examples"
$PASSED = 0
$FAILED = 0

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

Get-ChildItem -Path $EXAMPLES_DIR -Filter "*.rk" | ForEach-Object {
    $file = $_.FullName
    $name = $_.Name
    
    Write-Host "Testing $name ... " -NoNewline
    
    # Run in execute mode
    $langFlag = @()
    if ($name -eq "english.rk") {
        $langFlag = @("--lang", "en")
    }
    
    $output = & $RAVI run @langFlag $file 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[PASS]" -ForegroundColor Green
        $global:PASSED++
    } else {
        Write-Host "[FAIL: Run]" -ForegroundColor Red
        Write-Host "Error Output: $output" -ForegroundColor Red
        $global:FAILED++
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Test Summary                           " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed: $PASSED" -ForegroundColor Green
Write-Host "Failed: $FAILED" -ForegroundColor Red

if ($FAILED -gt 0) {
    exit 1
} else {
    Write-Host "All examples executed successfully!" -ForegroundColor Green
    exit 0
}
