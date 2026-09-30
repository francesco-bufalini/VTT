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
import shutil
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
    "tentacle",
    "tentacles",
    "wing",
    "wings",
    "arm",
    "arms",
    "leg",
    "legs",
    "tail",
    "weapon",
    "weapons",
    "marker",
    "base",
)
COMPLETE_MODEL_WORDS = (
    "final",
    "posed",
    "complete",
    "completed",
    "assembled",
    "merged",
    "whole",
    "full",
)
TECHNICAL_FOLDER_WORDS = {
    "blend",
    "blends",
    "model",
    "models",
    "obj",
    "objs",
    "source",
    "sources",
    "stl",
    "stls",
    "unsupported",
    "supported",
    "presupported",
    "pre-supported",
    "parts",
    "pieces",
    "print",
    "printing",
    "files",
}


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
    """Append the source scene hierarchy instead of flattening every object.

    Keeping the collection tree preserves author visibility choices: hidden
    printable pieces/variants stay hidden instead of becoming part of the VTT
    miniature.
    """
    with bpy.data.libraries.load(str(path), link=False) as (source, target):
        if not source.scenes:
            raise ValueError(f"No scene found in blend file: {path.name}")
        target.scenes = [source.scenes[0]]

    source_scene = target.scenes[0]
    if source_scene is None:
        raise ValueError(f"Could not load scene from blend file: {path.name}")

    destination = bpy.context.scene.collection

    for obj in source_scene.collection.objects:
        if obj.name not in destination.objects:
            destination.objects.link(obj)

    for child in source_scene.collection.children:
        if child.name not in destination.children:
            destination.children.link(child)

    # The appended hierarchy is now owned by the conversion scene too; remove
    # the temporary Scene datablock so it cannot keep stale duplicate objects
    # alive across hundreds of conversions.
    bpy.data.scenes.remove(source_scene)


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


def mesh_objects(visible_only: bool = False) -> list[bpy.types.Object]:
    objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not visible_only:
        return objects
    return [
        obj
        for obj in objects
        if not obj.hide_viewport
        and not obj.hide_render
        and obj.visible_get(view_layer=bpy.context.view_layer)
    ]


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


def direct_supported_files(folder: Path) -> list[Path]:
    return sorted(
        path
        for path in folder.iterdir()
        if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )


def supported_files(folder: Path) -> list[Path]:
    return sorted(
        path
        for path in folder.rglob("*")
        if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )


def _technical_folder_name(name: str) -> bool:
    normalized = slugify(name)
    tokens = set(normalized.split("_"))
    compact = normalized.replace("_", "-")
    return (
        compact in TECHNICAL_FOLDER_WORDS
        or bool(tokens.intersection(TECHNICAL_FOLDER_WORDS))
    )


def discover_packages(source_root: Path) -> list[Path]:
    """Find miniature folders at any depth without stopping at A/B/C grouping folders.

    A directory containing model files directly is a package.  A creature folder
    whose only model-bearing children are technical folders (STL, Supported,
    Parts, Blend, ...) is also kept as one package so print variants are not
    mistaken for separate creatures.
    """
    packages: list[Path] = []

    def walk(folder: Path, is_root: bool = False) -> None:
        direct = direct_supported_files(folder)
        children = [
            child
            for child in sorted(folder.iterdir())
            if child.is_dir() and supported_files(child)
        ]

        if direct:
            packages.append(folder)
            return

        if children and all(_technical_folder_name(child.name) for child in children):
            packages.append(folder)
            return

        for child in children:
            walk(child)

    walk(source_root, is_root=True)

    # Preserve order while removing accidental duplicates from unusual trees.
    unique: list[Path] = []
    seen: set[Path] = set()
    for package in packages:
        resolved = package.resolve()
        if resolved not in seen:
            seen.add(resolved)
            unique.append(package)
    return unique


def _contains_word(text: str, word: str) -> bool:
    return re.search(r"(^|[^a-z0-9])" + re.escape(word) + r"([^a-z0-9]|$)", text) is not None


def is_print_part(path: Path, package_name: str) -> bool:
    """Identify separate printable pieces, not complete authoring scenes.

    In these miniature packs, split print parts are primarily STL files.
    A .blend can legitimately contain objects named Body/Base/Marker together
    with the complete assembled miniature, cameras and lights, so its filename
    alone must never make it a "print part".
    """
    if path.suffix.lower() == ".blend":
        return False

    name = path.stem.lower()
    if slugify(name) == slugify(package_name):
        return False
    if any(_contains_word(name, word) for word in COMPLETE_MODEL_WORDS):
        return False
    return any(_contains_word(name, word) for word in AUXILIARY_WORDS)


