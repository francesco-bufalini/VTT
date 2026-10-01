param(
    [string]$Godot = "godot",
    [switch]$Tests,
    [switch]$FullTests
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

if (Test-Path -LiteralPath $Godot -PathType Leaf) {
    $GodotExecutable = (Resolve-Path -LiteralPath $Godot).Path
} else {
    $GodotCommand = Get-Command $Godot -ErrorAction SilentlyContinue
    if ($null -eq $GodotCommand) {
        throw "Godot executable not found: $Godot"
    }
    $GodotExecutable = $GodotCommand.Source
}

# Prefer the console build on Windows: unlike the GUI executable it exposes
# a reliable process exit code to PowerShell while remaining fully headless.
if ($GodotExecutable -notmatch "_console\.exe$") {
    $directory = Split-Path -Parent $GodotExecutable
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($GodotExecutable)
    $consoleCandidate = Join-Path $directory ($baseName + "_console.exe")
    if (Test-Path -LiteralPath $consoleCandidate -PathType Leaf) {
        $GodotExecutable = $consoleCandidate
    }
}

function Invoke-Godot {
    param(
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 60
    )
    $process = Start-Process -FilePath $script:GodotExecutable `
        -ArgumentList $Arguments -NoNewWindow -PassThru

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "Godot timed out after $TimeoutSeconds seconds: $($Arguments -join ' ')"
    }
    $process.Refresh()
    $exitCode = $process.ExitCode
    if ($null -ne $exitCode -and $exitCode -ne 0) {
        throw "Godot failed with exit code ${exitCode}: $($Arguments -join ' ')"
    }
}

$version = (& $GodotExecutable --version | Select-Object -First 1)
if ($version -notmatch "^4\.7\.2\.stable") {
    throw "Expected Godot 4.7.2 stable, found: $version"
}

$fastTests = @(
    "test_initiative_tracker.gd",
    "test_spell_catalog_smoke.gd",
    "test_board_smoke.gd"
)

if ($FullTests) {
    Write-Host "== Full project import / parse =="
    Invoke-Godot @("--headless", "--path", $ProjectRoot, "--editor", "--import", "--quit") 300

    $testFiles = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "tests") `
        -Filter "test_*.gd" -File | Sort-Object Name
} elseif ($Tests) {
    Write-Host "== Fast VTT validation =="
    $testFiles = foreach ($name in $fastTests) {
        $path = Join-Path (Join-Path $ProjectRoot "tests") $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Fast test is missing from checkout: $name"
        }
        Get-Item -LiteralPath $path
    }
} else {
    Write-Host "== Lightweight parse smoke test =="
    $testFiles = @(Get-Item -LiteralPath (Join-Path $ProjectRoot "tests/test_spell_area_catalog.gd"))
}

foreach ($test in $testFiles) {
    $relative = "res://tests/$($test.Name)"
    Write-Host "== $relative =="
    $testTimeout = if ($FullTests) { 90 } else { 12 }
    Invoke-Godot @("--headless", "--path", $ProjectRoot, "--script", $relative) $testTimeout
}

Write-Host "Validation passed."
