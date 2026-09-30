param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [string]$Default = "",

    [string]$Blender = "",

    [double]$TargetHeight = 1.8
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
    $candidates = Get-ChildItem -Path "$env:ProgramFiles\Blender Foundation\Blender *\blender.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending

    if ($candidates.Count -gt 0) {
        $Blender = $candidates[0].FullName
    }
}

if ([string]::IsNullOrWhiteSpace($Blender) -or -not (Test-Path $Blender)) {
    throw "Blender non trovato. Passa -Blender 'C:\...\blender.exe' oppure aggiungilo al PATH."
}

$SourcePath = (Resolve-Path $Source).Path
$InvariantTargetHeight = $TargetHeight.ToString([System.Globalization.CultureInfo]::InvariantCulture)

$arguments = @(
    "--background",
    "--python", $Converter,
    "--",
    "--source", $SourcePath,
    "--project-root", $ProjectRoot,
    "--target-height", $InvariantTargetHeight
)

if (-not [string]::IsNullOrWhiteSpace($Default)) {
    $arguments += @("--default", $Default)
}

Write-Host "Blender: $Blender"
Write-Host "Sorgente: $SourcePath"
Write-Host "Progetto: $ProjectRoot"
Write-Host "Altezza normalizzata: $TargetHeight unita Godot"

& $Blender @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Conversione terminata con codice $LASTEXITCODE"
}

Write-Host ""
Write-Host "Token pronti in assets\tokens\generated"
Write-Host "Scene trascinabili in assets\tokens\scenes"
Write-Host "Default registrato in assets\tokens\token_library.json"
