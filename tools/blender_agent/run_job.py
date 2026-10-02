#!/usr/bin/env python3
"""Execute a constrained Blender job for the VTT repository.

Run through Blender:
  blender --background --python tools/blender_agent/run_job.py -- --job blender/jobs/example.json --project-root .
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import re
import sys
import traceback
from pathlib import Path

import bpy


REQUIRED_VERSION = (5, 2)


def project_path(root: Path, value: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        path = root / path
    return path.resolve()


def vec3(value, default=(0.0, 0.0, 0.0)):
    if value is None:
        return default
    if not isinstance(value, list) or len(value) != 3:
        raise ValueError(f"Expected vec3, got {value!r}")
    return tuple(float(v) for v in value)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def add_cube(op: dict) -> None:
    bpy.ops.mesh.primitive_cube_add(location=vec3(op.get("location")))
    obj = bpy.context.object
    obj.name = op.get("name", "Cube")
    obj.scale = vec3(op.get("scale"), (1.0, 1.0, 1.0))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def add_plane(op: dict) -> None:
    size = float(op.get("size", 10.0))
    bpy.ops.mesh.primitive_plane_add(size=size, location=vec3(op.get("location")))
    obj = bpy.context.object
    obj.name = op.get("name", "Ground")


def add_sun(op: dict) -> None:
    data = bpy.data.lights.new(op.get("name", "Sun"), type="SUN")
    data.energy = float(op.get("energy", 3.0))
    obj = bpy.data.objects.new(op.get("name", "Sun"), data)
    bpy.context.scene.collection.objects.link(obj)
    rot = vec3(op.get("rotation_degrees"), (35.0, 0.0, -35.0))
    obj.rotation_euler = tuple(math.radians(v) for v in rot)


def set_camera(op: dict) -> None:
    data = bpy.data.cameras.new(op.get("name", "AgentCamera"))
    obj = bpy.data.objects.new(op.get("name", "AgentCamera"), data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = vec3(op.get("location"), (10.0, -10.0, 8.0))
    target = vec3(op.get("look_at"), (0.0, 0.0, 0.0))
    direction = mathutils.Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    data.lens = float(op.get("lens", 50.0))
    bpy.context.scene.camera = obj


def ensure_default_camera_and_light() -> None:
    scene = bpy.context.scene
    if scene.camera is None:
        data = bpy.data.cameras.new("AgentCamera")
        camera = bpy.data.objects.new("AgentCamera", data)
        scene.collection.objects.link(camera)
        camera.location = (10.0, -10.0, 8.0)
        direction = mathutils.Vector((0.0, 0.0, 0.0)) - camera.location
        camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.camera = camera

    if not any(obj.type == "LIGHT" for obj in scene.objects):
        data = bpy.data.lights.new("AgentSun", type="SUN")
        data.energy = 3.0
        sun = bpy.data.objects.new("AgentSun", data)
        scene.collection.objects.link(sun)
        sun.rotation_euler = tuple(math.radians(v) for v in (35.0, 0.0, -35.0))


def save_blend(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(path))


def export_glb(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        export_animations=False,
        export_apply=True,
    )


def render_preview(path: Path, width: int = 960, height: int = 540) -> None:
    ensure_default_camera_and_light()
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    else:
        raise RuntimeError("No supported Blender render engine is available.")
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(path)
    scene.world.color = (0.04, 0.04, 0.04)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)


def scene_report(path: Path, job_path: Path, job: dict) -> None:
    scene = bpy.context.scene
    objects = list(scene.objects)
    meshes = [obj for obj in objects if obj.type == "MESH"]
    report = {
        "blender_version": bpy.app.version_string,
        "job": str(job_path),
        "scene_id": job.get("scene_id", job_path.stem),
        "description": job.get("description", ""),
        "design_references": job.get("design_references", []),
        "combat_mapping": (
            json.loads(scene.get("kaos_combat_mapping_json", "{}"))
            if scene.get("kaos_combat_mapping_json")
            else job.get("combat_mapping", {})
        ),
        "asset_root": os.environ.get("VTT_BLENDER_ASSET_ROOT", ""),
        "object_count": len(objects),
        "mesh_object_count": len(meshes),
        "triangle_count": sum(
            sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
            for obj in meshes
            if obj.data is not None
        ),
        "objects": [
            {
                "name": obj.name,
                "type": obj.type,
                "location": [round(float(v), 4) for v in obj.location],
            }
            for obj in objects
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2), encoding="utf-8")



def _material(name: str, base_color, roughness: float = 0.7, metallic: float = 0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*base_color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    return mat


def _assign_material(obj, mat) -> None:
    if obj.data is not None and hasattr(obj.data, "materials"):
        obj.data.materials.clear()
        obj.data.materials.append(mat)


def _add_cylinder(name: str, radius: float, depth: float, location, mat, vertices: int = 64):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
    )
    obj = bpy.context.object
    obj.name = name
    _assign_material(obj, mat)
    return obj


def _add_box(name: str, scale, location, mat, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    _assign_material(obj, mat)
    return obj


def _add_column(name: str, location, height: float, radius: float, mat, broken: float = 1.0):
    total = height * broken
    shaft = _add_cylinder(
        name + "_Shaft",
        radius,
        total,
        (location[0], location[1], location[2] + total * 0.5),
        mat,
        vertices=20,
    )
    # Slight taper via top/bottom decorative drums.
    _add_cylinder(
        name + "_Base",
        radius * 1.35,
        min(1.2, total * 0.08),
        (location[0], location[1], location[2] + min(0.6, total * 0.04)),
        mat,
        vertices=24,
    )
    if broken > 0.82:
        _add_cylinder(
            name + "_Capital",
            radius * 1.45,
            min(1.0, total * 0.07),
            (location[0], location[1], location[2] + total - min(0.5, total * 0.035)),
            mat,
            vertices=24,
        )
    return shaft


def _add_arch(
    name: str,
    center,
    width: float,
    height: float,
    depth: float,
    mat,
    ruined: bool = False,
    rotation_z: float = 0.0,
):
    x, y, z = center
    pillar_w = width * 0.12
    pillar_h = height * (0.72 if ruined else 0.78)

    def world_point(local_x: float, local_y: float, local_z: float):
        return (
            x + math.cos(rotation_z) * local_x - math.sin(rotation_z) * local_y,
            y + math.sin(rotation_z) * local_x + math.cos(rotation_z) * local_y,
            z + local_z,
        )

    _add_box(
        name + "_L",
        (pillar_w * 0.5, depth * 0.5, pillar_h * 0.5),
        world_point(-width * 0.5 + pillar_w * 0.5, 0.0, pillar_h * 0.5),
        mat,
        rotation=(0.0, 0.0, rotation_z),
    )
    _add_box(
        name + "_R",
        (pillar_w * 0.5, depth * 0.5, pillar_h * 0.5),
        world_point(width * 0.5 - pillar_w * 0.5, 0.0, pillar_h * 0.5),
        mat,
        rotation=(0.0, 0.0, rotation_z),
    )
    if not ruined:
        segments = 9
        arch_radius = width * 0.38
        arch_center_z = pillar_h
        for i in range(segments):
            a = math.pi * (i / (segments - 1))
            local_x = math.cos(a) * arch_radius
            local_z = arch_center_z + math.sin(a) * arch_radius
            _add_box(
                f"{name}_Voussoir_{i:02d}",
                (width * 0.055, depth * 0.52, width * 0.055),
                world_point(local_x, 0.0, local_z),
                mat,
                rotation=(0.0, -(a - math.pi * 0.5), rotation_z),
            )
    else:
        _add_box(
            name + "_BrokenLintel",
            (width * 0.20, depth * 0.52, pillar_w * 0.6),
            world_point(-width * 0.28, 0.0, pillar_h + width * 0.13),
            mat,
            rotation=(0.0, 0.18, rotation_z + 0.12),
        )


def _add_rock(name: str, location, scale, mat, seed_value: int):
    rng = random.Random(seed_value)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler = (
        rng.uniform(-0.5, 0.5),
        rng.uniform(-0.5, 0.5),
        rng.uniform(-math.pi, math.pi),
    )
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    _assign_material(obj, mat)
    return obj


def _kaos_mapping_from_godot(root: Path) -> dict:
    scenery_path = root / "encounter" / "encounter_scenery.gd"
    hazard_path = root / "encounter" / "hazard_allowed_area.gd"
    measurement_path = root / "measurement_tool.gd"

    for path in (scenery_path, hazard_path, measurement_path):
        if not path.exists():
            raise FileNotFoundError(f"Kaos mapping source missing: {path}")

    scenery = scenery_path.read_text(encoding="utf-8")
    hazard = hazard_path.read_text(encoding="utf-8")
    measurement = measurement_path.read_text(encoding="utf-8")

    def one(pattern: str, text: str, label: str) -> tuple[str, ...]:
        match = re.search(pattern, text, re.MULTILINE)
        if not match:
            raise RuntimeError(f"Could not derive {label} from current Godot source.")
        return match.groups()

    floor_x, floor_z = one(
        r"floor_shape\.size\s*=\s*Vector3\(\s*([0-9.]+)\s*\*\s*_units,\s*[0-9.]+,\s*([0-9.]+)\s*\*\s*_units\s*\)",
        scenery,
        "battlemap dimensions",
    )
    (floor_center_z,) = one(
        r'get_node\("Board/FloorCollision"\)\.position\.z\s*=\s*([0-9.]+)\s*\*\s*_units',
        scenery,
        "battlemap center",
    )
    (water_radius,) = one(
        r"water_mesh\.top_radius\s*=\s*([0-9.]+)\s*\*\s*_units",
        scenery,
        "water radius",
    )
    water_y, water_z = one(
        r"water\.position\s*=\s*Vector3\(\s*0\s*,\s*([-0-9.]+)\s*,\s*([-0-9.]+)\s*\)\s*\*\s*_units",
        scenery,
        "water position",
    )
    klothis_elev, sphere_extra = one(
        r"@export var klothis_group_elevation_meters:\s*float\s*=\s*([0-9.]+).*?@export var sphere_extra_elevation_meters:\s*float\s*=\s*([0-9.]+)",
        scenery,
        "Klothys elevation defaults",
    )
    sphere_base_y, sphere_local_z = one(
        r"sphere\.position\s*=\s*Vector3\(\s*0\s*,\s*([0-9.]+)\s*\+\s*sphere_extra_elevation_meters\s*,\s*([-0-9.]+)\s*\)",
        scenery,
        "sphere local position",
    )
    (sphere_radius,) = one(
        r"_sphere\(\s*sphere\s*,\s*([0-9.]+)\s*,",
        scenery,
        "sphere radius",
    )
    klothis_root_z = -12.0
    klothis_root_match = re.search(
        r"klothis\.position\s*=\s*Vector3\(\s*0\s*,\s*klothis_group_elevation_meters\s*,\s*([-0-9.]+)\s*\)",
        scenery,
    )
    if klothis_root_match:
        klothis_root_z = float(klothis_root_match.group(1))

    hx, hz, hw, hh = one(
        r"Rect2i\(\s*([-0-9]+)\s*,\s*([-0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*\)",
        hazard,
        "hazard cell rectangle",
    )
    (meters_per_cell,) = one(
        r"meters_per_cell:\s*float\s*=\s*([0-9.]+)",
        measurement,
        "meters per cell",
    )

    klothis_elev = float(klothis_elev)
    sphere_extra = float(sphere_extra)
    sphere_base_y = float(sphere_base_y)
    sphere_local_z = float(sphere_local_z)
    mpc = float(meters_per_cell)

    return {
        "coordinate_mapping": "Godot (X,Y,Z) -> Blender (X,Z,Y)",
        "meters_per_cell": mpc,
        "battlemap": {
            "size_m": [float(floor_x), float(floor_z)],
            "center_godot_m": [0.0, 0.0, float(floor_center_z)],
            "x_bounds_m": [-float(floor_x) * 0.5, float(floor_x) * 0.5],
            "z_bounds_m": [
                float(floor_center_z) - float(floor_z) * 0.5,
                float(floor_center_z) + float(floor_z) * 0.5,
            ],
        },
        "hazard_area": {
            "cells": [int(hx), int(hz), int(hw), int(hh)],
            "size_m": [int(hw) * mpc, int(hh) * mpc],
            "x_bounds_m": [int(hx) * mpc, (int(hx) + int(hw)) * mpc],
            "z_bounds_m": [int(hz) * mpc, (int(hz) + int(hh)) * mpc],
        },
        "water": {
            "radius_m": float(water_radius),
            "center_godot_m": [0.0, float(water_y), float(water_z)],
        },
        "sphere": {
            "radius_m": float(sphere_radius),
            "center_godot_m": [
                0.0,
                klothis_elev + sphere_base_y + sphere_extra,
                klothis_root_z + sphere_local_z,
            ],
        },
    }


def _validate_expected_mapping(actual: dict, expected: dict) -> None:
    if not expected:
        return

    checks = [
        ("meters_per_cell", actual["meters_per_cell"], expected["meters_per_cell"]),
        ("battlemap.size_m[0]", actual["battlemap"]["size_m"][0], expected["battlemap"]["size_m"][0]),
        ("battlemap.size_m[1]", actual["battlemap"]["size_m"][1], expected["battlemap"]["size_m"][1]),
        ("battlemap.center_godot_m[2]", actual["battlemap"]["center_godot_m"][2], expected["battlemap"]["center_godot_m"][2]),
        ("water.radius_m", actual["water"]["radius_m"], expected["water"]["radius_m"]),
        ("water.center_godot_m[2]", actual["water"]["center_godot_m"][2], expected["water"]["center_godot_m"][2]),
        ("sphere.radius_m", actual["sphere"]["radius_m"], expected["sphere"]["radius_m"]),
        ("sphere.center_godot_m[1]", actual["sphere"]["center_godot_m"][1], expected["sphere"]["center_godot_m"][1]),
        ("sphere.center_godot_m[2]", actual["sphere"]["center_godot_m"][2], expected["sphere"]["center_godot_m"][2]),
    ]
    for label, got, want in checks:
        if abs(float(got) - float(want)) > 1e-6:
            raise RuntimeError(f"Godot/Blender mapping drift for {label}: Godot={got}, expected={want}")

    if actual["hazard_area"]["cells"] != expected["hazard_area"]["cells"]:
        raise RuntimeError(
            "Godot/Blender hazard mapping drift: "
            f"Godot={actual['hazard_area']['cells']}, expected={expected['hazard_area']['cells']}"
        )


def build_kaos_arena(op: dict, root_path: Path) -> None:
    """Build a Blender visual shell whose combat geometry matches Godot exactly."""
    rng = random.Random(int(op.get("seed", 20261002)))
    scale = float(op.get("scale", 1.0))

    mapping = _kaos_mapping_from_godot(root_path)
    _validate_expected_mapping(mapping, op.get("expected_mapping", {}))
    bpy.context.scene["kaos_combat_mapping_json"] = json.dumps(mapping, sort_keys=True)

    stone = _material("Arena_Weathered_Marble", (0.48, 0.47, 0.43), 0.86)
    stone_dark = _material("Arena_Dark_Stone", (0.09, 0.095, 0.105), 0.82)
    stone_light = _material("Arena_Pale_Stone", (0.62, 0.60, 0.54), 0.78)
    gold = _material("Arena_Aged_Gold", (0.32, 0.20, 0.06), 0.42, 0.55)
    water = _material("Arena_Deep_Water", (0.018, 0.055, 0.075), 0.18, 0.08)
    rock = _material("Arena_Cliff_Rock", (0.12, 0.115, 0.105), 0.94)

    root = bpy.data.collections.new("KAOS_ARENA")
    bpy.context.scene.collection.children.link(root)
    before = set(bpy.context.scene.objects)

    # Godot X,Z become Blender X,Y. Godot vertical Y becomes Blender Z.
    floor_w, floor_d = mapping["battlemap"]["size_m"]
    floor_center_y = mapping["battlemap"]["center_godot_m"][2]
    water_radius = mapping["water"]["radius_m"]
    water_center_y = mapping["water"]["center_godot_m"][2]
    water_height = mapping["water"]["center_godot_m"][1]
    sphere_radius = mapping["sphere"]["radius_m"]
    sphere_godot = mapping["sphere"]["center_godot_m"]
    sphere_blender = (sphere_godot[0], sphere_godot[2], sphere_godot[1])

    # Exact visual proxy for the current Godot FloorCollision: 120 x 180 m.
    # Decorative geometry may exist outside this rectangle but must not change it.
    floor = _add_box(
        "COMBAT_TacticalFloor_120x180m",
        (floor_w * 0.5 * scale, floor_d * 0.5 * scale, 0.35 * scale),
        (0.0, floor_center_y * scale, -0.35 * scale),
        stone,
    )
    floor["godot_role"] = "Board/FloorCollision"
    floor["size_m"] = f"{floor_w}x{floor_d}"
    floor["center_godot_m"] = f"0,0,{floor_center_y}"

    # A subtly raised inner paving field follows the same footprint but remains
    # entirely inside it. It is visual dressing, not a new gameplay boundary.
    _add_box(
        "ArenaInnerPaving",
        ((floor_w - 3.0) * 0.5 * scale, (floor_d - 3.0) * 0.5 * scale, 0.10 * scale),
        (0.0, floor_center_y * scale, 0.10 * scale),
        stone_light,
    )

    # Exact Godot water basin reference: radius 337 m, centered at Z=-60 m.
    water_obj = _add_cylinder(
        "COMBAT_WaterBasin_R337m",
        water_radius * scale,
        0.20 * scale,
        (0.0, water_center_y * scale, water_height * scale),
        water,
        vertices=160,
    )
    water_obj["godot_role"] = "Board/WaterSurface"
    water_obj["radius_m"] = water_radius

    # Exact Klothys sphere mapping. This is intentionally enormous relative
    # to the 120x180 m battlemap, matching encounter_scenery.gd.
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=128,
        ring_count=64,
        radius=sphere_radius * scale,
        location=tuple(v * scale for v in sphere_blender),
    )
    sphere = bpy.context.object
    sphere.name = "COMBAT_KlothysSphere_R220m"
    sphere["godot_role"] = "KlothisRoot/SphereVisual"
    sphere["radius_m"] = sphere_radius
    sphere["center_godot_m"] = ",".join(str(v) for v in sphere_godot)
    _assign_material(sphere, stone_dark)

    # Keep only restrained bindings; these do not alter the sphere surface.
    for band_angle in (-0.58, 0.0, 0.58):
        bpy.ops.mesh.primitive_torus_add(
            major_radius=(sphere_radius + 1.2) * scale,
            minor_radius=0.85 * scale,
            major_segments=128,
            minor_segments=10,
            location=tuple(v * scale for v in sphere_blender),
            rotation=(band_angle, 0.0, 0.0),
        )
        band = bpy.context.object
        band.name = "SphereBinding"
        _assign_material(band, gold)

    # Tactical reference markers: four corner plinths sit just OUTSIDE the
    # combat rectangle, so they make scale readable without occupying cells.
    xb = mapping["battlemap"]["x_bounds_m"]
    yb = mapping["battlemap"]["z_bounds_m"]
    corner_offset = 2.0
    for idx, (x, y) in enumerate([
        (xb[0] - corner_offset, yb[0] - corner_offset),
        (xb[1] + corner_offset, yb[0] - corner_offset),
        (xb[0] - corner_offset, yb[1] + corner_offset),
        (xb[1] + corner_offset, yb[1] + corner_offset),
    ]):
        _add_box(
            f"BoundaryPlinth_{idx}",
            (1.5 * scale, 1.5 * scale, 0.8 * scale),
            (x * scale, y * scale, 0.8 * scale),
            stone_dark,
        )

    # Scenic ruins follow the ACTUAL Godot apse radii: columns start around
    # 310 m from (0,-60), with the back wall at 395 m. They stay far outside
    # the practical 120x180 m combat floor.
    ruin_center_y = -60.0
    kept_angles = [160, 177, 196, 216, 238, 262, 287, 313, 340]
    ruin_radius = 310.0
    for idx, deg in enumerate(kept_angles):
        a = math.radians(deg)
        x = math.cos(a) * ruin_radius
        y = ruin_center_y + math.sin(a) * ruin_radius
        broken = 1.0 if idx not in (1, 5, 8) else rng.uniform(0.55, 0.78)
        _add_column(
            f"ScenicColumn_{idx:02d}",
            (x * scale, y * scale, 0.0),
            29.0 * scale,
            2.8 * scale,
            stone_light,
            broken=broken,
        )

    # A few fallen fragments may decorate the floor, but remain low and do not
    # define the combat boundary. They can later be removed or made non-solid.
    for i in range(12):
        x = rng.uniform(xb[0] + 8, xb[1] - 8)
        y = rng.uniform(yb[0] + 8, yb[1] - 8)
        _add_rock(
            f"ScenicFloorDebris_{i:02d}",
            (x * scale, y * scale, 0.45 * scale),
            (
                rng.uniform(0.7, 1.8) * scale,
                rng.uniform(0.6, 1.5) * scale,
                rng.uniform(0.3, 0.7) * scale,
            ),
            stone_dark if i % 3 == 0 else rock,
            3000 + i,
        )

    key = bpy.data.lights.new("KaosKey", type="SUN")
    key.energy = 3.0
    key.color = (1.0, 0.84, 0.68)
    key_obj = bpy.data.objects.new("KaosKey", key)
    bpy.context.scene.collection.objects.link(key_obj)
    key_obj.rotation_euler = tuple(math.radians(v) for v in (42, -18, -28))

    fill = bpy.data.lights.new("KaosFill", type="AREA")
    fill.energy = 2600
    fill.shape = "DISK"
    fill.size = 120 * scale
    fill.color = (0.22, 0.38, 0.55)
    fill_obj = bpy.data.objects.new("KaosFill", fill)
    bpy.context.scene.collection.objects.link(fill_obj)
    fill_obj.location = (-180 * scale, 80 * scale, 280 * scale)
    fill_obj.rotation_euler = (math.radians(30), 0, math.radians(-35))

    bpy.context.scene.world.color = (0.012, 0.016, 0.024)

    generated = [obj for obj in bpy.context.scene.objects if obj not in before]
    for obj in generated:
        for coll in list(obj.users_collection):
            coll.objects.unlink(obj)
        root.objects.link(obj)


def _set_camera_pose(location, look_at, lens: float) -> None:
    scene = bpy.context.scene
    camera = scene.camera
    if camera is None:
        data = bpy.data.cameras.new("AgentCamera")
        camera = bpy.data.objects.new("AgentCamera", data)
        scene.collection.objects.link(camera)
        scene.camera = camera
    camera.location = location
    direction = mathutils.Vector(look_at) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = lens
    camera.data.clip_end = 3000.0


def render_preview_spec(root: Path, spec: dict) -> None:
    _set_camera_pose(
        vec3(spec.get("location"), (150.0, -165.0, 110.0)),
        vec3(spec.get("look_at"), (0.0, 35.0, 35.0)),
        float(spec.get("lens", 50.0)),
    )
    render_preview(
        project_path(root, spec["path"]),
        int(spec.get("width", 1280)),
        int(spec.get("height", 720)),
    )

def execute_operation(op: dict, root: Path) -> None:
    kind = op.get("op")
    if kind == "add_cube":
        add_cube(op)
    elif kind == "add_plane":
        add_plane(op)
    elif kind == "add_sun":
        add_sun(op)
    elif kind == "set_camera":
        set_camera(op)
    elif kind == "build_kaos_arena":
        build_kaos_arena(op, root)
    else:
        raise ValueError(f"Unsupported operation: {kind!r}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--job", required=True)
    parser.add_argument("--project-root", required=True)
    args = parser.parse_args(argv)

    if tuple(bpy.app.version[:2]) != REQUIRED_VERSION:
        raise RuntimeError(f"Expected Blender 5.2.x, found {bpy.app.version_string}")

    root = Path(args.project_root).resolve()
    job_path = project_path(root, args.job)
    job = json.loads(job_path.read_text(encoding="utf-8"))

    if job.get("schema_version") != 1:
        raise RuntimeError("Unsupported Blender job schema")

    source_scene = job.get("scene")
    if source_scene:
        source_path = project_path(root, source_scene)
        if not source_path.exists():
            raise FileNotFoundError(source_path)
        bpy.ops.wm.open_mainfile(filepath=str(source_path))
    elif job.get("reset_scene", True):
        clear_scene()

    for index, operation in enumerate(job.get("operations", []), start=1):
        print(f"BLENDER_AGENT_OP {index}: {operation.get('op')}", flush=True)
        execute_operation(operation, root)

    outputs = job.get("outputs", {})
    if outputs.get("previews"):
        for preview_index, spec in enumerate(outputs["previews"], start=1):
            print(f"BLENDER_AGENT_OUTPUT preview_{preview_index}", flush=True)
            render_preview_spec(root, spec)
    elif outputs.get("preview"):
        print("BLENDER_AGENT_OUTPUT preview", flush=True)
        render_preview(
            project_path(root, outputs["preview"]),
            int(outputs.get("preview_width", 960)),
            int(outputs.get("preview_height", 540)),
        )
    if outputs.get("report"):
        print("BLENDER_AGENT_OUTPUT report", flush=True)
        scene_report(project_path(root, outputs["report"]), job_path, job)
    if outputs.get("glb"):
        print("BLENDER_AGENT_OUTPUT glb", flush=True)
        export_glb(project_path(root, outputs["glb"]))
    if outputs.get("blend"):
        print("BLENDER_AGENT_OUTPUT blend", flush=True)
        save_blend(project_path(root, outputs["blend"]))

    print("BLENDER_AGENT_PASS", job_path.name)
    return 0


if __name__ == "__main__":
    import mathutils

    cli = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    try:
        raise SystemExit(main(cli))
    except SystemExit:
        raise
    except Exception:
        print("BLENDER_AGENT_TRACEBACK_BEGIN", flush=True)
        print(traceback.format_exc(), flush=True)
        print("BLENDER_AGENT_TRACEBACK_END", flush=True)
        raise SystemExit(1)
