param(
    [string]$Godot = "godot",
    [switch]$Tests,
    [switch]$FullImport
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

function Invoke-Godot {
    param(
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 180
    )
    $process = Start-Process -FilePath $script:GodotExecutable `
        -ArgumentList $Arguments -NoNewWindow -PassThru
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "Godot timed out after $TimeoutSeconds seconds: $($Arguments -join ' ')"
    }
    if ($process.ExitCode -ne 0) {
        throw "Godot failed with exit code $($process.ExitCode): $($Arguments -join ' ')"
    }
}

$version = (& $GodotExecutable --version | Select-Object -First 1)
if ($version -notmatch "^4\.7\.2\.stable") {
    throw "Expected Godot 4.7.2 stable, found: $version"
}

$ImportSentinel = Join-Path $ProjectRoot "vtt/icons/eye.svg.import"
if ($FullImport -or -not (Test-Path -LiteralPath $ImportSentinel)) {
    Write-Host "== Full project import / parse =="
    Invoke-Godot -Arguments @("--headless", "--path", $ProjectRoot, "--editor", "--import", "--quit") -TimeoutSeconds 1200
}

if ($Tests) {
    $testFiles = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "tests") -Filter "test_*.gd" -File |
        Sort-Object Name

    foreach ($test in $testFiles) {
        $relative = "res://tests/$($test.Name)"
        Write-Host "== $relative =="
        Invoke-Godot -Arguments @("--headless", "--path", $ProjectRoot, "--script", $relative)
    }
}

Write-Host "Validation passed."
