#!/usr/bin/env python3
"""VTT Blender 5.2 environment helper.

Run "fetch" with normal Python. Run "configure" and "export" through Blender.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REQUIRED_VERSION = (5, 2)
LIBRARY_NAME = "VTT Assets"


def _bpy():
    try:
        import bpy
    except ImportError as exc:
        raise RuntimeError("This command must be run by Blender.") from exc
    return bpy


def _check_blender(bpy) -> None:
    if tuple(bpy.app.version[:2]) != REQUIRED_VERSION:
        raise RuntimeError(f"Expected Blender 5.2.x, found {bpy.app.version_string}")


def _configure(args: argparse.Namespace) -> int:
    bpy = _bpy()
    _check_blender(bpy)
    project_root = Path(args.project_root).resolve()
    asset_root = Path(args.asset_root).resolve()
    if not (project_root / "project.godot").exists():
        raise RuntimeError(f"Not a VTT project root: {project_root}")

    manifest = json.loads(
        (ROOT / "tools/blender_env/environment.json").read_text(encoding="utf-8")
    )
    library = asset_root / manifest["asset_library"]["path"]
    library.mkdir(parents=True, exist_ok=True)
    for name in manifest["asset_library"]["catalogs"]:
        (library / name).mkdir(parents=True, exist_ok=True)
    for key in ("downloads", "extensions", "cache"):
        (asset_root / manifest["paths"][key]).mkdir(parents=True, exist_ok=True)

    libraries = bpy.context.preferences.filepaths.asset_libraries
    match = next((item for item in libraries if item.name == LIBRARY_NAME), None)
    if match is None:
        bpy.ops.preferences.asset_library_add(
            directory=str(library),
            name=LIBRARY_NAME,
            type="LOCAL",
        )
    else:
        match.path = str(library)
    bpy.ops.wm.save_userpref()
    print(f"VTT Asset Library: {library}")
    return 0


def _select_collection(bpy, name: str) -> bool:
    if not name:
        return False
    collection = bpy.data.collections.get(name)
    if collection is None:
        raise RuntimeError(f"Collection not found: {name}")
    bpy.ops.object.select_all(action="DESELECT")
    selected = 0
    for obj in collection.all_objects:
        if obj.type in {"MESH", "EMPTY", "ARMATURE"} and not obj.hide_render:
            obj.select_set(True)
            selected += 1
    if not selected:
        raise RuntimeError(f"Collection has no exportable objects: {name}")
    return True


def _export(args: argparse.Namespace) -> int:
    bpy = _bpy()
    _check_blender(bpy)
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    use_selection = _select_collection(bpy, args.collection)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=use_selection,
        export_apply=not args.keep_modifiers,
        export_animations=args.animations,
    )
    print(f"Exported: {output}")
    return 0


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _fetch(args: argparse.Namespace) -> int:
    manifest_path = Path(args.manifest).resolve()
    asset_root = Path(args.asset_root or ROOT / ".vtt_assets/library").resolve()
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or not isinstance(data.get("assets"), list):
        raise RuntimeError("Invalid asset manifest")

    failures: list[str] = []
    for asset in data["assets"]:
        if asset.get("enabled", True) is False:
            continue
        asset_id = str(asset.get("id", "")).strip()
        url = str(asset.get("url", "")).strip()
        rel = str(asset.get("path", "")).strip()
        license_name = str(asset.get("license", "")).strip()
        expected = str(asset.get("sha256", "")).strip().lower()
        if not all((asset_id, url, rel, license_name)) or not url.startswith(
            ("https://", "http://")
        ):
            failures.append(f"invalid entry: {asset_id or asset!r}")
            continue

        destination = (asset_root / rel).resolve()
        try:
            destination.relative_to(asset_root)
            if (
                destination.exists()
                and not args.force
                and (not expected or _sha256(destination) == expected)
            ):
                print(f"skip  {asset_id}")
                continue

            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_suffix(destination.suffix + ".part")
            request = urllib.request.Request(
                url, headers={"User-Agent": "VTT-Blender/1.0"}
            )
            try:
                with urllib.request.urlopen(request, timeout=120) as response:
                    with temporary.open("wb") as out:
                        shutil.copyfileobj(response, out)
                temporary.replace(destination)
            finally:
                temporary.unlink(missing_ok=True)

            if expected and _sha256(destination) != expected:
                destination.unlink(missing_ok=True)
                raise RuntimeError("SHA256 mismatch")
            print(f"fetch {asset_id} [{license_name}]")
        except Exception as exc:
            failures.append(f"{asset_id}: {exc}")

    if failures:
        for failure in failures:
            print(f"ERROR {failure}", file=sys.stderr)
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    command = sub.add_parser("configure")
    command.add_argument("--project-root", required=True)
    command.add_argument("--asset-root", required=True)
    command.set_defaults(func=_configure)

    command = sub.add_parser("export")
    command.add_argument("--output", required=True)
    command.add_argument("--collection", default="")
    command.add_argument("--animations", action="store_true")
    command.add_argument("--keep-modifiers", action="store_true")
    command.set_defaults(func=_export)

    command = sub.add_parser("fetch")
    command.add_argument("manifest")
    command.add_argument("--asset-root", default="")
    command.add_argument("--force", action="store_true")
    command.set_defaults(func=_fetch)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    script_args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    raise SystemExit(main(script_args))
