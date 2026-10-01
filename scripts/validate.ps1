param(
    [string]$Godot = "godot",
    [switch]$Tests
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Invoke-Godot {
    param([string[]]$Arguments)
    & $Godot @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Godot failed with exit code ${LASTEXITCODE}: $($Arguments -join ' ')"
    }
}

$version = & $Godot --version
if ($LASTEXITCODE -ne 0) {
    throw "Godot executable not found: $Godot"
}
if ($version -notmatch "^4\.7\.2\.stable") {
    throw "Expected Godot 4.7.2 stable, found: $version"
}

Write-Host "== Import / parse =="
Invoke-Godot @("--headless", "--path", $ProjectRoot, "--editor", "--import", "--quit")

if ($Tests) {
    $testFiles = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "tests") -Filter "test_*.gd" -File |
        Sort-Object Name

    foreach ($test in $testFiles) {
        $relative = "res://tests/$($test.Name)"
        Write-Host "== $relative =="
        Invoke-Godot @("--headless", "--path", $ProjectRoot, "--script", $relative)
    }
}

Write-Host "Validation passed."
