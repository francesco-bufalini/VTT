param([string]$Godot = 'godot', [ValidateSet('all','windows','macos')][string]$Target = 'all')
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$version = & $Godot --version
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.7\.2\.stable') { throw 'Usare Godot 4.7.2 stable e i relativi export template.' }
& $Godot --headless --path $projectRoot --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Importazione fallita' }
foreach ($platform in @('windows','macos')) {
    if ($Target -ne 'all' -and $Target -ne $platform) { continue }
    $folder = Join-Path $projectRoot "build/$platform"
    New-Item -ItemType Directory -Force $folder | Out-Null
    $preset = if ($platform -eq 'windows') { 'Windows Desktop' } else { 'macOS' }
    $filename = if ($platform -eq 'windows') { 'Astrolabe.exe' } else { 'Astrolabe.zip' }
    $outputFile = Join-Path $folder $filename
    & $Godot --headless --path $projectRoot --export-release $preset $outputFile
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputFile)) { throw "Export $platform fallito: verificare i template 4.7.2.stable" }
}
