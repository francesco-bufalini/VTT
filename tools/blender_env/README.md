# VTT Blender environment

This folder makes the Blender side of the VTT reproducible without committing large third-party libraries.

## First setup

Use Blender 5.2 LTS and run:

    .\tools\blender_env\blender_env.ps1 -Action Setup

This creates the ignored local workspace .vtt_assets/, registers VTT Assets in Blender's Asset Browser, creates Architecture/Nature/Props/Materials/GeometryNodes/Environments folders, and registers a local extension repository named vtt_local.

The repository stores configuration and tooling; bulk libraries and caches stay local.

## Default environment-art rule

Use this order:

1. search the local Asset Browser and suitable providers;
2. reuse/kitbash existing assets;
3. use Geometry Nodes or a focused extension for repetition/scattering;
4. model from scratch only when a suitable reusable component does not exist.

The configured provider policy includes Poly Haven and ambientCG as preferred CC0 sources, with BlenderKit, Fab and Geo-Scatter available when their per-asset/commercial terms make sense.

## Extensions

    .\tools\blender_env\blender_env.ps1 -Action ListExtensions
    .\tools\blender_env\blender_env.ps1 -Action SyncExtensions
    .\tools\blender_env\blender_env.ps1 -Action InstallExtension -Packages package_id
    .\tools\blender_env\blender_env.ps1 -Action InstallExtensionFile -File C:\path\tool.zip
    .\tools\blender_env\blender_env.ps1 -Action RemoveExtension -Packages package_id

Install tools only when they materially help the current task. Third-party store credentials are never kept in Git.

## Lazy scene assets

A scene can declare direct-download dependencies in a small JSON manifest. The manifest records id, direct URL, local Asset Library path, license and optionally SHA256.

Fetch only what that scene requires:

    .\tools\blender_env\blender_env.ps1 -Action FetchAssets -Manifest blender\manifests\my_scene.assets.json

Authenticated stores should use their official client/extension instead of putting tokens in manifests.

## Blender -> Godot

Keep editable, project-specific source under blender/. For export, a collection named GAME_EXPORT is recommended:

    .\tools\blender_env\blender_env.ps1 -Action Export -Blend blender\arenas\kaos.blend -Collection GAME_EXPORT -Output assets\environments\kaos.glb

Static environment exports omit animations by default and apply modifiers. Gameplay collision, triggers, tokens, spells and encounter state stay in Godot. Distant unreachable scenery can be aggressively simplified or merged in Blender.
