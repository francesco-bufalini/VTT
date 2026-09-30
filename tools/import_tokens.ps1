param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [string]$Default = "",

    [ValidateRange(0.05, 1.0)]
    [double]$DecimateRatio = 1.0,

    [string]$Blender = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Converter = Join-Path $ProjectRoot "tools\token_converter\convert_tokens.py"

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
    "--decimate-ratio", $DecimateRatio.ToString([System.Globalization.CultureInfo]::InvariantCulture)
)

if (-not [string]::IsNullOrWhiteSpace($Default)) {
    $arguments += @("--default", $Default)
}

Write-Host "Blender:  $Blender"
Write-Host "Sorgente: $SourcePath"
Write-Host "Progetto: $ProjectRoot"
Write-Host "Scala:    ricavata automaticamente dalla base della miniatura"
Write-Host "Decimate: $DecimateRatio (1.0 = nessuna semplificazione)"

& $Blender @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Conversione terminata con codice $LASTEXITCODE"
}

Write-Host ""
Write-Host "OBJ:    assets\tokens\generated"
Write-Host "Scene:  assets\tokens\scenes"
Write-Host "Indice: assets\tokens\token_library.json"
