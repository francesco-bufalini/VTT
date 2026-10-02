param(
    [string]$TokenId = "ape",
    [string]$Godot = "",
    [switch]$All,
    [switch]$Force,
    [switch]$SkipImport,
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ManifestPath = Join-Path $ProjectRoot "assets\tokens\token_library.json"
$GeneratedDir = Join-Path $ProjectRoot "assets\tokens\generated"
$DistDir = Join-Path $ProjectRoot "dist\token_packs"
$CatalogPath = Join-Path $DistDir "token_catalog.json"

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
        "C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe",
        "C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe"
    )
    $Godot = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($Godot) -or -not (Test-Path $Godot)) {
    throw "Godot 4.7.2 non trovato. Passa -Godot 'C:\...\Godot_v4.7.2-stable_win64.exe'."
}

$godotDir = Split-Path -Parent $Godot
$godotName = [IO.Path]::GetFileNameWithoutExtension($Godot)
if (-not $godotName.EndsWith("_console")) {
    $consoleCandidate = Join-Path $godotDir ($godotName + "_console.exe")
    if (Test-Path $consoleCandidate) {
        $Godot = $consoleCandidate
    }
}

function Invoke-Godot {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$Phase,
        [int]$TimeoutSeconds = 180
    )

    Write-Host ">> $Phase"

    $logDir = Join-Path $ProjectRoot ".token_pack_build\logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $safePhase = ($Phase -replace '[^a-zA-Z0-9_-]', '_')
    $logPath = Join-Path $logDir ($safePhase + ".log")
    if (Test-Path $logPath) { Remove-Item -Force $logPath }

    $effectiveArguments = @("--log-file", $logPath) + $Arguments
    $argumentLine = ($effectiveArguments | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_ -replace '"', '\"') + '"'
        } else {
            $_
        }
    }) -join ' '

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Godot
    $startInfo.Arguments = $argumentLine
    $startInfo.WorkingDirectory = $ProjectRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $false
    $startInfo.RedirectStandardError = $false
    $startInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Impossibile avviare Godot durante: $Phase"
    }

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch {}
        throw "Timeout ($TimeoutSeconds s) durante: $Phase. Il processo Godot e stato terminato."
    }

    if ($process.ExitCode -ne 0) {
        Write-Host ""
        Write-Host "---- Godot log: $Phase ----"
        if (Test-Path $logPath) {
            Get-Content -Path $logPath -Tail 120 | ForEach-Object { Write-Host $_ }
        } else {
            Write-Host "(Godot non ha prodotto il file di log atteso: $logPath)"
        }
        Write-Host "---- fine log ----"
        throw "$Phase fallita con codice $($process.ExitCode)"
    }
}

function Get-ProfileVisualPath {
    param([Parameter(Mandatory = $true)]$Profile)
    $visualPath = ""
    if ($Profile.PSObject.Properties.Name -contains "visual_asset") {
        $visualPath = [string]$Profile.visual_asset
    }
    if ([string]::IsNullOrWhiteSpace($visualPath) -and $Profile.PSObject.Properties.Name -contains "obj") {
        $visualPath = [string]$Profile.obj
    }
    return $visualPath
}

function New-CatalogEntry {
    param(
        [Parameter(Mandatory = $true)]$Profile,
        [Parameter(Mandatory = $true)][string]$PckPath
    )

    $file = Get-Item $PckPath
    $sha256 = (Get-FileHash -Algorithm SHA256 $PckPath).Hash.ToLowerInvariant()
    $id = [string]$Profile.id
    $entry = [ordered]@{
        id = $id
        name = [string]$Profile.name
        size_name = [string]$Profile.size_name
        footprint = [double]$Profile.footprint
        version = 1
        bytes = [int64]$file.Length
        pck = $file.Name
        scene = ("res://remote_tokens/{0}/{0}_token.tscn" -f $id)
        sha256 = $sha256
    }
    if ($Profile.PSObject.Properties.Name -contains "source") {
        $sourceCollection = [string]$Profile.source
        if (-not [string]::IsNullOrWhiteSpace($sourceCollection)) {
            $entry.source_collection = $sourceCollection
        }
    }
    return $entry
}

function Save-Catalog {
    param([Parameter(Mandatory = $true)]$EntriesById)

    $entries = @(
        $EntriesById.Values |
            Sort-Object { [string]$_.id }
    )
    $catalog = [ordered]@{
        version = 1
        generated_at = [DateTimeOffset]::UtcNow.ToString("o")
        tokens = $entries
    }
    $catalog | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $CatalogPath
}

