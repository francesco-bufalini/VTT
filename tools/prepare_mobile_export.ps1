param(
    [Parameter(Mandatory=$true)][string]$Destination,
    [string]$Source = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
$Source = (Resolve-Path -LiteralPath $Source).Path
$Destination = [IO.Path]::GetFullPath($Destination)
if ($Destination.StartsWith($Source + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Mobile staging must be outside the original project.'
}
if (Test-Path -LiteralPath $Destination) {
    Remove-Item -LiteralPath $Destination -Force -Recurse
}
New-Item -ItemType Directory -Force -Path $Destination | Out-Null

# A dedicated export workspace prevents large desktop-only import artifacts
# from being scanned or included as transitive Godot dependencies.
# Preserve scripts, scenes, JSON catalogs, menu and GUI resources.
$excludedDirectories = @(
    (Join-Path $Source '.git'),
    (Join-Path $Source '.godot'),
    (Join-Path $Source 'build'),
    (Join-Path $Source 'outputs'),
    (Join-Path $Source 'blender'),
    (Join-Path $Source 'export_templates'),
    (Join-Path $Source 'encounter/assets'),
    (Join-Path $Source 'assets/presets')
)
$excludedFiles = @('*.glb', '*.gltf', '*.blend', '*.obj', '*.fbx', '*.stl', '*.scn', '*.exr')
& robocopy $Source $Destination /E /R:1 /W:1 /NP /NFL /NDL /NJH /NJS /XD $excludedDirectories /XF $excludedFiles
$copyExitCode = $LASTEXITCODE
if ($copyExitCode -gt 7) {
    throw "Failed to stage mobile project: robocopy exit code $copyExitCode"
}

# The normal export preset keeps x86_64 for emulator testing. A phone release
# needs only arm64-v8a; edit the temporary preset, never the shared project.
$presetPath = Join-Path $Destination 'export_presets.cfg'
$presets = [IO.File]::ReadAllText($presetPath)
if (-not $presets.Contains('architectures/x86_64=true')) {
    throw 'Android preset does not contain the expected x86_64 setting.'
}
$presets = $presets.Replace('architectures/x86_64=true', 'architectures/x86_64=false')
# Export the mobile shell directly; the desktop menu references 3D scenes that
# intentionally do not exist in this isolated project.
$presets = $presets.Replace('export_files=PackedStringArray("res://vtt/menu/main_menu.tscn", "res://vtt/mobile/creatures_mobile.tscn")', 'export_files=PackedStringArray("res://vtt/mobile/creatures_mobile.tscn")')
[IO.File]::WriteAllText($presetPath, $presets, [Text.UTF8Encoding]::new($false))
$projectPath = Join-Path $Destination 'project.godot'
$project = [IO.File]::ReadAllText($projectPath).Replace('run/main_scene="res://vtt/menu/main_menu.tscn"', 'run/main_scene="res://vtt/mobile/creatures_mobile.tscn"')
[IO.File]::WriteAllText($projectPath, $project, [Text.UTF8Encoding]::new($false))

foreach ($file in @(
    'project.godot',
    'vtt/menu/main_menu.tscn',
    'vtt/mobile/creatures_mobile.tscn',
    'vtt/data/player_5etools_catalog.json',
    'vtt/data/compendium_items_5etools.json',
    'vtt/data/miniature_bestiary.json'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $Destination $file))) {
        throw "Essential mobile resource missing from staging: $file"
    }
}
$forbidden = @(Get-ChildItem -LiteralPath $Destination -File -Recurse | Where-Object {
    $_.Extension -in @('.glb','.gltf','.blend','.obj','.fbx','.stl','.scn','.exr')
})
if ($forbidden.Count -gt 0) { throw '3D source resources were unexpectedly copied to mobile staging.' }
Write-Host "Slim Android project staged at: $Destination"
