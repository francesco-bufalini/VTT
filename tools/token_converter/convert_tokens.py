#!/usr/bin/env python3
"""Convert downloaded tabletop miniatures into ready-to-use Godot tokens.

The physical/author scale is not normalized from character height.  The base is
the calibration reference: its diameter is mapped to the D&D footprint in grid
cells.  This keeps long tails, wings and weapons free to extend outside the
occupied squares without changing the token size.

Run through Blender:
  blender --background --python tools/token_converter/convert_tokens.py -- \
    --source "C:/Downloads/Miniatures" --project-root "C:/Projects/VTT"
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
SIZE_TO_FOOTPRINT = {
    "Tiny": 0.5,
    "Small": 1.0,
    "Medium": 1.0,
    "Large": 2.0,
    "Huge": 3.0,
    "Gargantuan": 4.0,
}
# Used only when a base has no explicit D&D size in its name.
STANDARD_BASE_DIAMETERS_MM = {
    "Tiny": 12.7,
    "Medium": 25.4,
    "Large": 50.8,
    "Huge": 76.2,
    "Gargantuan": 101.6,
}
AUXILIARY_WORDS = (
    "presupported",
    "pre-supported",
    "supported",
    "support",
    "head",
    "body",
    "sculpted",
    "marker",
    "base",
)


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        required=True,
        help="One miniature folder, or a parent folder containing miniature folders.",
    )
    parser.add_argument("--project-root", required=True)
    parser.add_argument(
        "--default",
        default="",
        help="Token id/name/substring to use instead of the procedural default token.",
    )
    return parser.parse_args(argv)


def slugify(value: str) -> str:
    value = value.lower().replace("\\", "/")
    value = re.sub(r"[^a-z0-9]+", "_", value).strip("_")
    return value or "token"


def size_from_text(text: str) -> tuple[str, float] | None:
    lowered = text.lower()
    for size_name, footprint in SIZE_TO_FOOTPRINT.items():
        if re.search(r"\b" + re.escape(size_name.lower()) + r"\b", lowered):
            return size_name, footprint
    return None


def size_from_diameter(diameter: float) -> tuple[str, float]:
    if diameter <= 0.0:
        raise ValueError("Base diameter must be positive")
    # Source STL/OBJ miniature packs normally use millimetres.  Choose the
    # closest tabletop base only as a fallback when there is no named size.
    size_name = min(
        STANDARD_BASE_DIAMETERS_MM,
        key=lambda name: abs(
            math.log(diameter / STANDARD_BASE_DIAMETERS_MM[name])
        ),
    )
    return size_name, SIZE_TO_FOOTPRINT[size_name]


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


def object_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    low = Vector((math.inf, math.inf, math.inf))
    high = Vector((-math.inf, -math.inf, -math.inf))
    for corner in evaluated.bound_box:
        point = evaluated.matrix_world @ Vector(corner)
        low.x = min(low.x, point.x)
        low.y = min(low.y, point.y)
        low.z = min(low.z, point.z)
        high.x = max(high.x, point.x)
        high.y = max(high.y, point.y)
        high.z = max(high.z, point.z)
    return low, high


def world_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    low = Vector((math.inf, math.inf, math.inf))
    high = Vector((-math.inf, -math.inf, -math.inf))
    for obj in objects:
        obj_low, obj_high = object_bounds(obj)
        for axis in range(3):
            low[axis] = min(low[axis], obj_low[axis])
            high[axis] = max(high[axis], obj_high[axis])
    if not objects:
        raise ValueError("No mesh objects found")
    return low, high


def supported_files(folder: Path) -> list[Path]:
    return sorted(
        path
        for path in folder.rglob("*")
        if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )


def discover_packages(source_root: Path) -> list[Path]:
    direct = [
        p
        for p in source_root.iterdir()
        if p.is_file() and p.suffix.lower() in SUPPORTED_EXTENSIONS
    ]
    children = [
        p
        for p in sorted(source_root.iterdir())
        if p.is_dir() and supported_files(p)
    ]
    # If the chosen folder already contains miniature files, it is one package.
    # Otherwise each immediate child is treated as one miniature package.
    if direct:
        return [source_root]
    return children


def source_score(path: Path, package_name: str) -> int:
    name = path.stem.lower()
    package = package_name.lower()
    suffix = path.suffix.lower()
    score = {
        ".blend": 120,
        ".glb": 110,
        ".gltf": 105,
        ".obj": 100,
        ".stl": 90,
        ".fbx": 95,
    }.get(suffix, 0)

    if "final" in name:
        score += 400
    if "posed" in name:
        score += 300
    if "rigged" in name:
        score += 100
    if slugify(name) == slugify(package):
        score += 250

    for word in AUXILIARY_WORDS:
        if word in name:
            score -= 600
    return score


def choose_main_source(package: Path) -> Path:
    files = supported_files(package)
    if not files:
        raise ValueError("No supported model files")
    return max(files, key=lambda path: (source_score(path, package.name), path.stat().st_size))


def base_candidate_score(obj: bpy.types.Object) -> int:
    name = obj.name.lower()
    score = 0
    if "marker" in name:
        score += 50
    if "base" in name:
        score += 40
    if "size" in name:
        score += 10
    if size_from_text(name) is not None:
        score += 80
    if score <= 0:
        return 0

    low, high = object_bounds(obj)
    x_extent = high.x - low.x
    y_extent = high.y - low.y
    if min(x_extent, y_extent) > 0.0:
        ratio = max(x_extent, y_extent) / min(x_extent, y_extent)
        if ratio <= 1.25:
            score += 20
    return score


def find_scene_base(objects: list[bpy.types.Object]) -> bpy.types.Object | None:
    candidates = [
        (base_candidate_score(obj), obj)
        for obj in objects
        if base_candidate_score(obj) > 0
    ]
    if not candidates:
        return None
    candidates.sort(
        key=lambda item: (
            item[0],
            max(
                object_bounds(item[1])[1].x - object_bounds(item[1])[0].x,
                object_bounds(item[1])[1].y - object_bounds(item[1])[0].y,
            ),
        ),
        reverse=True,
    )
    return candidates[0][1]


def base_file_score(path: Path) -> int:
    name = path.stem.lower()
    score = 0
    if "marker" in name:
        score += 50
    if "base" in name:
        score += 40
    if "size" in name:
        score += 10
    if size_from_text(name) is not None:
        score += 80
    if "presupported" in name or "supported" in name:
        score -= 100
    return score


def choose_external_base(package: Path, main_source: Path) -> Path | None:
    candidates = [
        path
        for path in supported_files(package)
        if path != main_source and base_file_score(path) > 0
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda path: (base_file_score(path), path.stat().st_size))


def import_external_base(path: Path) -> list[bpy.types.Object]:
    before = {obj.as_pointer() for obj in bpy.context.scene.objects}
    import_source(path)
    return [
        obj
        for obj in mesh_objects()
        if obj.as_pointer() not in before
    ]


def low_band_base_bounds(
    objects: list[bpy.types.Object],
) -> tuple[Vector, Vector] | None:
    scene_low, scene_high = world_bounds(objects)
    height = scene_high.z - scene_low.z
    if height <= 0.0:
        return None
    band_top = scene_low.z + height * 0.08

    low = Vector((math.inf, math.inf, math.inf))
    high = Vector((-math.inf, -math.inf, -math.inf))
    found = False
    depsgraph = bpy.context.evaluated_depsgraph_get()

    for obj in objects:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        try:
            step = max(1, len(mesh.vertices) // 50000)
            for index in range(0, len(mesh.vertices), step):
                point = evaluated.matrix_world @ mesh.vertices[index].co
                if point.z > band_top:
                    continue
                for axis in range(3):
                    low[axis] = min(low[axis], point[axis])
                    high[axis] = max(high[axis], point[axis])
                found = True
        finally:
            evaluated.to_mesh_clear()

    return (low, high) if found else None


def resolve_base(
    package: Path,
    main_source: Path,
    objects: list[bpy.types.Object],
) -> tuple[list[bpy.types.Object], Vector, Vector, str]:
    scene_base = find_scene_base(objects)
    if scene_base is not None:
        low, high = object_bounds(scene_base)
        return objects, low, high, f"object:{scene_base.name}"

    external = choose_external_base(package, main_source)
    if external is not None:
        added = import_external_base(external)
        objects = mesh_objects()
        external_base = find_scene_base(added)
        if external_base is None and added:
            external_base = max(
                added,
                key=lambda obj: max(
                    object_bounds(obj)[1].x - object_bounds(obj)[0].x,
                    object_bounds(obj)[1].y - object_bounds(obj)[0].y,
                ),
            )
        if external_base is not None:
            low, high = object_bounds(external_base)
            return objects, low, high, f"file:{external.name}"

    fallback = low_band_base_bounds(objects)
    if fallback is not None:
        return objects, fallback[0], fallback[1], "geometry:lowest_8_percent"

    raise ValueError("Could not identify the miniature base")


def normalize_from_base(
    objects: list[bpy.types.Object],
    base_low: Vector,
    base_high: Vector,
    footprint: float,
) -> dict[str, float]:
    base_x = base_high.x - base_low.x
    base_y = base_high.y - base_low.y
    base_diameter = max(base_x, base_y)
    if base_diameter <= 1.0e-9:
        raise ValueError("Detected base has zero diameter")

    scale = footprint / base_diameter
    center_x = (base_low.x + base_high.x) * 0.5
    center_y = (base_low.y + base_high.y) * 0.5
    ground_z = base_low.z

    transform = Matrix.Scale(scale, 4) @ Matrix.Translation(
        Vector((-center_x, -center_y, -ground_z))
    )
    for obj in objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.matrix_world = transform @ obj.matrix_world

    output_low, output_high = world_bounds(objects)
    return {
        "base_diameter_source": base_diameter,
        "scale_factor": scale,
        "width": output_high.x - output_low.x,
        "depth": output_high.y - output_low.y,
        "height": output_high.z - min(0.0, output_low.z),
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


def write_wrapper_scene(
    project_root: Path,
    slug: str,
    obj_res_path: str,
    size_name: str,
    footprint: float,
    height_cells: float,
) -> str:
    scenes_dir = project_root / "assets" / "tokens" / "scenes"
    scenes_dir.mkdir(parents=True, exist_ok=True)
    scene_path = scenes_dir / f"{slug}_token.tscn"
    scene_text = (
        '[gd_scene load_steps=2 format=3]\n\n'
        '[ext_resource type="PackedScene" path="res://token.tscn" id="1_base"]\n\n'
        f'[node name="{slug}_token" instance=ExtResource("1_base")]\n'
        f'visual_asset_path = "{obj_res_path}"\n'
        f'default_size_name = "{size_name}"\n'
        f'default_footprint_cells = {footprint:.6f}\n'
        f'token_height_cells = {height_cells:.6f}\n'
    )
    scene_path.write_text(scene_text, encoding="utf-8")
    return f"res://assets/tokens/scenes/{scene_path.name}"


def choose_default(tokens: list[dict], requested: str) -> dict:
    if not tokens:
        return {}
    request = requested.strip().lower()
    if not request:
        return tokens[0]

    exact: list[dict] = []
    partial: list[dict] = []
    for token in tokens:
        candidates = {
            str(token.get("id", "")).lower(),
            str(token.get("name", "")).lower(),
            str(token.get("source", "")).lower(),
            Path(str(token.get("source", ""))).stem.lower(),
        }
        if request in candidates:
            exact.append(token)
        elif any(request in candidate for candidate in candidates):
            partial.append(token)

    chosen = exact[0] if exact else (partial[0] if partial else None)
    if chosen is None:
        raise ValueError(f'Default token "{requested}" did not match any converted package')
    return chosen


def process_package(
    package: Path,
    source_root: Path,
    project_root: Path,
) -> dict:
    clear_scene()
    main_source = choose_main_source(package)
    print(f"Source model: {main_source.name}")
    import_source(main_source)

    objects = mesh_objects()
    if not objects:
        raise ValueError("Main source contains no mesh objects")

    objects, base_low, base_high, base_reference = resolve_base(
        package, main_source, objects
    )
    diameter = max(base_high.x - base_low.x, base_high.y - base_low.y)

    size_hint = (
        size_from_text(base_reference)
        or size_from_text(package.name)
        or size_from_text(main_source.stem)
    )
    size_name, footprint = (
        size_hint if size_hint is not None else size_from_diameter(diameter)
    )

    metrics = normalize_from_base(objects, base_low, base_high, footprint)
    slug = slugify(package.name)
    token_dir = project_root / "assets" / "tokens" / "generated" / slug
    obj_path = token_dir / f"{slug}.obj"
    export_obj(objects, obj_path)

    obj_res = f"res://assets/tokens/generated/{slug}/{slug}.obj"
    height_cells = max(float(metrics["height"]), 0.1)
    scene_res = write_wrapper_scene(
        project_root,
        slug,
        obj_res,
        size_name,
        footprint,
        height_cells,
    )

    source_label = (
        main_source.relative_to(source_root).as_posix()
        if source_root in main_source.parents
        else main_source.name
    )
    profile = {
        "id": slug,
        "name": package.name,
        "source": source_label,
        "obj": obj_res,
        "scene": scene_res,
        "size_name": size_name,
        "footprint": footprint,
        "height_cells": round(height_cells, 6),
        "width_cells": round(float(metrics["width"]), 6),
        "depth_cells": round(float(metrics["depth"]), 6),
        "base_reference": base_reference,
        "base_diameter_source": float(metrics["base_diameter_source"]),
        "scale_factor": float(metrics["scale_factor"]),
    }

    print(
        "Base: "
        f"{base_reference} | diameter={metrics['base_diameter_source']:.4f} "
        f"-> {size_name} ({footprint:g} cells)"
    )
    print(
        "Godot bounds: "
        f"W={metrics['width']:.3f}, D={metrics['depth']:.3f}, "
        f"H={height_cells:.3f} cells"
    )
    print(f"OBJ: {obj_res}")
    return profile


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

    packages = discover_packages(source_root)
    if not packages:
        print(f"ERROR: no miniature packages found under {source_root}")
        return 3

    tokens: list[dict] = []
    failures: list[dict] = []

    for package in packages:
        print(f"\n=== {package.name} ===")
        try:
            tokens.append(process_package(package, source_root, project_root))
        except Exception as exc:
            failures.append({"package": package.name, "error": str(exc)})
            print(f"FAILED: {package.name}: {exc}")

    if not tokens:
        print("ERROR: all conversions failed")
        return 4

    default_token = choose_default(tokens, args.default)
    manifest_path = project_root / "assets" / "tokens" / "token_library.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest = {
        "version": 2,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "default_id": default_token["id"],
        "default": default_token,
        "tokens": tokens,
        "failures": failures,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(f"\nConverted: {len(tokens)}")
    print(f"Failed:    {len(failures)}")
    print(
        "Default:   "
        f"{default_token['name']} "
        f"({default_token['size_name']}, {default_token['footprint']:g} cells)"
    )
    print(f"Manifest:  {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
