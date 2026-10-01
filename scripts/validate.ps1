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

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    $failurePattern = (
        "SCRIPT ERROR:.*(Assertion failed|Parse Error|Compile Error|Invalid call|" +
        "Invalid access|Invalid assignment)|ERROR: Failed to load script"
    )

    try {
        $process = Start-Process -FilePath $script:GodotExecutable `
            -ArgumentList $Arguments -NoNewWindow -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $failureDetected = $false

        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 500
            $combined = (
                (Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue) +
                [Environment]::NewLine +
                (Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue)
            )
            if ($combined -match $failurePattern) {
                $failureDetected = $true
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                $process.WaitForExit()
                break
            }
            if ([DateTime]::UtcNow -ge $deadline) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                $process.WaitForExit()
                $combined | Write-Host
                throw "Godot timed out after $TimeoutSeconds seconds: $($Arguments -join ' ')"
            }
        }

        $stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
        if ($stdout) { $stdout | Write-Host }
        if ($stderr) { $stderr | Write-Host }

        if ($failureDetected) {
            throw "Godot reported a script failure: $($Arguments -join ' ')"
        }
        $exitCode = $process.ExitCode
        if ($null -ne $exitCode -and $exitCode -ne 0) {
            throw "Godot failed with exit code ${exitCode}: $($Arguments -join ' ')"
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
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
