param(
    [ValidateSet("Setup", "ListExtensions", "SyncExtensions", "UpdateExtensions", "InstallExtension", "InstallExtensionFile", "RemoveExtension", "Export", "FetchAssets")]
    [string]$Action = "Setup",
    [string]$Blender = "",
    [string]$AssetRoot = "",
    [string[]]$Packages = @(),
    [string]$File = "",
    [string]$Blend = "",
    [string]$Output = "",
    [string]$Collection = "",
    [string]$Manifest = "",
    [switch]$Animations,
    [switch]$KeepModifiers,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ConfigPath = Join-Path $PSScriptRoot "environment.json"
$Helper = Join-Path $PSScriptRoot "vtt_blender.py"
$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

function Find-Blender([string]$Requested) {
    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        if (Test-Path -LiteralPath $Requested -PathType Leaf) {
            return (Resolve-Path -LiteralPath $Requested).Path
        }
        $cmd = Get-Command $Requested -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        throw "Blender executable not found: $Requested"
    }

    $cmd = Get-Command blender -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $root = "$env:ProgramFiles\Blender Foundation"
    if (Test-Path $root) {
        $candidate = Get-ChildItem -Path $root -Filter blender.exe -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "Blender 5\.2" } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }

    throw "Blender 5.2.x not found. Install Blender 5.2 LTS or pass -Blender explicitly."
}

function Get-AssetRoot {
    if ([string]::IsNullOrWhiteSpace($AssetRoot)) {
        return [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot ([string]$Config.asset_root)))
    }
    if ([System.IO.Path]::IsPathRooted($AssetRoot)) {
        return [System.IO.Path]::GetFullPath($AssetRoot)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $AssetRoot))
}

function Invoke-Extension([string[]]$Arguments) {
    & $script:BlenderExe --command extension @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Blender extension command failed: $($Arguments -join ' ')"
    }
}

$BlenderExe = if ($Action -eq "FetchAssets") { "" } else { Find-Blender $Blender }

if ($BlenderExe) {
    $version = (& $BlenderExe --version | Select-Object -First 1)
    if ($version -notmatch "Blender 5\.2\.") {
        throw "Expected Blender 5.2.x, found: $version"
    }
}

switch ($Action) {
    "Setup" {
        $root = Get-AssetRoot
        $library = Join-Path $root ([string]$Config.asset_library.path)
        $extensions = Join-Path $root ([string]$Config.paths.extensions)

        New-Item -ItemType Directory -Path $root,$library,$extensions -Force | Out-Null
        foreach ($catalog in $Config.asset_library.catalogs) {
            New-Item -ItemType Directory -Path (Join-Path $library $catalog) -Force | Out-Null
        }
        foreach ($name in @("downloads", "cache")) {
            New-Item -ItemType Directory -Path (Join-Path $root ([string]$Config.paths.$name)) -Force | Out-Null
        }

        & $BlenderExe --background --python $Helper -- configure --project-root $ProjectRoot --asset-root $root
        if ($LASTEXITCODE -ne 0) { throw "Blender configuration failed." }

        $repoId = [string]$Config.extension_repository.id
        $repos = (& $BlenderExe --command extension repo-list 2>&1 | Out-String)
        if ($repos -notmatch [regex]::Escape($repoId)) {
            & $BlenderExe --command extension repo-add $repoId --name ([string]$Config.extension_repository.name) --directory $extensions
            if ($LASTEXITCODE -ne 0) { throw "Could not add local extension repository." }
        }

        Set-Content -LiteralPath (Join-Path $root "README.txt") -Encoding UTF8 -Value "Rebuildable VTT Blender workspace. This directory is intentionally ignored by Git."
        Write-Host "Blender environment ready: $root"
    }

    "ListExtensions" { Invoke-Extension @("list") }
    "SyncExtensions" { Invoke-Extension @("sync") }
    "UpdateExtensions" { Invoke-Extension @("update", "-s") }

    "InstallExtension" {
        if ($Packages.Count -eq 0) { throw "-Packages is required." }
        Invoke-Extension @("install", "-s", "-e", ($Packages -join ","))
    }

    "InstallExtensionFile" {
        if ([string]::IsNullOrWhiteSpace($File)) { throw "-File is required." }
        $resolved = (Resolve-Path -LiteralPath $File).Path
        Invoke-Extension @("install-file", "-r", ([string]$Config.extension_repository.id), "-e", $resolved)
    }

    "RemoveExtension" {
        if ($Packages.Count -eq 0) { throw "-Packages is required." }
        Invoke-Extension @("remove", ($Packages -join ","))
    }

    "Export" {
        if ([string]::IsNullOrWhiteSpace($Blend) -or [string]::IsNullOrWhiteSpace($Output)) {
            throw "-Blend and -Output are required."
        }
        $blendPath = (Resolve-Path -LiteralPath $Blend).Path
        $outputPath = if ([System.IO.Path]::IsPathRooted($Output)) {
            [System.IO.Path]::GetFullPath($Output)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $Output))
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null

        $arguments = @($blendPath, "--background", "--python", $Helper, "--", "export", "--output", $outputPath)
        if ($Collection) { $arguments += @("--collection", $Collection) }
        if ($Animations) { $arguments += "--animations" }
        if ($KeepModifiers) { $arguments += "--keep-modifiers" }

        & $BlenderExe @arguments
        if ($LASTEXITCODE -ne 0) { throw "GLB export failed." }
    }

    "FetchAssets" {
        if ([string]::IsNullOrWhiteSpace($Manifest)) { throw "-Manifest is required." }
        $python = Get-Command python -ErrorAction SilentlyContinue
        if (-not $python) { throw "Python was not found on PATH." }
        $arguments = @($Helper, "fetch", (Resolve-Path -LiteralPath $Manifest).Path)
        if ($AssetRoot) { $arguments += @("--asset-root", (Get-AssetRoot)) }
        if ($Force) { $arguments += "--force" }
        & $python.Source @arguments
        if ($LASTEXITCODE -ne 0) { throw "Asset fetch failed." }
    }
}