function Build-OneTokenPack {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)]$Profile
    )

    $visualPath = Get-ProfileVisualPath -Profile $Profile
    if ([string]::IsNullOrWhiteSpace($visualPath) -or -not $visualPath.StartsWith("res://")) {
        throw "Visual asset non valido per '$Id': $visualPath"
    }

    $visualRelative = $visualPath.Substring(6).Replace("/", [IO.Path]::DirectorySeparatorChar)
    $visualAbsolute = Join-Path $ProjectRoot $visualRelative
    if (-not (Test-Path $visualAbsolute)) {
        throw "Miniatura convertita non presente localmente: $visualAbsolute"
    }

    $pckPath = Join-Path $DistDir "$Id.pck"
    $pckResPath = "res://dist/token_packs/$Id.pck"
    $scenePath = ("res://remote_tokens/{0}/{0}_token.tscn" -f $Id)

    Write-Host ""
    Write-Host "[$Id]"
    Write-Host "Visual: $visualPath"
    Write-Host "Output: dist\token_packs\$Id.pck"

    $buildArgs = @(
        "--headless",
        "--path", $ProjectRoot,
        "--script", "res://tools/token_packs/build_one_token_pack.gd",
        "--",
        "--token-id", $Id,
        "--output", $pckResPath
    )
    Invoke-Godot -Arguments $buildArgs -Phase "Build PCK di $Id" -TimeoutSeconds 180

    if (-not (Test-Path $pckPath)) {
        throw "Il builder non ha prodotto $pckPath"
    }

    if (-not $SkipVerify) {
        $verifyArgs = @(
            "--headless",
            "--path", $ProjectRoot,
            "--script", "res://tools/token_packs/verify_token_pack.gd",
            "--",
            "--pck", $pckResPath,
            "--scene", $scenePath,
            "--token-id", $Id
        )
        Invoke-Godot -Arguments $verifyArgs -Phase "Verifica PCK di $Id" -TimeoutSeconds 60
    }

    return $pckPath
}

$manifest = Get-Content -Raw -Encoding UTF8 $ManifestPath | ConvertFrom-Json
$profilesById = @{}
foreach ($profile in $manifest.tokens) {
    $id = [string]$profile.id
    if (-not [string]::IsNullOrWhiteSpace($id)) {
        $profilesById[$id] = $profile
    }
}

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

$catalogEntries = @{}
if (Test-Path $CatalogPath) {
    try {
        $existingCatalog = Get-Content -Raw -Encoding UTF8 $CatalogPath | ConvertFrom-Json
        foreach ($entry in @($existingCatalog.tokens)) {
            if ($null -ne $entry -and -not [string]::IsNullOrWhiteSpace([string]$entry.id)) {
                $catalogEntries[[string]$entry.id] = $entry
            }
        }
    } catch {
        Write-Warning "Catalogo esistente non leggibile; verra ricostruito dalle entry disponibili: $($_.Exception.Message)"
    }
}

if ($All) {
    if (-not (Test-Path $GeneratedDir)) {
        throw "Directory miniature generate non trovata: $GeneratedDir"
    }
    $tokenIds = @(
        Get-ChildItem -Path $GeneratedDir -Directory |
            Sort-Object Name |
            ForEach-Object { $_.Name }
    )
    if ($tokenIds.Count -eq 0) {
        throw "Nessuna sottodirectory trovata in $GeneratedDir"
    }
} else {
    $tokenIds = @($TokenId)
}

Write-Host "Godot: $Godot"
Write-Host ("Modalita: " + $(if ($All) { "ALL incrementale" } else { "singolo token" }))
Write-Host "Token candidati: $($tokenIds.Count)"
if ($All -and -not $Force) {
    Write-Host "I PCK gia presenti verranno saltati e mantenuti nel catalogo."
}
if ($Force) {
    Write-Host "Force: i PCK esistenti verranno ricostruiti."
}

if (-not $SkipImport) {
    Write-Host ""
    Write-Host "Aggiorno la cache di import Godot una sola volta..."
    $importArgs = @("--headless", "--path", $ProjectRoot, "--import")
    Invoke-Godot -Arguments $importArgs -Phase "Import Godot per token packs" -TimeoutSeconds 180
}

$built = 0
$skipped = 0
$failed = 0
$failures = @()

foreach ($id in $tokenIds) {
    if (-not $profilesById.ContainsKey($id)) {
        $failed++
        $failures += ("{0}: profilo assente da assets/tokens/token_library.json" -f $id)
        Write-Warning "[$id] Profilo assente dal manifest; salto."
        continue
    }

    $profile = $profilesById[$id]
    $pckPath = Join-Path $DistDir "$id.pck"

    if ($All -and -not $Force -and (Test-Path $pckPath) -and ((Get-Item $pckPath).Length -gt 0)) {
        $catalogEntries[$id] = New-CatalogEntry -Profile $profile -PckPath $pckPath
        $skipped++
        Write-Host "[$id] gia presente: skip"
        continue
    }

    try {
        $builtPck = Build-OneTokenPack -Id $id -Profile $profile
        $catalogEntries[$id] = New-CatalogEntry -Profile $profile -PckPath $builtPck
        Save-Catalog -EntriesById $catalogEntries
        $built++
        Write-Host "[$id] OK"
    } catch {
        $failed++
        $message = $_.Exception.Message
        $failures += ("{0}: {1}" -f $id, $message)
        Write-Warning "[$id] FALLITO: $message"
        if (-not $All) {
            throw
        }
    }
}

Save-Catalog -EntriesById $catalogEntries

Write-Host ""
Write-Host "===== TOKEN PACK SUMMARY ====="
Write-Host "Costruiti: $built"
Write-Host "Gia presenti/skippati: $skipped"
Write-Host "Falliti: $failed"
Write-Host "Catalogo totale: $($catalogEntries.Count)"
Write-Host "Catalogo: $CatalogPath"

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Fallimenti:"
    foreach ($failure in $failures) {
        Write-Host " - $failure"
    }
}

if (-not $All -and $built -eq 1) {
    $pckPath = Join-Path $DistDir "$TokenId.pck"
    $file = Get-Item $pckPath
    $sha256 = (Get-FileHash -Algorithm SHA256 $pckPath).Hash.ToLowerInvariant()
    Write-Host ""
    Write-Host "PCK:     $pckPath"
    Write-Host "Bytes:   $($file.Length)"
    Write-Host "SHA-256: $sha256"
}
