param(
    [string]$Godot = 'godot',
    [ValidateSet('all','windows','macos','android')][string]$Target = 'all',
    [string]$OutputRoot = (Join-Path $PSScriptRoot 'build')
)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$version = & $Godot --version
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.7\.2\.stable') {
    throw 'Usare Godot 4.7.2 stable e i relativi export template.'
}
# An open editor can retain an obsolete Java path. Repair only a missing SDK,
# immediately before Android export, using an already installed Java runtime.
function Repair-AndroidJavaPath {
    if ($env:OS -ne 'Windows_NT') { return }
    $settingsPath = Join-Path $env:APPDATA 'Godot/editor_settings-4.7.tres'
    if (-not (Test-Path -LiteralPath $settingsPath)) { return }
    $settings = Get-Content -LiteralPath $settingsPath -Raw
    $match = [regex]::Match($settings, '(?m)^export/android/java_sdk_path = "(.*)"$')
    $configured = $match.Groups[1].Value.Replace('\\', '\')
    if ($configured -and (Test-Path -LiteralPath (Join-Path $configured 'bin/java.exe'))) { return }
    foreach ($candidate in @($env:JAVA_HOME, (Join-Path $env:ProgramFiles 'Android/Android Studio/jbr'))) {
        if (-not $candidate -or -not (Test-Path -LiteralPath (Join-Path $candidate 'bin/keytool.exe'))) { continue }
        $entry = 'export/android/java_sdk_path = "' + $candidate.Replace('\', '/') + '"'
        $settings = [regex]::Replace($settings, '(?m)^export/android/java_sdk_path = .*$', $entry)
        Set-Content -LiteralPath $settingsPath -Value $settings -NoNewline -Encoding utf8
        return
    }
}
function Invoke-BuildStep([string[]]$Arguments) {
    $log = & $Godot @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $log | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0 -or ($log -join "`n") -match '(?m)^(SCRIPT ERROR:|ERROR:)') {
        throw "Godot ha segnalato un errore: $($Arguments -join ' ')"
    }
}
Invoke-BuildStep @('--headless', '--path', $projectRoot, '--editor', '--import', '--quit')
foreach ($platform in @('android','windows','macos')) {
    if ($Target -ne 'all' -and $Target -ne $platform) { continue }
    if ($platform -eq 'android' -and -not $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH) {
        $signingRoot = Join-Path $env:APPDATA 'VTT/signing'
        if ((Test-Path (Join-Path $signingRoot 'release.keystore')) -and (Test-Path (Join-Path $signingRoot 'release-password.txt'))) {
            $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = Join-Path $signingRoot 'release.keystore'
            $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = 'vtt'
            $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = Get-Content (Join-Path $signingRoot 'release-password.txt') -Raw
        }
    }
    $folder = Join-Path $OutputRoot $platform
    New-Item -ItemType Directory -Force $folder | Out-Null
    $preset = switch ($platform) { windows { 'Windows Desktop' } macos { 'macOS' } android { 'Android' } }
    $filename = switch ($platform) { windows { 'VTT.exe' } macos { 'VTT-macOS.zip' } android { 'VTT-Android.apk' } }
    $outputFile = Join-Path $folder $filename
    if ($platform -eq 'android') { Repair-AndroidJavaPath }
    Invoke-BuildStep @('--headless', '--path', $projectRoot, '--export-release', $preset, $outputFile)
    if (-not (Test-Path -LiteralPath $outputFile)) {
        throw "Export $platform fallito: verificare i template 4.7.2.stable"
    }
    if ($platform -eq 'windows' -and -not (Test-Path -LiteralPath (Join-Path $folder 'VTT.pck'))) {
        throw 'Export Windows incompleto: manca VTT.pck.'
    }
    Write-Host "Build ${platform}: $outputFile"
}
