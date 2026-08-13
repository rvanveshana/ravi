param(
    [string]$InputPath = "config/feature-matrix.json",
    [string]$OutputPath = "docs/feature-matrix.md"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$inputFile = Join-Path $root $InputPath
$outputFile = Join-Path $root $OutputPath
$features = Get-Content -Raw -LiteralPath $inputFile | ConvertFrom-Json
$stages = @("designed", "parsed", "analyzed", "lowered", "executed", "tested")
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# Ravi Feature Matrix")
$lines.Add("")
$lines.Add("Generated from ``$InputPath`` by ``tools/generate_feature_matrix.ps1``.")
$lines.Add("")
$lines.Add(("| Feature | " + (($stages | ForEach-Object { $_ }) -join " | ") + " |"))
$lines.Add(("| --- | " + (($stages | ForEach-Object { "---" }) -join " | ") + " |"))
foreach ($feature in $features) {
    $values = $stages | ForEach-Object { if ($feature.$_) { "yes" } else { "no" } }
    $lines.Add(("| {0} | {1} |" -f $feature.feature, ($values -join " | ")))
}
[System.IO.File]::WriteAllLines($outputFile, $lines)
