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


def scene_report(path: Path, job_path: Path) -> None:
    scene = bpy.context.scene
    objects = list(scene.objects)
    meshes = [obj for obj in objects if obj.type == "MESH"]
    report = {
        "blender_version": bpy.app.version_string,
        "job": str(job_path),
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


def _add_arch(name: str, center, width: float, height: float, depth: float, mat, ruined: bool = False):
    x, y, z = center
    pillar_w = width * 0.12
    pillar_h = height * (0.72 if ruined else 0.78)
    _add_box(
        name + "_L",
        (pillar_w * 0.5, depth * 0.5, pillar_h * 0.5),
        (x - width * 0.5 + pillar_w * 0.5, y, z + pillar_h * 0.5),
        mat,
    )
    _add_box(
        name + "_R",
        (pillar_w * 0.5, depth * 0.5, pillar_h * 0.5),
        (x + width * 0.5 - pillar_w * 0.5, y, z + pillar_h * 0.5),
        mat,
    )
    if not ruined:
        segments = 9
        arch_radius = width * 0.38
        arch_center_z = z + pillar_h
        for i in range(segments):
            a = math.pi * (i / (segments - 1))
            bx = x + math.cos(a) * arch_radius
            bz = arch_center_z + math.sin(a) * arch_radius
            block = _add_box(
                f"{name}_Voussoir_{i:02d}",
                (width * 0.055, depth * 0.52, width * 0.055),
                (bx, y, bz),
                mat,
                rotation=(0.0, a - math.pi * 0.5, 0.0),
            )
            block.rotation_euler.y = -(a - math.pi * 0.5)
    else:
        _add_box(
            name + "_BrokenLintel",
            (width * 0.20, depth * 0.52, pillar_w * 0.6),
            (x - width * 0.28, y, z + pillar_h + width * 0.13),
            mat,
            rotation=(0.0, 0.18, 0.12),
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


def build_kaos_arena(op: dict) -> None:
    """Build the first Blender-authored Kaos arena environment shell.

    This intentionally models only visual environment geometry. Gameplay
    collision, tokens, Kaos anatomy and encounter logic stay in Godot.
    """
    rng = random.Random(int(op.get("seed", 20261002)))
    scale = float(op.get("scale", 1.0))

    stone = _material("Arena_Weathered_Marble", (0.48, 0.47, 0.43), 0.86)
    stone_dark = _material("Arena_Dark_Stone", (0.09, 0.095, 0.105), 0.82)
    stone_light = _material("Arena_Pale_Stone", (0.62, 0.60, 0.54), 0.78)
    gold = _material("Arena_Aged_Gold", (0.32, 0.20, 0.06), 0.42, 0.55)
    water = _material("Arena_Deep_Water", (0.018, 0.055, 0.075), 0.18, 0.08)
    rock = _material("Arena_Cliff_Rock", (0.12, 0.115, 0.105), 0.94)

    root = bpy.data.collections.new("KAOS_ARENA")
    bpy.context.scene.collection.children.link(root)

    # Build in the scene collection, then move generated objects into KAOS_ARENA.
    before = set(bpy.context.scene.objects)

    # Water basin and concentric stepped arena.
    _add_cylinder("WaterBasin", 190 * scale, 0.7 * scale, (0, 0, -0.5 * scale), water, vertices=128)
    rings = [
        (112, 1.0, 0.0, stone_dark),
        (101, 1.8, 0.7, stone),
        (88, 1.6, 1.7, stone_light),
        (73, 1.4, 2.6, stone),
    ]
    for idx, (radius, depth, z, mat) in enumerate(rings):
        _add_cylinder(
            f"ArenaRing_{idx}",
            radius * scale,
            depth * scale,
            (0, 0, (z + depth * 0.5) * scale),
            mat,
            vertices=128,
        )

    # Central fractured dais.
    _add_cylinder("CentralDais", 45 * scale, 1.4 * scale, (0, 0, 4.0 * scale), stone_dark, vertices=96)
    for i in range(12):
        angle = i * math.tau / 12.0 + rng.uniform(-0.08, 0.08)
        radius = rng.uniform(35, 58) * scale
        w = rng.uniform(3.5, 7.5) * scale
        l = rng.uniform(8.0, 18.0) * scale
        h = rng.uniform(0.5, 1.4) * scale
        _add_box(
            f"FracturedSlab_{i:02d}",
            (w * 0.5, l * 0.5, h * 0.5),
            (math.cos(angle) * radius, math.sin(angle) * radius, (4.2 + h * 0.5) * scale),
            stone_light if i % 3 else stone,
            rotation=(rng.uniform(-0.07,0.07), rng.uniform(-0.07,0.07), angle + rng.uniform(-0.2,0.2)),
        )

    # Monumental sphere behind the arena, echoing the Godot encounter composition.
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=96,
        ring_count=48,
        radius=74 * scale,
        location=(0, 118 * scale, 70 * scale),
    )
    sphere = bpy.context.object
    sphere.name = "KlothysSphere_Reference"
    _assign_material(sphere, stone_dark)
    for band_angle in (-0.58, 0.0, 0.58):
        bpy.ops.mesh.primitive_torus_add(
            major_radius=74.8 * scale,
            minor_radius=0.7 * scale,
            major_segments=96,
            minor_segments=10,
            location=(0, 118 * scale, 70 * scale),
            rotation=(band_angle, 0.0, 0.0),
        )
        band = bpy.context.object
        band.name = "SphereBinding"
        _assign_material(band, gold)

    # Outer ruin arc: intentionally incomplete/asymmetric.
    ruin_radius = 105 * scale
    kept_angles = [-155, -132, -110, -87, -65, -43, -20, 4, 31, 59, 84, 112, 139]
    for idx, deg in enumerate(kept_angles):
        a = math.radians(deg)
        p = (math.cos(a) * ruin_radius, math.sin(a) * ruin_radius, 4.3 * scale)
        broken = 1.0
        if idx in (1, 4, 8, 11):
            broken = rng.uniform(0.48, 0.76)
        col = _add_column(
            f"OuterColumn_{idx:02d}",
            p,
            18 * scale,
            1.55 * scale,
            stone_light,
            broken=broken,
        )
        col.rotation_euler.z = a + math.pi * 0.5

    # Three surviving arches establish scale; two damaged ones break symmetry.
    arch_specs = [
        (-72, False, 16),
        (0, False, 18),
        (68, False, 15),
        (128, True, 13),
        (-138, True, 12),
    ]
    for idx, (deg, ruined, width) in enumerate(arch_specs):
        a = math.radians(deg)
        r = 101 * scale
        x, y = math.cos(a) * r, math.sin(a) * r
        _add_arch(
            f"RuinArch_{idx:02d}",
            (x, y, 4.3 * scale),
            width * scale,
            18 * scale,
            3.0 * scale,
            stone_light,
            ruined=ruined,
        )
        # Parentless primitive architecture: rotate every piece created near the arch.
        # Visual orientation is handled by placing arches along the outer silhouette.

    # Fallen column drums and debris.
    for i in range(28):
        a = rng.uniform(-math.pi, math.pi)
        r = rng.uniform(78, 118) * scale
        x, y = math.cos(a) * r, math.sin(a) * r
        if i < 10:
            bpy.ops.mesh.primitive_cylinder_add(
                vertices=20,
                radius=rng.uniform(1.1, 1.8) * scale,
                depth=rng.uniform(4.0, 9.0) * scale,
                location=(x, y, rng.uniform(4.8, 6.0) * scale),
                rotation=(rng.uniform(1.25,1.75), rng.uniform(-0.25,0.25), a),
            )
            obj = bpy.context.object
            obj.name = f"FallenColumn_{i:02d}"
            _assign_material(obj, stone_light)
        else:
            _add_rock(
                f"Debris_{i:02d}",
                (x, y, rng.uniform(4.3, 5.2) * scale),
                (
                    rng.uniform(1.2, 3.8) * scale,
                    rng.uniform(1.0, 3.1) * scale,
                    rng.uniform(0.6, 2.0) * scale,
                ),
                stone if i % 2 else rock,
                1000 + i,
            )

    # Perimeter cliff fragments to give the arena a stronger silhouette.
    for i in range(18):
        a = math.radians(-170 + i * 20 + rng.uniform(-5, 5))
        r = rng.uniform(150, 176) * scale
        _add_rock(
            f"PerimeterRock_{i:02d}",
            (math.cos(a) * r, math.sin(a) * r, rng.uniform(3, 8) * scale),
            (
                rng.uniform(7, 16) * scale,
                rng.uniform(5, 12) * scale,
                rng.uniform(8, 20) * scale,
            ),
            rock,
            2000 + i,
        )

    # Small processional bridge from the near side into the arena.
    for i in range(8):
        _add_box(
            f"ApproachStep_{i:02d}",
            (7.0 * scale, 5.0 * scale, 0.45 * scale),
            (0, (-128 + i * 8.5) * scale, (0.2 + i * 0.48) * scale),
            stone if i % 2 else stone_light,
        )

    # Lighting tuned for readable greybox + material preview.
    key = bpy.data.lights.new("KaosKey", type="SUN")
    key.energy = 2.8
    key.color = (1.0, 0.84, 0.68)
    key_obj = bpy.data.objects.new("KaosKey", key)
    bpy.context.scene.collection.objects.link(key_obj)
    key_obj.rotation_euler = tuple(math.radians(v) for v in (42, -18, -28))

    fill = bpy.data.lights.new("KaosFill", type="AREA")
    fill.energy = 1800
    fill.shape = "DISK"
    fill.size = 55 * scale
    fill.color = (0.22, 0.38, 0.55)
    fill_obj = bpy.data.objects.new("KaosFill", fill)
    bpy.context.scene.collection.objects.link(fill_obj)
    fill_obj.location = (-65 * scale, -45 * scale, 68 * scale)
    fill_obj.rotation_euler = (math.radians(30), 0, math.radians(-35))

    scene = bpy.context.scene
    scene.world.color = (0.012, 0.016, 0.024)

    # Move freshly generated objects into dedicated collection for later editing.
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

def execute_operation(op: dict) -> None:
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
        build_kaos_arena(op)
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
        execute_operation(operation)

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
        scene_report(project_path(root, outputs["report"]), job_path)
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
