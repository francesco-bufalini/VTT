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
$CreatureIndex = Join-Path $ProjectRoot "assets\tokens\5etools_creature_index.json"

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

if ([string]::IsNullOrWhiteSpace($FiveEToolsRoot)) {
    $fiveEToolsCandidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:VTT_5ETOOLS_ROOT)) {
        $fiveEToolsCandidates += $env:VTT_5ETOOLS_ROOT
    }
    $fiveEToolsCandidates += @(
        (Join-Path $ProjectRoot "5etools-src"),
        (Join-Path $ProjectRoot "5etools"),
        (Join-Path $ProjectRoot ".vtt_assets\5etools-src"),
        (Join-Path (Split-Path $ProjectRoot -Parent) "5etools-src")
    )

    foreach ($candidate in $fiveEToolsCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            (Test-Path (Join-Path $candidate "data\bestiary\index.json"))) {
            $FiveEToolsRoot = (Resolve-Path $candidate).Path
            break
        }
    }

    # Locate any project-local checkout by its canonical bestiary index.
    if ([string]::IsNullOrWhiteSpace($FiveEToolsRoot)) {
        $searchRoots = @($ProjectRoot)
        $parentRoot = Split-Path $ProjectRoot -Parent
        if (-not [string]::IsNullOrWhiteSpace($parentRoot)) {
            $searchRoots += $parentRoot
        }

        foreach ($searchRoot in $searchRoots) {
            $bestiaryIndexes = Get-ChildItem -Path $searchRoot -Filter "index.json" -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Directory.Name -eq "bestiary" -and
                    $_.Directory.Parent.Name -eq "data"
                }

            foreach ($indexFile in $bestiaryIndexes) {
                $candidateRoot = $indexFile.Directory.Parent.Parent.FullName
                if (Test-Path (Join-Path $candidateRoot "data\bestiary\index.json")) {
                    $FiveEToolsRoot = $candidateRoot
                    break
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($FiveEToolsRoot)) {
                break
            }
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($FiveEToolsRoot)) {
    $FiveEToolsRoot = (Resolve-Path $FiveEToolsRoot).Path
    $bestiaryIndex = Join-Path $FiveEToolsRoot "data\bestiary\index.json"
    if (-not (Test-Path $bestiaryIndex)) {
        throw "Checkout 5eTools non valido: manca $bestiaryIndex"
    }
    if (-not (Test-Path $CreatureIndexGenerator)) {
        throw "Generatore indice creature non trovato: $CreatureIndexGenerator"
    }

    Write-Host "5eTools:  $FiveEToolsRoot"
    Write-Host "Indice:   rigenerazione metadata creature..."
    & $Blender --background --python $CreatureIndexGenerator -- $FiveEToolsRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Generazione indice creature 5eTools terminata con codice $LASTEXITCODE"
    }
}
elseif (-not (Test-Path $CreatureIndex)) {
    throw (
        "5eTools non rilevato e indice creature assente. " +
        "Il token importer richiede un checkout con data\bestiary\index.json. " +
        "Passa -FiveEToolsRoot oppure imposta VTT_5ETOOLS_ROOT."
    )
}
else {
    Write-Host "5eTools:  uso indice creature locale esistente"
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
Write-Host "Taglia:   5eTools -> override -> nome -> base/marker -> Medium"
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
