param(
    [string]$Godot = 'godot',
    [ValidateSet('all','windows','macos')][string]$Target = 'all',
    [string]$OutputRoot = (Join-Path $PSScriptRoot 'build')
)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$version = & $Godot --version
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.7\.2\.stable') {
    throw 'Usare Godot 4.7.2 stable e i relativi export template.'
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
foreach ($platform in @('windows','macos')) {
    if ($Target -ne 'all' -and $Target -ne $platform) { continue }
    $folder = Join-Path $OutputRoot $platform
    New-Item -ItemType Directory -Force $folder | Out-Null
    $preset = switch ($platform) { windows { 'Windows Desktop' } macos { 'macOS' } }
    $filename = switch ($platform) { windows { 'VTT.exe' } macos { 'VTT-macOS.zip' } }
    $outputFile = Join-Path $folder $filename
    Invoke-BuildStep @('--headless', '--path', $projectRoot, '--export-release', $preset, $outputFile)
    if (-not (Test-Path -LiteralPath $outputFile)) {
        throw "Export $platform fallito: verificare i template 4.7.2.stable"
    }
    if ($platform -eq 'windows' -and -not (Test-Path -LiteralPath (Join-Path $folder 'VTT.pck'))) {
        throw 'Export Windows incompleto: manca VTT.pck.'
    }
    Write-Host "Build ${platform}: $outputFile"
}
