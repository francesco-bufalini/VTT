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
import sys
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
    scene.render.engine = "BLENDER_EEVEE_NEXT"
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
    if outputs.get("preview"):
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
