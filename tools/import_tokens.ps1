param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [string]$Default = "",

    [ValidateRange(0.05, 1.0)]
    [double]$DecimateRatio = 1.0,

    [string]$Blender = "",

    [string]$FiveEToolsRoot = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Converter = Join-Path $ProjectRoot "tools\token_converter\convert_tokens.py"
$CreatureIndexGenerator = Join-Path $ProjectRoot "tools\token_converter\build_5etools_creature_index.py"

if (-not (Test-Path $Converter)) {
    throw "Convertitore non trovato: $Converter"
}

if ([string]::IsNullOrWhiteSpace($Blender)) {
    $cmd = Get-Command blender -ErrorAction SilentlyContinue
    if ($cmd) {
        $Blender = $cmd.Source
    }
}

if ([string]::IsNullOrWhiteSpace($Blender)) {
    $candidates = Get-ChildItem -Path "$env:ProgramFiles\Blender Foundation\Blender *\blender.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending
    if ($candidates.Count -gt 0) {
        $Blender = $candidates[0].FullName
    }
}

if ([string]::IsNullOrWhiteSpace($Blender) -or -not (Test-Path $Blender)) {
    throw "Blender non trovato. Passa -Blender 'C:\...\blender.exe' oppure aggiungilo al PATH."
}

$CacheRoot = if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    Join-Path $env:LOCALAPPDATA "VTT\cache"
}
else {
    Join-Path $env:USERPROFILE ".vtt\cache"
}
$CreatureIndex = Join-Path $CacheRoot "5etools_creature_index.json"

if (-not (Test-Path $CacheRoot)) {
    New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null
}

if (-not [string]::IsNullOrWhiteSpace($FiveEToolsRoot)) {
    $FiveEToolsRoot = (Resolve-Path $FiveEToolsRoot).Path
    $bestiaryIndex = Join-Path $FiveEToolsRoot "data\bestiary\index.json"
    if (-not (Test-Path $bestiaryIndex)) {
        throw "Checkout 5eTools non valido: manca $bestiaryIndex"
    }

    Write-Host "5eTools:  checkout locale esplicito $FiveEToolsRoot"
    & $Blender --background --python $CreatureIndexGenerator -- $FiveEToolsRoot --output $CreatureIndex
}
elseif (-not [string]::IsNullOrWhiteSpace($env:VTT_5ETOOLS_ROOT)) {
    $FiveEToolsRoot = (Resolve-Path $env:VTT_5ETOOLS_ROOT).Path
    $bestiaryIndex = Join-Path $FiveEToolsRoot "data\bestiary\index.json"
    if (-not (Test-Path $bestiaryIndex)) {
        throw "VTT_5ETOOLS_ROOT non valido: manca $bestiaryIndex"
    }

    Write-Host "5eTools:  checkout locale da VTT_5ETOOLS_ROOT"
    & $Blender --background --python $CreatureIndexGenerator -- $FiveEToolsRoot --output $CreatureIndex
}
else {
    Write-Host "5eTools:  sorgente online (GitHub mirror)"
    Write-Host "Cache:    $CreatureIndex"
    & $Blender --background --python $CreatureIndexGenerator -- --online --output $CreatureIndex
}

if ($LASTEXITCODE -ne 0) {
    if (Test-Path $CreatureIndex) {
        Write-Warning ("Aggiornamento 5eTools fallito; uso la cache esistente: " + $CreatureIndex)
    }
    else {
        throw "Impossibile creare l indice creature 5eTools e nessuna cache disponibile."
    }
}
function Remove-TrailingDirectorySeparator([string]$PathValue) {
    $fullPath = [System.IO.Path]::GetFullPath($PathValue)
    $root = [System.IO.Path]::GetPathRoot($fullPath)

    if ($fullPath.Length -gt $root.Length) {
        $separators = [char[]]@([char]92, [char]47)
        return $fullPath.TrimEnd($separators)
    }

    return $fullPath
}

$SourcePath = Remove-TrailingDirectorySeparator ((Resolve-Path $Source).Path)
$ProjectRoot = Remove-TrailingDirectorySeparator $ProjectRoot
$Converter = Remove-TrailingDirectorySeparator $Converter

$arguments = @(
    "--background",
    "--python", $Converter,
    "--",
    "--source", $SourcePath,
    "--project-root", $ProjectRoot,
    "--creature-index", $CreatureIndex,
    "--decimate-ratio", $DecimateRatio.ToString([System.Globalization.CultureInfo]::InvariantCulture)
)

if (-not [string]::IsNullOrWhiteSpace($Default)) {
    $arguments += @("--default", $Default)
}

Write-Host "Blender:  $Blender"
Write-Host "Sorgente: $SourcePath"
Write-Host "Progetto: $ProjectRoot"
Write-Host "Taglia:   5eTools online/cache -> override -> nome -> base/marker -> Medium"
Write-Host "Scala:    visuale authored; la taglia D&D non ridimensiona la miniatura"
Write-Host "Decimate: $DecimateRatio (1.0 = nessuna semplificazione)"

& $Blender @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Conversione terminata con codice $LASTEXITCODE"
}

Write-Host ""
Write-Host "OBJ:    assets\tokens\generated"
Write-Host "Scene:  assets\tokens\scenes"
Write-Host "Indice: assets\tokens\token_library.json"
