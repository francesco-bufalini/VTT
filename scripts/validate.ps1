param(
    [string]$Godot = "godot",
    [switch]$Tests,
    [switch]$SmokeTests,
    [switch]$FullTests
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# A self-hosted runner intentionally retains .godot/ between checkouts.
# Godot's cached extension_list.cfg may still name a GDExtension that was
# removed from the repository (for example, the retired native WebView).
# Drop only missing entries; keep the other imported Godot resources intact.
$extensionListPath = Join-Path $ProjectRoot ".godot/extension_list.cfg"
if (Test-Path -LiteralPath $extensionListPath -PathType Leaf) {
    $keptEntries = @()
    $staleEntries = @()
    foreach ($entry in (Get-Content -LiteralPath $extensionListPath)) {
        $trimmedEntry = $entry.Trim()
        if ($trimmedEntry -match '^res://(.+\.gdextension)& node (Join-Path $PSScriptRoot "check_pwa_assets.mjs")
if ($LASTEXITCODE -ne 0) { throw "PWA update asset validation failed." }

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
            # The Windows runner uses a .NET build without Process.Kill(bool).
            # taskkill /T reliably terminates the console launcher and its Godot child.
            if ($env:OS -eq "Windows_NT") {
                & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null
            } else {
                $process.Kill()
            }
            $process.WaitForExit()
            $timeoutStdout = if (Test-Path $stdoutPath) {
                Get-Content -LiteralPath $stdoutPath -Raw
            } else { "" }
            $timeoutStderr = if (Test-Path $stderrPath) {
                Get-Content -LiteralPath $stderrPath -Raw
            } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($timeoutStdout)) {
                Write-Host $timeoutStdout.TrimEnd()
            }
            if (-not [string]::IsNullOrWhiteSpace($timeoutStderr)) {
                Write-Host $timeoutStderr.TrimEnd()
            }
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
        if ($RequirePass -and (($stdout + $stderr) -notmatch "(?m)^PASS(?::|\s)")) {
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
    "test_character_token_images.gd",
    "test_class_feature_activation.gd",
    "test_lan_presence.gd",
    "test_combat_basic_actions.gd",
    "test_map_data_controller.gd",
    "test_initiative_tracker.gd",
    "test_artificer_and_natural_armor.gd",
    "test_spell_catalog_smoke.gd",
    "test_spell_slot_profiles.gd",
    "test_spell_catalog_edition_geometry.gd",
    "test_spell_targeting_lifecycle.gd",
    "test_pwa_backup_store.gd",
    "test_area_dimensions.gd",
    "test_map_box_drawing.gd",
    "test_token_context_conditions.gd",
    "test_token_catalog_merge.gd",
    "test_scene_token_pack_recovery.gd",
    "test_board_smoke.gd",
    "test_structured_resource_trackers.gd",
    "test_monster_action_metadata.gd",
    "test_structured_numeric_bonuses.gd",
    "test_split_item_bonuses.gd",
    "test_movement_speeds.gd",
    "test_linked_token_motion.gd",
    "test_token_effects_and_group_movement.gd",
    "test_quick_custom_dialogs.gd",
    "test_dice_bonus_scopes.gd",
    "test_creature_formula_bonuses.gd",
    "test_race_subrace_selection.gd",
    "test_dialog_layout.gd",
    "test_tactical_overlay.gd",
    "test_content_layer_separation.gd",
    "test_camera_2d_height.gd",
    "test_measurement_token_elevation.gd",
    "test_grid_2d_elevation_colors.gd",
    "test_encounter_sync_scripts.gd",
    "test_initiative_creature_selection.gd",
    "test_content_catalog.gd",
    "test_item_transport.gd",
    "test_item_board_integration.gd",
    "test_dice_chat_sync.gd",
    "test_flanking_geometry.gd",
    "test_token_unique_names.gd",
    "test_token_spawn_targeting.gd",
    "test_bestiary_token_hat.gd"
)

# Small, representative CI smoke suite; the existing -Tests and -FullTests
# remain available for broader regression coverage outside the 60s CI gate.
$ciSmokeTestNames = @(
    "test_spell_catalog_smoke.gd",
    "test_spell_slot_profiles.gd",
    "test_origin_granted_spells.gd",
    "test_structured_resource_trackers.gd",
    "test_monster_action_metadata.gd",
    "test_board_smoke.gd",
    "test_dialog_layout.gd"
)

if ($FullTests) {
    Write-Host "== Full project import / parse =="
    Invoke-Godot @("--headless", "--path", $ProjectRoot, "--editor", "--import", "--quit") 300

    $testFiles = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "tests") `
        -Filter "test_*.gd" -File | Sort-Object Name
} elseif ($SmokeTests -or $Tests) {
    Write-Host $(if ($SmokeTests) { "== Bounded CI smoke validation ==" } else { "== Fast VTT validation ==" })
    $testFiles = foreach ($name in $(if ($SmokeTests) { $ciSmokeTestNames } else { $fastTests })) {
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
    $testTimeout = if ($SmokeTests) {
        10
    } elseif ($FullTests) {
        90
    } elseif ($test.Name -in @("test_token_effects_and_group_movement.gd", "test_item_transport.gd", "test_item_board_integration.gd", "test_race_subrace_selection.gd")) {
        45
    } else {
        12
    }
    if ($Tests -and $testTimeout -gt 90) {
        throw "Fast validation cannot run $($test.Name): timeout $testTimeout exceeds 90 seconds."
    }
    # Runtime integration tests need normal node initialization, not editor mode.
    $testArguments = @("--headless", "--path", $ProjectRoot, "--script", $relative)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Invoke-Godot -Arguments $testArguments -TimeoutSeconds $testTimeout -RequirePass
    } finally {
        $stopwatch.Stop()
        Write-Host ("== {0}: {1:N1}s (limit {2}s) ==" -f $test.Name, $stopwatch.Elapsed.TotalSeconds, $testTimeout)
    }
}

Write-Host "Validation passed."
exit 0
) {
            $extensionPath = Join-Path $ProjectRoot $Matches[1]
            if (-not (Test-Path -LiteralPath $extensionPath -PathType Leaf)) {
                $staleEntries += $trimmedEntry
                continue
            }
        }
        $keptEntries += $entry
    }
    if ($staleEntries.Count -gt 0) {
        if ($keptEntries.Count -gt 0) {
            [System.IO.File]::WriteAllLines(
                $extensionListPath,
                [string[]]$keptEntries,
                (New-Object System.Text.UTF8Encoding($false))
            )
        } else {
            Remove-Item -LiteralPath $extensionListPath -Force
        }
        Write-Host ("Removed stale Godot extension cache entries: " + ($staleEntries -join ", "))
    }
}

& node (Join-Path $PSScriptRoot "check_pwa_assets.mjs")
if ($LASTEXITCODE -ne 0) { throw "PWA update asset validation failed." }

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
            # The Windows runner uses a .NET build without Process.Kill(bool).
            # taskkill /T reliably terminates the console launcher and its Godot child.
            if ($env:OS -eq "Windows_NT") {
                & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null
            } else {
                $process.Kill()
            }
            $process.WaitForExit()
            $timeoutStdout = if (Test-Path $stdoutPath) {
                Get-Content -LiteralPath $stdoutPath -Raw
            } else { "" }
            $timeoutStderr = if (Test-Path $stderrPath) {
                Get-Content -LiteralPath $stderrPath -Raw
            } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($timeoutStdout)) {
                Write-Host $timeoutStdout.TrimEnd()
            }
            if (-not [string]::IsNullOrWhiteSpace($timeoutStderr)) {
                Write-Host $timeoutStderr.TrimEnd()
            }
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
        if ($RequirePass -and (($stdout + $stderr) -notmatch "(?m)^PASS(?::|\s)")) {
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
    "test_character_token_images.gd",
    "test_class_feature_activation.gd",
    "test_lan_presence.gd",
    "test_combat_basic_actions.gd",
    "test_map_data_controller.gd",
    "test_initiative_tracker.gd",
    "test_artificer_and_natural_armor.gd",
    "test_spell_catalog_smoke.gd",
    "test_spell_slot_profiles.gd",
    "test_spell_catalog_edition_geometry.gd",
    "test_spell_targeting_lifecycle.gd",
    "test_pwa_backup_store.gd",
    "test_area_dimensions.gd",
    "test_map_box_drawing.gd",
    "test_token_context_conditions.gd",
    "test_token_catalog_merge.gd",
    "test_scene_token_pack_recovery.gd",
    "test_board_smoke.gd",
    "test_structured_resource_trackers.gd",
    "test_monster_action_metadata.gd",
    "test_structured_numeric_bonuses.gd",
    "test_split_item_bonuses.gd",
    "test_movement_speeds.gd",
    "test_linked_token_motion.gd",
    "test_token_effects_and_group_movement.gd",
    "test_quick_custom_dialogs.gd",
    "test_dice_bonus_scopes.gd",
    "test_creature_formula_bonuses.gd",
    "test_race_subrace_selection.gd",
    "test_dialog_layout.gd",
    "test_tactical_overlay.gd",
    "test_content_layer_separation.gd",
    "test_camera_2d_height.gd",
    "test_measurement_token_elevation.gd",
    "test_grid_2d_elevation_colors.gd",
    "test_encounter_sync_scripts.gd",
    "test_initiative_creature_selection.gd",
    "test_content_catalog.gd",
    "test_item_transport.gd",
    "test_item_board_integration.gd",
    "test_dice_chat_sync.gd",
    "test_flanking_geometry.gd",
    "test_token_unique_names.gd",
    "test_token_spawn_targeting.gd",
    "test_bestiary_token_hat.gd"
)

# Small, representative CI smoke suite; the existing -Tests and -FullTests
# remain available for broader regression coverage outside the 60s CI gate.
$ciSmokeTestNames = @(
    "test_spell_catalog_smoke.gd",
    "test_spell_slot_profiles.gd",
    "test_origin_granted_spells.gd",
    "test_structured_resource_trackers.gd",
    "test_monster_action_metadata.gd",
    "test_board_smoke.gd",
    "test_dialog_layout.gd"
)

if ($FullTests) {
    Write-Host "== Full project import / parse =="
    Invoke-Godot @("--headless", "--path", $ProjectRoot, "--editor", "--import", "--quit") 300

    $testFiles = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "tests") `
        -Filter "test_*.gd" -File | Sort-Object Name
} elseif ($SmokeTests -or $Tests) {
    Write-Host $(if ($SmokeTests) { "== Bounded CI smoke validation ==" } else { "== Fast VTT validation ==" })
    $testFiles = foreach ($name in $(if ($SmokeTests) { $ciSmokeTestNames } else { $fastTests })) {
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
    $testTimeout = if ($SmokeTests) {
        10
    } elseif ($FullTests) {
        90
    } elseif ($test.Name -in @("test_token_effects_and_group_movement.gd", "test_item_transport.gd", "test_item_board_integration.gd", "test_race_subrace_selection.gd")) {
        45
    } else {
        12
    }
    if ($Tests -and $testTimeout -gt 90) {
        throw "Fast validation cannot run $($test.Name): timeout $testTimeout exceeds 90 seconds."
    }
    # Runtime integration tests need normal node initialization, not editor mode.
    $testArguments = @("--headless", "--path", $ProjectRoot, "--script", $relative)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Invoke-Godot -Arguments $testArguments -TimeoutSeconds $testTimeout -RequirePass
    } finally {
        $stopwatch.Stop()
        Write-Host ("== {0}: {1:N1}s (limit {2}s) ==" -f $test.Name, $stopwatch.Elapsed.TotalSeconds, $testTimeout)
    }
}

Write-Host "Validation passed."
exit 0
