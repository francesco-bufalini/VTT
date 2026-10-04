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
        [int]$TimeoutSeconds = 60,
        [switch]$RequirePass
    )

    $stdoutPath = Join-Path $env:TEMP ("vtt-godot-" + [guid]::NewGuid() + ".out")
    $stderrPath = Join-Path $env:TEMP ("vtt-godot-" + [guid]::NewGuid() + ".err")
    try {
        # Start-Process joins arguments into one string; quote paths with spaces.
        $quotedArguments = foreach ($argument in $Arguments) {
            if ($argument -match '\s') { '"' + $argument + '"' } else { $argument }
        }
        $process = Start-Process -FilePath $script:GodotExecutable `
            -ArgumentList $quotedArguments -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            # The console launcher may own a headless child; stop this test tree.
            $process.Kill($true)
            $process.WaitForExit()
            throw "Godot timed out after $TimeoutSeconds seconds: $($Arguments -join ' ')"
        }
        $process.Refresh()

        $stdout = if (Test-Path $stdoutPath) {
            Get-Content -LiteralPath $stdoutPath -Raw
        } else { "" }
        $stderr = if (Test-Path $stderrPath) {
            Get-Content -LiteralPath $stderrPath -Raw
        } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            Write-Host $stdout.TrimEnd()
        }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            Write-Host $stderr.TrimEnd()
        }

        $combinedOutput = $stdout + [Environment]::NewLine + $stderr
        if ($combinedOutput -match "(?m)^(SCRIPT ERROR:|ERROR:)") {
            throw "Godot reported an error: $($Arguments -join ' ')"
        }

        $exitCode = $process.ExitCode
        if ($null -ne $exitCode -and $exitCode -ne 0) {
            throw "Godot failed with exit code ${exitCode}: $($Arguments -join ' ')"
        }
        if ($RequirePass -and (($stdout + $stderr) -notmatch "(?m)^PASS:")) {
            throw "Godot test ended without PASS marker: $($Arguments -join ' ')"
        }
    } finally {
        Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
    }
}


$version = (& $GodotExecutable --version | Select-Object -First 1)
if ($version -notmatch "^4\.7\.2\.stable") {
    throw "Expected Godot 4.7.2 stable, found: $version"
}

$fastTests = @(
    "test_initiative_tracker.gd",
    "test_spell_catalog_smoke.gd",
    "test_spell_targeting_lifecycle.gd",
    "test_board_smoke.gd",
    "test_dice_chat_sync.gd",
    "test_flanking_geometry.gd",
    "test_token_unique_names.gd"
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
    Invoke-Godot -Arguments @("--headless", "--path", $ProjectRoot, "--script", $relative) -TimeoutSeconds $testTimeout -RequirePass
}

Write-Host "Validation passed."
exit 0