def source_score(path: Path, package_name: str) -> int:
    name = path.stem.lower()
    package = package_name.lower()
    suffix = path.suffix.lower()

    # Scene/assembled formats win decisively over raw printable STL pieces.
    score = {
        ".blend": 1200,
        ".glb": 1100,
        ".gltf": 1050,
        ".fbx": 950,
        ".obj": 900,
        ".stl": 200,
    }.get(suffix, 0)

    if _contains_word(name, "final"):
        score += 1500
    elif _contains_word(name, "posed"):
        score += 1400
    elif any(
        _contains_word(name, word)
        for word in ("complete", "completed", "assembled", "merged", "whole", "full")
    ):
        score += 1300

    if slugify(name) == slugify(package):
        score += 800
    if _contains_word(name, "rigged"):
        score += 600
    if _contains_word(name, "sculpted"):
        score -= 400

    if is_print_part(path, package_name):
        score -= 1400
    return score


def choose_main_source(package: Path) -> Path:
    files = supported_files(package)
    if not files:
        raise ValueError("No supported model files")

    # Marker/base STL files are references, never the creature itself.  First
    # determine how many actual model candidates remain after removing them.
    creature_files = [
        path
        for path in files
        if not (
            path.suffix.lower() == ".stl"
            and is_platform_reference_name(path.stem)
        )
    ]

    if not creature_files:
        raise ValueError(
            "Only a base/size marker was found; no creature model to convert"
        )

    # A filename such as Body.stl or Tentacles.stl does not imply that it is a
    # fragment when it is the only non-marker model in the package.  In that
    # case it is necessarily the best available representation of the creature.
    if len(creature_files) == 1:
        return creature_files[0]

    ranked = sorted(
        creature_files,
        key=lambda path: (source_score(path, package.name), path.stat().st_size),
        reverse=True,
    )
    chosen = ranked[0]

    # With several creature files present, keep the conservative behaviour:
    # do not silently choose one head/body/tentacle/etc. from a split print set.
    if is_print_part(chosen, package.name):
        raise ValueError(
            "Only separated printable parts were found; no complete/posed model "
            "could be identified for this miniature"
        )
    return chosen


def is_platform_reference_name(text: str) -> bool:
    name = text.lower().strip()

    # "Organic Base Sphere" is a common sculpt/object name in authored .blend
    # files.  Despite containing the word "base", it is real miniature
    # geometry, not a D&D footprint marker, and must remain exportable.
    if re.fullmatch(r"organic\s+base\s+sphere(?:\.\d+)?", name):
        return False

    if any(
        _contains_word(name, word)
        for word in ("base", "marker", "platform", "stand")
    ):
        return True

    if size_from_text(name) is None:
        return False

    # Many authored Blender files use the D&D footprint object itself as
    # "Small Creature", "Large Creature.001", etc.  These are legitimate
    # in-scene bases and must be recognized (and kept in the exported model).
    if re.fullmatch(
        r"(tiny|small|medium|large|huge|gargantuan)\s+creature(?:\.\d+)?",
        name,
    ):
        return True

    # Also support the common flying/floating footprint naming convention.
    return bool(
        re.search(
            r"\b(tiny|small|medium|large|huge|gargantuan)\b"
            r".*\bcreature\b.*\b(flying|floating)\b",
            name,
        )
    )


