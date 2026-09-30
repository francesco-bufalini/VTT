#!/usr/bin/env python3
"""Batch token converter for the VTT project.

Run through Blender:
  blender --background --python tools/token_converter/convert_tokens.py -- --source SOURCE --project-root PROJECT

The converter accepts .blend/.stl/.obj/.fbx/.glb/.gltf, normalizes the miniature,
exports OBJ/MTL, creates ready-to-drag token scenes, and writes a token manifest.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


SUPPORTED_EXTENSIONS = {".blend", ".stl", ".obj", ".fbx", ".glb", ".gltf"}
DEFAULT_TARGET_HEIGHT = 1.8


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--default", default="")
    parser.add_argument("--target-height", type=float, default=DEFAULT_TARGET_HEIGHT)
    return parser.parse_args(argv)


def slugify(value: str) -> str:
    value = value.lower().replace("\\", "/")
    value = re.sub(r"[^a-z0-9]+", "_", value).strip("_")
    return value or "token"


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def import_blend(path: Path) -> None:
    with bpy.data.libraries.load(str(path), link=False) as (source, target):
        target.objects = list(source.objects)
    for obj in target.objects:
        if obj is not None and obj.name not in bpy.context.scene.collection.objects:
            bpy.context.scene.collection.objects.link(obj)


def import_source(path: Path) -> None:
    suffix = path.suffix.lower()
    if suffix == ".blend":
        import_blend(path)
    elif suffix == ".stl":
        if hasattr(bpy.ops.wm, "stl_import"):
            bpy.ops.wm.stl_import(filepath=str(path))
        else:
            bpy.ops.import_mesh.stl(filepath=str(path))
    elif suffix == ".obj":
        if hasattr(bpy.ops.wm, "obj_import"):
            bpy.ops.wm.obj_import(filepath=str(path))
        else:
            bpy.ops.import_scene.obj(filepath=str(path))
    elif suffix == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(path))
    elif suffix in {".glb", ".gltf"}:
        bpy.ops.import_scene.gltf(filepath=str(path))
    else:
        raise ValueError(f"Unsupported source format: {suffix}")


def mesh_objects() -> list[bpy.types.Object]:
    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]


def world_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    low = Vector((math.inf, math.inf, math.inf))
    high = Vector((-math.inf, -math.inf, -math.inf))
    found = False
    for obj in objects:
        evaluated = obj.evaluated_get(depsgraph)
        for corner in evaluated.bound_box:
            point = evaluated.matrix_world @ Vector(corner)
            low.x = min(low.x, point.x)
            low.y = min(low.y, point.y)
            low.z = min(low.z, point.z)
            high.x = max(high.x, point.x)
            high.y = max(high.y, point.y)
            high.z = max(high.z, point.z)
            found = True
    if not found:
        raise ValueError("No mesh bounds found")
    return low, high


def normalize(objects: list[bpy.types.Object], target_height: float) -> dict[str, float]:
    low, high = world_bounds(objects)
    source_height = high.z - low.z
    if source_height <= 1.0e-9:
        raise ValueError("Miniature has zero height")

    scale = target_height / source_height
    center_x = (low.x + high.x) * 0.5
    center_y = (low.y + high.y) * 0.5

    transform = Matrix.Scale(scale, 4) @ Matrix.Translation(
        Vector((-center_x, -center_y, -low.z))
    )
    for obj in objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.matrix_world = transform @ obj.matrix_world

    after_low, after_high = world_bounds(objects)
    return {
        "source_height": source_height,
        "scale_factor": scale,
        "width": after_high.x - after_low.x,
        "depth": after_high.y - after_low.y,
        "height": after_high.z - after_low.z,
    }


def export_obj(objects: list[bpy.types.Object], destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]

    if hasattr(bpy.ops.wm, "obj_export"):
        operator = bpy.ops.wm.obj_export
        supported = set(operator.get_rna_type().properties.keys())
        kwargs = {
            "filepath": str(destination),
            "export_selected_objects": True,
            "apply_modifiers": True,
            "export_materials": True,
            "forward_axis": "NEGATIVE_Z",
            "up_axis": "Y",
            "path_mode": "COPY",
        }
        operator(**{key: value for key, value in kwargs.items() if key in supported})
    else:
        bpy.ops.export_scene.obj(
            filepath=str(destination),
            use_selection=True,
            use_mesh_modifiers=True,
            use_materials=True,
            axis_forward="-Z",
            axis_up="Y",
            path_mode="COPY",
        )


def write_wrapper_scene(project_root: Path, slug: str, obj_res_path: str) -> str:
    scenes_dir = project_root / "assets" / "tokens" / "scenes"
    scenes_dir.mkdir(parents=True, exist_ok=True)
    scene_path = scenes_dir / f"{slug}_token.tscn"
    scene_text = (
        '[gd_scene load_steps=2 format=3]\n\n'
        '[ext_resource type="PackedScene" path="res://token.tscn" id="1_base"]\n\n'
        f'[node name="{slug}_token" instance=ExtResource("1_base")]\n'
        f'visual_asset_path = "{obj_res_path}"\n'
    )
    scene_path.write_text(scene_text, encoding="utf-8")
    return f"res://assets/tokens/scenes/{scene_path.name}"


def discover(source_root: Path) -> list[Path]:
    return sorted(
        path
        for path in source_root.rglob("*")
        if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )


def choose_default(tokens: list[dict], requested: str) -> str:
    if not tokens:
        return ""
    request = requested.strip().lower()
    if not request:
        return tokens[0]["obj"]

    exact = []
    partial = []
    for token in tokens:
        candidates = {
            token["id"].lower(),
            token["source"].lower(),
            Path(token["source"]).name.lower(),
            Path(token["source"]).stem.lower(),
        }
        if request in candidates:
            exact.append(token)
        elif any(request in candidate for candidate in candidates):
            partial.append(token)

    chosen = exact[0] if exact else (partial[0] if partial else None)
    if chosen is None:
        raise ValueError(f'Default token "{requested}" did not match any converted file')
    return chosen["obj"]


def main() -> int:
    args = parse_args()
    source_root = Path(args.source).expanduser().resolve()
    project_root = Path(args.project_root).expanduser().resolve()

    if not source_root.is_dir():
        print(f"ERROR: source folder not found: {source_root}")
        return 2
    if not (project_root / "project.godot").is_file():
        print(f"ERROR: project.godot not found under: {project_root}")
        return 2
    if args.target_height <= 0:
        print("ERROR: --target-height must be > 0")
        return 2

    output_root = project_root / "assets" / "tokens" / "generated"
    output_root.mkdir(parents=True, exist_ok=True)

    sources = discover(source_root)
    if not sources:
        print(f"ERROR: no supported miniature files found under {source_root}")
        return 3

    tokens: list[dict] = []
    failures: list[dict] = []
    used_slugs: set[str] = set()

    for source in sources:
        relative = source.relative_to(source_root)
        base_slug = slugify(str(relative.with_suffix("")))
        slug = base_slug
        suffix_index = 2
        while slug in used_slugs:
            slug = f"{base_slug}_{suffix_index}"
            suffix_index += 1
        used_slugs.add(slug)

        print(f"\n=== {relative} -> {slug} ===")
        try:
            clear_scene()
            import_source(source)
            objects = mesh_objects()
            if not objects:
                raise ValueError("No mesh objects found")

            metrics = normalize(objects, args.target_height)
            token_dir = output_root / slug
            obj_path = token_dir / f"{slug}.obj"
            export_obj(objects, obj_path)

            obj_res = f"res://assets/tokens/generated/{slug}/{slug}.obj"
            scene_res = write_wrapper_scene(project_root, slug, obj_res)
            tokens.append(
                {
                    "id": slug,
                    "source": relative.as_posix(),
                    "obj": obj_res,
                    "scene": scene_res,
                    "height": round(metrics["height"], 6),
                    "width": round(metrics["width"], 6),
                    "depth": round(metrics["depth"], 6),
                    "scale_factor": metrics["scale_factor"],
                    "source_height": metrics["source_height"],
                }
            )
            print(
                "OK: "
                f"{obj_res} | H={metrics['height']:.3f}, "
                f"W={metrics['width']:.3f}, D={metrics['depth']:.3f}, "
                f"scale={metrics['scale_factor']:.8g}"
            )
        except Exception as exc:
            failures.append({"source": relative.as_posix(), "error": str(exc)})
            print(f"FAILED: {relative}: {exc}")

    if not tokens:
        print("ERROR: all conversions failed")
        return 4

    default_obj = choose_default(tokens, args.default)
    manifest_path = project_root / "assets" / "tokens" / "token_library.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest = {
        "version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "target_height_godot_units": args.target_height,
        "default": default_obj,
        "tokens": tokens,
        "failures": failures,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(f"\nConverted: {len(tokens)}")
    print(f"Failed:    {len(failures)}")
    print(f"Default:   {default_obj}")
    print(f"Manifest:  {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
