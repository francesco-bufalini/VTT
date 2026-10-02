param(
    [string]$TokenId = "ape",
    [string]$Godot = "",
    [switch]$SkipImport,
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ManifestPath = Join-Path $ProjectRoot "assets\tokens\token_library.json"
$DistDir = Join-Path $ProjectRoot "dist\token_packs"

if (-not (Test-Path $ManifestPath)) {
    throw "Manifest token non trovato: $ManifestPath"
}

if ([string]::IsNullOrWhiteSpace($Godot)) {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { $Godot = $cmd.Source }
}
if ([string]::IsNullOrWhiteSpace($Godot)) {
    $cmd = Get-Command godot4 -ErrorAction SilentlyContinue
    if ($cmd) { $Godot = $cmd.Source }
}
if ([string]::IsNullOrWhiteSpace($Godot)) {
    $candidates = @(
        "C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe",
        "C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe"
    )
    $Godot = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($Godot) -or -not (Test-Path $Godot)) {
    throw "Godot 4.7.2 non trovato. Passa -Godot 'C:\...\Godot_v4.7.2-stable_win64.exe'."
}

$manifest = Get-Content -Raw -Encoding UTF8 $ManifestPath | ConvertFrom-Json
$profile = $manifest.tokens | Where-Object { $_.id -eq $TokenId } | Select-Object -First 1
if (-not $profile) {
    throw "Token '$TokenId' non presente in assets/tokens/token_library.json"
}

$visualPath = ""
if ($profile.PSObject.Properties.Name -contains "visual_asset") {
    $visualPath = [string]$profile.visual_asset
}
if ([string]::IsNullOrWhiteSpace($visualPath) -and $profile.PSObject.Properties.Name -contains "obj") {
    $visualPath = [string]$profile.obj
}
if ([string]::IsNullOrWhiteSpace($visualPath) -or -not $visualPath.StartsWith("res://")) {
    throw "Visual asset non valido per '$TokenId': $visualPath"
}

$visualRelative = $visualPath.Substring(6).Replace("/", [IO.Path]::DirectorySeparatorChar)
$visualAbsolute = Join-Path $ProjectRoot $visualRelative
if (-not (Test-Path $visualAbsolute)) {
    throw @"
Miniatura convertita non presente localmente:
  $visualAbsolute

Il branch non contiene piu gli OBJ/GLB pesanti per scelta.
Rigenera/importa la miniatura con tools/import_tokens.ps1, poi rilancia questo comando.
Gli originali non vengono modificati.
"@
}

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

Write-Host "Godot:   $Godot"
Write-Host "Token:   $TokenId"
Write-Host "Visual:  $visualPath"
Write-Host "Output:  dist\token_packs\$TokenId.pck"

if (-not $SkipImport) {
    Write-Host ""
    Write-Host "Aggiorno la cache di import Godot..."
    $importArgs = @("--headless", "--path", $ProjectRoot, "--import")
    & $Godot @importArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Import Godot fallito con codice $LASTEXITCODE"
    }
}

$pckResPath = "res://dist/token_packs/$TokenId.pck"
$buildArgs = @(
    "--headless",
    "--path", $ProjectRoot,
    "--script", "res://tools/token_packs/build_one_token_pack.gd",
    "--",
    "--token-id", $TokenId,
    "--output", $pckResPath
)
& $Godot @buildArgs
if ($LASTEXITCODE -ne 0) {
    throw "Build PCK fallita con codice $LASTEXITCODE"
}

$pckPath = Join-Path $DistDir "$TokenId.pck"
if (-not (Test-Path $pckPath)) {
    throw "Il builder non ha prodotto $pckPath"
}

$scenePath = "res://remote_tokens/" + $TokenId + "/" + $TokenId + "_token.tscn"
if (-not $SkipVerify) {
    Write-Host ""
    Write-Host "Verifico mount + load PackedScene + instantiate..."
    $verifyArgs = @(
        "--headless",
        "--path", $ProjectRoot,
        "--script", "res://tools/token_packs/verify_token_pack.gd",
        "--",
        "--pck", $pckResPath,
        "--scene", $scenePath,
        "--token-id", $TokenId
    )
    & $Godot @verifyArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Verifica PCK fallita con codice $LASTEXITCODE"
    }
}

$file = Get-Item $pckPath
$sha256 = (Get-FileHash -Algorithm SHA256 $pckPath).Hash.ToLowerInvariant()
$sourceCollection = ""
if ($profile.PSObject.Properties.Name -contains "source") {
    $sourceCollection = [string]$profile.source
}

$entry = [ordered]@{
    id = [string]$profile.id
    name = [string]$profile.name
    size_name = [string]$profile.size_name
    footprint = [double]$profile.footprint
    version = 1
    bytes = [int64]$file.Length
    pck = $file.Name
    scene = $scenePath
    sha256 = $sha256
}
if (-not [string]::IsNullOrWhiteSpace($sourceCollection)) {
    $entry.source_collection = $sourceCollection
}

$catalog = [ordered]@{
    version = 1
    generated_at = [DateTimeOffset]::UtcNow.ToString("o")
    tokens = @($entry)
}
$catalogPath = Join-Path $DistDir "token_catalog.json"
$catalog | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $catalogPath

Write-Host ""
Write-Host "OK"
Write-Host "PCK:      $pckPath"
Write-Host "Catalogo: $catalogPath"
Write-Host "Bytes:    $($file.Length)"
Write-Host "SHA-256:  $sha256"