def base_candidate_score(obj: bpy.types.Object) -> int:
    name = obj.name.lower()
    if not is_platform_reference_name(name):
        return 0

    score = 0
    if "marker" in name:
        score += 50
    if "base" in name:
        score += 40
    if "platform" in name or "stand" in name:
        score += 40
    if "flying" in name:
        score += 30
    if "size" in name:
        score += 10
    if size_from_text(name) is not None:
        score += 80

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
    if not is_platform_reference_name(name):
        return 0

    score = 0
    if "marker" in name:
        score += 50
    if "base" in name:
        score += 40
    if "platform" in name or "stand" in name:
        score += 40
    if "flying" in name:
        score += 30
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
) -> tuple[Vector, Vector, str, list[bpy.types.Object]]:
    """Resolve scale/ground reference and identify external STL-only helpers.

    A base/marker that already belongs to the chosen source scene (especially a
    .blend miniature) is part of the authored miniature and must stay exported.
    Only a *separate STL file* imported solely as a size/flying marker is treated
    as calibration-only geometry and removed from the final OBJ.
    """
    scene_references = [
        obj for obj in objects if base_candidate_score(obj) > 0
    ]
    scene_base = find_scene_base(scene_references)
    if scene_base is not None:
        low, high = object_bounds(scene_base)
        # Keep every object already present in the main .blend/source scene.
        return low, high, f"object:{scene_base.name}", []

    external = choose_external_base(package, main_source)
    if external is not None:
        added = import_external_base(external)
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
            reference_only = added if external.suffix.lower() == ".stl" else []
            return low, high, f"file:{external.name}", reference_only

    # No explicit authored base/marker was found.  Do not fail and do not try
    # to infer a D&D size from the creature's lowest geometry: use a virtual
    # standard Medium base instead.  These packs are authored in tabletop-mm
    # scale, so 25.4 source units correspond to a 1-cell Medium footprint.
    scene_low, scene_high = world_bounds(objects)
    diameter = STANDARD_BASE_DIAMETERS_MM["Medium"]
    radius = diameter * 0.5
    center_x = (scene_low.x + scene_high.x) * 0.5
    center_y = (scene_low.y + scene_high.y) * 0.5
    base_low = Vector((center_x - radius, center_y - radius, scene_low.z))
    base_high = Vector((center_x + radius, center_y + radius, scene_low.z))

    print(
        "WARNING: no base/marker found; using Medium 1x1 fallback "
        f"({diameter:g} source units)"
    )
    return base_low, base_high, "fallback:Medium (no base found)", []


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


def cleanup_stale_generated(project_root: Path, tokens: list[dict]) -> None:
    """Remove only converter-owned artifacts that disappeared from the new scan."""
    manifest_path = project_root / "assets" / "tokens" / "token_library.json"
    if not manifest_path.is_file():
        return

    try:
        previous = json.loads(manifest_path.read_text(encoding="utf-8"))
    except Exception:
        return

    current_ids = {str(token.get("id", "")) for token in tokens}
    for old in previous.get("tokens", []):
        old_id = str(old.get("id", ""))
        if not old_id or old_id in current_ids:
            continue

        obj_res = str(old.get("obj", ""))
        scene_res = str(old.get("scene", ""))

        if obj_res.startswith("res://assets/tokens/generated/"):
            obj_path = project_root / obj_res.removeprefix("res://")
            generated_root = (project_root / "assets" / "tokens" / "generated").resolve()
            package_dir = obj_path.parent.resolve()
            if generated_root in package_dir.parents and package_dir.is_dir():
                shutil.rmtree(package_dir, ignore_errors=True)

        if scene_res.startswith("res://assets/tokens/scenes/"):
            scene_path = project_root / scene_res.removeprefix("res://")
            if scene_path.is_file():
                scene_path.unlink()


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

    all_objects = mesh_objects()
    if not all_objects:
        raise ValueError("Main source contains no mesh objects")

    # Hidden printable parts/alternate variants must not determine the token
    # ground plane if they are not exported. Resolve the base from the same
    # visible geometry that will become the VTT miniature.
    visible_main_objects = mesh_objects(visible_only=True)
    if not visible_main_objects:
        raise ValueError(
            "The selected complete model has no visible mesh objects to export"
        )

    if all(base_candidate_score(obj) > 0 for obj in visible_main_objects):
        raise ValueError(
            "The selected source contains only base/size-marker geometry; "
            "no creature mesh was found"
        )

    base_low, base_high, base_reference, reference_objects = resolve_base(
        package, main_source, visible_main_objects
    )
    reference_ids = {obj.as_pointer() for obj in reference_objects}
    objects = [
        obj
        for obj in mesh_objects(visible_only=True)
        if obj.as_pointer() not in reference_ids
    ]
    if not objects:
        raise ValueError(
            "The selected complete model has no visible creature mesh after "
            "excluding base/marker reference geometry"
        )

    if reference_objects:
        print(
            "Separate STL reference only (not exported): "
            + ", ".join(obj.name for obj in reference_objects)
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

    print(f"Miniature packages discovered: {len(packages)}")

    tokens: list[dict] = []
    failures: list[dict] = []

    for package in packages:
        relative_package = (
            package.relative_to(source_root).as_posix()
            if package != source_root
            else package.name
        )
        print(f"\n=== {relative_package} ===")
        try:
            tokens.append(process_package(package, source_root, project_root))
        except Exception as exc:
            failures.append({"package": package.name, "error": str(exc)})
            print(f"FAILED: {package.name}: {exc}")

    if not tokens:
        print("ERROR: all conversions failed")
        return 4

    default_token = choose_default(tokens, args.default)
    cleanup_stale_generated(project_root, tokens)
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
