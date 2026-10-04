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
import urllib.parse
import urllib.request
from pathlib import Path

import bpy


REQUIRED_VERSION = (5, 2)
BLENDER_AGENT_DIR = Path(__file__).resolve().parent
if str(BLENDER_AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(BLENDER_AGENT_DIR))


def project_path(root: Path, value: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        path = root / path
    return path.resolve()


def output_path(root: Path, value: str, output_root: Path | None) -> Path:
    path = Path(value)
    if output_root is None:
        return project_path(root, value)

    normalized = path.as_posix()
    prefix = "outputs/blender_agent/"
    if normalized.startswith(prefix):
        normalized = normalized[len(prefix):]
    elif path.is_absolute():
        normalized = path.name

    return (output_root / Path(normalized)).resolve()


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
    for image in bpy.data.images:
        relative = image.get("vtt_relative_path")
        if relative:
            image.filepath = str(relative)
            image.filepath_raw = str(relative)
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
        "layout_extension": (
            json.loads(scene.get("kaos_layout_extension_json", "{}"))
            if scene.get("kaos_layout_extension_json")
            else job.get("layout_extension", {})
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




def _json_from_url(url: str):
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "VTT-Blender-Agent/1.0 (+https://github.com/francesco-bufalini/VTT)",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def _flatten_download_leaves(tree, path=()):
    leaves = []
    if isinstance(tree, dict):
        if isinstance(tree.get("url"), str):
            leaves.append((path, tree))
        else:
            for key, value in tree.items():
                leaves.extend(_flatten_download_leaves(value, path + (str(key),)))
    elif isinstance(tree, list):
        for index, value in enumerate(tree):
            leaves.extend(_flatten_download_leaves(value, path + (str(index),)))
    return leaves


def _polyhaven_pick_file(files_tree, kind: str, resolution: str = "1k"):
    aliases = {
        "diffuse": ("diffuse", "albedo", "basecolor", "base_color"),
        "normal": ("nor_gl", "normal_gl", "normal (gl)", "normal"),
        "rough": ("rough", "roughness"),
    }
    wanted = aliases[kind]
    candidates = []
    for path, leaf in _flatten_download_leaves(files_tree):
        path_text = "/".join(path).lower()
        url = str(leaf.get("url", ""))
        if not url:
            continue
        if not any(alias in path_text for alias in wanted):
            continue
        score = 0
        if resolution.lower() in path_text:
            score += 20
        if kind == "normal" and "nor_gl" in path_text:
            score += 20
        if path and path[-1].lower() == "jpg":
            score += 8
        elif path and path[-1].lower() == "png":
            score += 6
        if "exr" in path_text:
            score -= 10
        candidates.append((score, path, leaf))
    if not candidates:
        raise RuntimeError(
            f"Poly Haven asset does not expose {kind!r} at a usable format/resolution."
        )
    candidates.sort(key=lambda item: (item[0], "/".join(item[1])), reverse=True)
    return candidates[0][2]


def _download_file(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and destination.stat().st_size > 0:
        return
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "VTT-Blender-Agent/1.0 (+https://github.com/francesco-bufalini/VTT)"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        data = response.read()
    destination.write_bytes(data)


def _polyhaven_texture_set(
    root_path: Path,
    scene_id: str,
    asset_id: str,
    resolution: str = "1k",
) -> dict:
    files_tree = _json_from_url(f"https://api.polyhaven.com/files/{asset_id}")
    target_dir = root_path / "blender" / "scenes" / scene_id / "textures" / asset_id
    target_dir.mkdir(parents=True, exist_ok=True)
    result = {}
    manifest_maps = {}

    for kind in ("diffuse", "normal", "rough"):
        leaf = _polyhaven_pick_file(files_tree, kind, resolution)
        url = str(leaf["url"])
        suffix = Path(urllib.parse.urlparse(url).path).suffix.lower() or ".jpg"
        filename = f"{asset_id}_{resolution}_{kind}{suffix}"
        dest = target_dir / filename
        _download_file(url, dest)
        result[kind] = dest
        manifest_maps[kind] = {
            "file": filename,
            "source_url": url,
            "size_bytes": dest.stat().st_size,
            "md5": leaf.get("md5", ""),
        }

    manifest = {
        "asset_id": asset_id,
        "source": f"https://polyhaven.com/a/{asset_id}",
        "api": f"https://api.polyhaven.com/files/{asset_id}",
        "license": "CC0",
        "resolution": resolution,
        "maps": manifest_maps,
    }
    (target_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8",
    )
    return result


def _pbr_material_from_maps(
    name: str,
    maps: dict,
    tiling=(32.0, 32.0, 32.0),
    normal_strength: float = 0.65,
):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    output.location = (620, 0)
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (360, 0)
    bsdf.inputs["Roughness"].default_value = 0.72
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])

    texcoord = nodes.new("ShaderNodeTexCoord")
    texcoord.location = (-900, 0)
    mapping = nodes.new("ShaderNodeMapping")
    mapping.location = (-700, 0)
    mapping.inputs["Scale"].default_value = tuple(float(v) for v in tiling[:3])
    links.new(texcoord.outputs["Generated"], mapping.inputs["Vector"])

    diffuse = nodes.new("ShaderNodeTexImage")
    diffuse.location = (-430, 170)
    diffuse.image = bpy.data.images.load(str(maps["diffuse"]), check_existing=True)
    diffuse.image["vtt_relative_path"] = "//textures/" + maps["diffuse"].parent.name + "/" + maps["diffuse"].name
    diffuse.projection = "BOX"
    diffuse.projection_blend = 0.18
    links.new(mapping.outputs["Vector"], diffuse.inputs["Vector"])
    links.new(diffuse.outputs["Color"], bsdf.inputs["Base Color"])

    rough = nodes.new("ShaderNodeTexImage")
    rough.location = (-430, -60)
    rough.image = bpy.data.images.load(str(maps["rough"]), check_existing=True)
    rough.image["vtt_relative_path"] = "//textures/" + maps["rough"].parent.name + "/" + maps["rough"].name
    rough.image.colorspace_settings.name = "Non-Color"
    rough.projection = "BOX"
    rough.projection_blend = 0.18
    links.new(mapping.outputs["Vector"], rough.inputs["Vector"])
    links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])

    normal_tex = nodes.new("ShaderNodeTexImage")
    normal_tex.location = (-430, -300)
    normal_tex.image = bpy.data.images.load(str(maps["normal"]), check_existing=True)
    normal_tex.image["vtt_relative_path"] = "//textures/" + maps["normal"].parent.name + "/" + maps["normal"].name
    normal_tex.image.colorspace_settings.name = "Non-Color"
    normal_tex.projection = "BOX"
    normal_tex.projection_blend = 0.18
    links.new(mapping.outputs["Vector"], normal_tex.inputs["Vector"])

    normal = nodes.new("ShaderNodeNormalMap")
    normal.location = (90, -240)
    normal.inputs["Strength"].default_value = normal_strength
    links.new(normal_tex.outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])

    mat["texture_source"] = "Poly Haven"
    mat["texture_license"] = "CC0"
    return mat


def _cubic_bezier_2d(p0, p1, p2, p3, segments: int):
    points = []
    for i in range(segments + 1):
        t = i / segments
        u = 1.0 - t
        x = (
            u**3 * p0[0]
            + 3.0 * u * u * t * p1[0]
            + 3.0 * u * t * t * p2[0]
            + t**3 * p3[0]
        )
        y = (
            u**3 * p0[1]
            + 3.0 * u * u * t * p1[1]
            + 3.0 * u * t * t * p2[1]
            + t**3 * p3[1]
        )
        points.append((x, y))
    return points



def _point_in_polygon_2d(x: float, y: float, polygon) -> bool:
    inside = False
    j = len(polygon) - 1
    for i in range(len(polygon)):
        xi, yi = polygon[i]
        xj, yj = polygon[j]
        intersects = ((yi > y) != (yj > y)) and (
            x < (xj - xi) * (y - yi) / ((yj - yi) if abs(yj - yi) > 1e-12 else 1e-12) + xi
        )
        if intersects:
            inside = not inside
        j = i
    return inside


def _harmonious_walkable_outline(
    rect_x_min: float,
    rect_x_max: float,
    rect_y_max: float,
    circle_center,
    circle_radius: float,
    blend_start_y: float,
    circle_join_angle_deg: float = 32.0,
    transition_segments: int = 24,
    circle_segments: int = 180,
):
    cx, cy = float(circle_center[0]), float(circle_center[1])
    half_angle = math.radians(circle_join_angle_deg)
    right_join = (
        cx + math.sin(half_angle) * circle_radius,
        cy + math.cos(half_angle) * circle_radius,
    )
    left_join = (
        cx - math.sin(half_angle) * circle_radius,
        cy + math.cos(half_angle) * circle_radius,
    )
    left_start = (rect_x_min, blend_start_y)
    right_start = (rect_x_max, blend_start_y)

    desired_left_derivative = mathutils.Vector(
        (-math.cos(half_angle), -math.sin(half_angle))
    ).normalized()
    desired_right_derivative = mathutils.Vector(
        (-math.cos(half_angle), math.sin(half_angle))
    ).normalized()
    handle = min(58.0, circle_radius * 0.24)
    vertical_handle = min(
        48.0,
        max(20.0, (blend_start_y - right_join[1]) * 0.38),
    )

    left_curve = _cubic_bezier_2d(
        left_start,
        (left_start[0], left_start[1] - vertical_handle),
        (
            left_join[0] - desired_left_derivative.x * handle,
            left_join[1] - desired_left_derivative.y * handle,
        ),
        left_join,
        transition_segments,
    )

    left_angle = math.atan2(left_join[1] - cy, left_join[0] - cx)
    right_angle = math.atan2(right_join[1] - cy, right_join[0] - cx)
    while right_angle <= left_angle:
        right_angle += math.tau

    arc = []
    for i in range(1, circle_segments):
        t = i / circle_segments
        a = left_angle + (right_angle - left_angle) * t
        arc.append((cx + math.cos(a) * circle_radius, cy + math.sin(a) * circle_radius))

    right_curve = _cubic_bezier_2d(
        right_join,
        (
            right_join[0] + desired_right_derivative.x * handle,
            right_join[1] + desired_right_derivative.y * handle,
        ),
        (right_start[0], right_start[1] - vertical_handle),
        right_start,
        transition_segments,
    )

    outline = [(rect_x_min, rect_y_max), left_start]
    outline.extend(left_curve[1:])
    outline.extend(arc)
    outline.extend(right_curve[1:])
    outline.append((rect_x_max, rect_y_max))
    return outline


def _add_harmonious_rect_circle_prism(
    name: str,
    rect_x_min: float,
    rect_x_max: float,
    rect_y_min: float,
    rect_y_max: float,
    circle_center,
    circle_radius: float,
    thickness: float,
    mat,
    blend_start_y: float,
    circle_join_angle_deg: float = 32.0,
    transition_segments: int = 24,
    circle_segments: int = 180,
):
    """One continuous floor with smooth flared shoulders into the circular platform."""
    outline = _harmonious_walkable_outline(
        rect_x_min,
        rect_x_max,
        rect_y_max,
        circle_center,
        circle_radius,
        blend_start_y,
        circle_join_angle_deg=circle_join_angle_deg,
        transition_segments=transition_segments,
        circle_segments=circle_segments,
    )

    n = len(outline)
    top_z = 0.0
    bottom_z = -abs(float(thickness))
    verts = [(x, y, top_z) for x, y in outline] + [(x, y, bottom_z) for x, y in outline]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    _assign_material(obj, mat)
    obj["harmonious_transition"] = True
    obj["blend_start_y_m"] = blend_start_y
    obj["circle_join_angle_deg"] = circle_join_angle_deg
    obj["circle_radius_m"] = circle_radius
    return obj


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



def _add_rect_circle_union_prism(
    name: str,
    rect_x_min: float,
    rect_x_max: float,
    rect_y_min: float,
    rect_y_max: float,
    circle_center,
    circle_radius: float,
    thickness: float,
    mat,
    arc_segments: int = 128,
):
    """Create one watertight prism from the union of a rectangle and a circle.

    The circle must intersect the rectangle's lower edge. This is used for the
    Kaos walkable floor so the former rectangular floor and circular platform
    become one continuous mesh with no coplanar overlap or collision seam.
    """
    cx, cy = float(circle_center[0]), float(circle_center[1])
    dy = rect_y_min - cy
    if abs(dy) >= circle_radius:
        raise RuntimeError("Circle does not intersect the rectangle lower edge.")

    dx = math.sqrt(circle_radius * circle_radius - dy * dy)
    ix_left = cx - dx
    ix_right = cx + dx
    if ix_left <= rect_x_min or ix_right >= rect_x_max:
        raise RuntimeError(
            "Circle/rectangle intersection must fall inside the rectangle width "
            f"for a continuous union: intersections=({ix_left}, {ix_right}), "
            f"rect=({rect_x_min}, {rect_x_max})"
        )

    angle_left = math.atan2(dy, ix_left - cx)
    angle_right = math.atan2(dy, ix_right - cx)
    while angle_right <= angle_left:
        angle_right += math.tau

    outline = [
        (rect_x_min, rect_y_max),
        (rect_x_min, rect_y_min),
        (ix_left, rect_y_min),
    ]

    # Follow the long, outward arc around the circular platform.
    for i in range(1, arc_segments):
        t = i / arc_segments
        a = angle_left + (angle_right - angle_left) * t
        outline.append((cx + math.cos(a) * circle_radius, cy + math.sin(a) * circle_radius))

    outline.extend([
        (ix_right, rect_y_min),
        (rect_x_max, rect_y_min),
        (rect_x_max, rect_y_max),
    ])

    n = len(outline)
    top_z = 0.0
    bottom_z = -abs(float(thickness))
    verts = [(x, y, top_z) for x, y in outline] + [(x, y, bottom_z) for x, y in outline]

    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    _assign_material(obj, mat)
    obj["continuous_union"] = True
    obj["rect_bounds_m"] = f"{rect_x_min},{rect_x_max},{rect_y_min},{rect_y_max}"
    obj["circle_center_m"] = f"{cx},{cy}"
    obj["circle_radius_m"] = circle_radius
    obj["intersection_x_m"] = f"{ix_left},{ix_right}"
    return obj


def _point_inside_rect_circle_union(
    x: float,
    y: float,
    rect_bounds,
    circle_center,
    circle_radius: float,
    margin: float = 0.0,
) -> bool:
    rx0, rx1, ry0, ry1 = rect_bounds
    in_rect = (
        rx0 - margin <= x <= rx1 + margin
        and ry0 - margin <= y <= ry1 + margin
    )
    cx, cy = circle_center
    in_circle = math.hypot(x - cx, y - cy) <= circle_radius + margin
    return in_rect or in_circle


def _add_fluted_cylinder_wall(
    name: str,
    radius: float,
    height: float,
    location,
    mat,
    flutes: int = 48,
    flute_depth: float = 2.4,
    segments_per_flute: int = 8,
):
    """Create an open-ended inward-facing fluted cylindrical wall.

    Only the curved surface is generated: there are no top or bottom caps.
    The radial modulation evokes the shaft of a monumental Greek column.
    """
    segments = max(24, int(flutes) * max(4, int(segments_per_flute)))
    verts = []
    faces = []
    z0 = float(location[2])
    z1 = z0 + float(height)
    cx = float(location[0])
    cy = float(location[1])

    for i in range(segments):
        angle = math.tau * i / segments
        # Concave grooves: radius varies smoothly from the nominal wall radius
        # inward by flute_depth. Using cosine keeps every groove continuous.
        phase = math.tau * flutes * i / segments
        radial = radius - flute_depth * (0.5 + 0.5 * math.cos(phase))
        x = cx + math.cos(angle) * radial
        y = cy + math.sin(angle) * radial
        verts.append((x, y, z0))
        verts.append((x, y, z1))

    for i in range(segments):
        j = (i + 1) % segments
        # Winding is chosen so normals face inward toward the arena.
        faces.append((2 * i, 2 * j, 2 * j + 1, 2 * i + 1))

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    _assign_material(obj, mat)
    obj["open_cylinder"] = True
    obj["radius_m"] = radius
    obj["height_m"] = height
    obj["flutes"] = flutes
    obj["flute_depth_m"] = flute_depth
    return obj


def _add_open_cylinder_band(
    name: str,
    radius: float,
    height: float,
    z_bottom: float,
    location_xy,
    mat,
    segments: int = 192,
):
    """Add a thin decorative cylindrical band with no caps."""
    verts = []
    faces = []
    cx, cy = location_xy
    for i in range(segments):
        a = math.tau * i / segments
        x = cx + math.cos(a) * radius
        y = cy + math.sin(a) * radius
        verts.append((x, y, z_bottom))
        verts.append((x, y, z_bottom + height))
    for i in range(segments):
        j = (i + 1) % segments
        faces.append((2 * i, 2 * j, 2 * j + 1, 2 * i + 1))
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
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
        match = re.search(pattern, text, re.MULTILINE | re.DOTALL)
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

    layout_extension = dict(op.get("layout_extension", {}) or {})
    if layout_extension:
        sphere_radius_expected = float(mapping["sphere"]["radius_m"])
        platform_radius = float(layout_extension.get("sphere_platform_radius_m", sphere_radius_expected + 10.0))
        if platform_radius <= sphere_radius_expected:
            raise RuntimeError(
                f"Sphere platform radius must exceed the sphere radius: "
                f"platform={platform_radius}, sphere={sphere_radius_expected}"
            )
        layout_extension["sphere_platform_radius_m"] = platform_radius

        if "arena_water_radius_m" in layout_extension:
            arena_water_radius = float(layout_extension["arena_water_radius_m"])
            sphere_center_distance = abs(
                float(mapping["sphere"]["center_godot_m"][2])
                - float(mapping["water"]["center_godot_m"][2])
            )
            required_tangent_radius = sphere_center_distance + platform_radius
            if abs(arena_water_radius - required_tangent_radius) > 1e-6:
                raise RuntimeError(
                    "Arena water radius must be exactly internally tangent to "
                    f"the sphere platform: got {arena_water_radius}, "
                    f"required {required_tangent_radius}"
                )
            layout_extension["arena_water_radius_m"] = arena_water_radius
            layout_extension["required_tangent_radius_m"] = required_tangent_radius

        bpy.context.scene["kaos_layout_extension_json"] = json.dumps(layout_extension, sort_keys=True)

    stone = _material("Arena_Weathered_Marble", (0.48, 0.47, 0.43), 0.86)
    stone_dark = _material("Arena_Dark_Stone", (0.09, 0.095, 0.105), 0.82)
    stone_light = _material("Arena_Pale_Stone", (0.62, 0.60, 0.54), 0.78)
    gold = _material("Arena_Aged_Gold", (0.32, 0.20, 0.06), 0.42, 0.55)
    water = _material("Arena_Deep_Water", (0.018, 0.055, 0.075), 0.18, 0.08)
    rock = _material("Arena_Cliff_Rock", (0.12, 0.115, 0.105), 0.94)

    texture_config = layout_extension.get("texture_sets", {}) if layout_extension else {}
    if texture_config:
        scene_id = str(op.get("scene_id") or bpy.context.scene.get("scene_id") or "kaos_arena")
        floor_cfg = texture_config.get("floor", {})
        wall_cfg = texture_config.get("wall", {})
        if floor_cfg:
            floor_maps = _polyhaven_texture_set(
                root_path,
                scene_id,
                str(floor_cfg.get("asset_id", "floor_tiles_02")),
                str(floor_cfg.get("resolution", "1k")),
            )
            stone_light = _pbr_material_from_maps(
                "Arena_PBR_Floor",
                floor_maps,
                tuple(floor_cfg.get("tiling", [58.0, 58.0, 58.0])),
                float(floor_cfg.get("normal_strength", 0.6)),
            )
        if wall_cfg:
            wall_maps = _polyhaven_texture_set(
                root_path,
                scene_id,
                str(wall_cfg.get("asset_id", "plaster_stone_wall_01")),
                str(wall_cfg.get("resolution", "1k")),
            )
            stone = _pbr_material_from_maps(
                "Arena_PBR_AncientStone",
                wall_maps,
                tuple(wall_cfg.get("tiling", [42.0, 42.0, 42.0])),
                float(wall_cfg.get("normal_strength", 0.85)),
            )
            rock = stone

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
    xb = mapping["battlemap"]["x_bounds_m"]
    yb = mapping["battlemap"]["z_bounds_m"]

    # Optional V7 extension: keep the original 120 m width but extend the
    # rectangle away from the sphere until its two far corners touch the
    # flooded arena boundary exactly.
    effective_rect_y_max = float(yb[1])
    if layout_extension and bool(layout_extension.get("extend_rect_to_arena_edge", False)):
        arena_radius_for_extension = float(
            layout_extension.get("arena_water_radius_m", mapping["water"]["radius_m"])
        )
        rect_half_width = max(abs(float(xb[0])), abs(float(xb[1])))
        if rect_half_width >= arena_radius_for_extension:
            raise RuntimeError("Rectangular floor is wider than the arena radius.")
        effective_rect_y_max = (
            float(mapping["water"]["center_godot_m"][2])
            + math.sqrt(arena_radius_for_extension ** 2 - rect_half_width ** 2)
        )
        layout_extension["extended_rect_y_max_m"] = effective_rect_y_max
        bpy.context.scene["kaos_layout_extension_json"] = json.dumps(layout_extension, sort_keys=True)

    continuous_walkable = bool(
        layout_extension.get("continuous_walkable_surface", False)
        if layout_extension else False
    )

    # V5 replaces the old overlapping rectangle + circular platform with one
    # watertight union mesh. Older jobs retain the original rectangular floor.
    if not continuous_walkable:
        floor = _add_box(
            "COMBAT_TacticalFloor_120x180m",
            (floor_w * 0.5 * scale, floor_d * 0.5 * scale, 0.35 * scale),
            (0.0, floor_center_y * scale, -0.35 * scale),
            stone,
        )
        floor["godot_role"] = "Board/FloorCollision"
        floor["size_m"] = f"{floor_w}x{floor_d}"
        floor["center_godot_m"] = f"0,0,{floor_center_y}"

        _add_box(
            "ArenaInnerPaving",
            ((floor_w - 3.0) * 0.5 * scale, (floor_d - 3.0) * 0.5 * scale, 0.10 * scale),
            (0.0, floor_center_y * scale, 0.10 * scale),
            stone_light,
        )

    # Godot defines R337m. V4 may deliberately enlarge the flooded arena
    # while preserving the original value in combat_mapping for traceability.
    effective_water_radius = float(
        layout_extension.get("arena_water_radius_m", water_radius)
        if layout_extension else water_radius
    )
    water_obj = _add_cylinder(
        f"COMBAT_WaterBasin_R{effective_water_radius:g}m",
        effective_water_radius * scale,
        0.20 * scale,
        (0.0, water_center_y * scale, water_height * scale),
        water,
        vertices=192,
    )
    water_obj["godot_role"] = "Board/WaterSurface"
    water_obj["source_godot_radius_m"] = water_radius
    water_obj["radius_m"] = effective_water_radius

    if layout_extension and bool(layout_extension.get("arena_wall_enabled", False)):
        wall_height = float(layout_extension.get("arena_wall_height_m", 60.0))
        wall_flutes = int(layout_extension.get("arena_wall_flutes", 48))
        wall_flute_depth = float(layout_extension.get("arena_wall_flute_depth_m", 2.4))
        wall = _add_fluted_cylinder_wall(
            "SCENERY_GreekFlutedArenaWall",
            effective_water_radius * scale,
            wall_height * scale,
            (0.0, water_center_y * scale, 0.0),
            stone,
            flutes=wall_flutes,
            flute_depth=wall_flute_depth * scale,
            segments_per_flute=8,
        )
        wall["arena_wall_style"] = "greek_fluted_column"
        wall["center_godot_m"] = f"0,0,{water_center_y}"

        # Monumental base/capital mouldings: still only curved surfaces, never caps.
        _add_open_cylinder_band(
            "SCENERY_GreekWall_BaseBand",
            (effective_water_radius - wall_flute_depth * 0.35) * scale,
            4.0 * scale,
            0.0,
            (0.0, water_center_y * scale),
            stone,
            segments=256,
        )
        _add_open_cylinder_band(
            "SCENERY_GreekWall_CapitalBand",
            (effective_water_radius - wall_flute_depth * 0.20) * scale,
            5.0 * scale,
            (wall_height - 5.0) * scale,
            (0.0, water_center_y * scale),
            stone,
            segments=256,
        )

    # Additive combat extension. V5 can merge the original rectangle and
    # the R230m sphere platform into one continuous watertight walkable mesh.
    if layout_extension:
        platform_radius = float(layout_extension["sphere_platform_radius_m"])
        platform_thickness = float(layout_extension.get("platform_thickness_m", 0.7))

        if continuous_walkable:
            rect_x_min, rect_x_max = xb
            rect_y_min = yb[0]
            rect_y_max = effective_rect_y_max
            if bool(layout_extension.get("harmonious_walkable_transition", False)):
                walkable = _add_harmonious_rect_circle_prism(
                    "COMBAT_ContinuousArenaFloor",
                    rect_x_min * scale,
                    rect_x_max * scale,
                    rect_y_min * scale,
                    rect_y_max * scale,
                    (sphere_blender[0] * scale, sphere_blender[1] * scale),
                    platform_radius * scale,
                    platform_thickness * scale,
                    stone_light,
                    blend_start_y=float(layout_extension.get("transition_start_y_m", 72.0)) * scale,
                    circle_join_angle_deg=float(layout_extension.get("transition_circle_angle_deg", 32.0)),
                    transition_segments=28,
                    circle_segments=200,
                )
            else:
                walkable = _add_rect_circle_union_prism(
                    "COMBAT_ContinuousArenaFloor",
                    rect_x_min * scale,
                    rect_x_max * scale,
                    rect_y_min * scale,
                    rect_y_max * scale,
                    (sphere_blender[0] * scale, sphere_blender[1] * scale),
                    platform_radius * scale,
                    platform_thickness * scale,
                    stone_light,
                    arc_segments=160,
                )
            walkable["godot_role"] = "Board/FloorCollision + V5 sphere platform"
            walkable["combat_extension"] = "kaos_v5"
            walkable["source_battlemap_size_m"] = f"{floor_w}x{floor_d}"
            walkable["sphere_platform_radius_m"] = platform_radius
        else:
            approach_width = float(layout_extension.get("approach_width_m", 100.0))
            approach_into_platform = float(layout_extension.get("approach_into_platform_m", 55.0))
            approach_floor_overlap = float(layout_extension.get("approach_floor_overlap_m", 6.0))

            platform = _add_cylinder(
                f"COMBAT_SpherePlatform_R{platform_radius:g}m",
                platform_radius * scale,
                platform_thickness * scale,
                (
                    sphere_blender[0] * scale,
                    sphere_blender[1] * scale,
                    -platform_thickness * 0.5 * scale,
                ),
                stone,
                vertices=160,
            )
            platform["combat_extension"] = "kaos_v3"
            platform["radius_m"] = platform_radius
            platform["center_godot_m"] = f"{sphere_godot[0]},0,{sphere_godot[2]}"

            _add_cylinder(
                "SpherePlatformInnerPaving",
                max(1.0, platform_radius - 3.0) * scale,
                0.12 * scale,
                (
                    sphere_blender[0] * scale,
                    sphere_blender[1] * scale,
                    0.06 * scale,
                ),
                stone_light,
                vertices=160,
            )

            platform_front_y = sphere_blender[1] + platform_radius
            approach_start_y = yb[0] + approach_floor_overlap
            approach_end_y = platform_front_y - approach_into_platform
            if approach_start_y <= approach_end_y:
                raise RuntimeError("Kaos V3 approach does not overlap the sphere platform enough.")
            approach_depth = approach_start_y - approach_end_y
            approach_center_y = (approach_start_y + approach_end_y) * 0.5

            approach = _add_box(
                f"COMBAT_SphereApproach_{approach_width:g}m",
                (
                    approach_width * 0.5 * scale,
                    approach_depth * 0.5 * scale,
                    platform_thickness * 0.5 * scale,
                ),
                (
                    0.0,
                    approach_center_y * scale,
                    -platform_thickness * 0.5 * scale,
                ),
                stone,
            )
            approach["combat_extension"] = "kaos_v3"

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
    corner_offset = 2.0
    for idx, (x, y) in enumerate([
        (xb[0] - corner_offset, yb[0] - corner_offset),
        (xb[1] + corner_offset, yb[0] - corner_offset),
        (xb[0] - corner_offset, effective_rect_y_max + corner_offset),
        (xb[1] + corner_offset, effective_rect_y_max + corner_offset),
    ]):
        _add_box(
            f"BoundaryPlinth_{idx}",
            (1.5 * scale, 1.5 * scale, 0.8 * scale),
            (x * scale, y * scale, 0.8 * scale),
            stone_dark,
        )

    # Columns are scenic debris in the flooded zone, not a semicircular
    # colonnade. Sample uniformly over area and reject any point that falls on
    # the walkable floor/platform or too close to the cylindrical wall.
    random_water_columns = bool(
        layout_extension.get("random_water_columns", False)
        if layout_extension else False
    )
    if random_water_columns:
        target_columns = int(layout_extension.get("random_water_column_count", 16))
        wall_margin = float(layout_extension.get("random_water_column_wall_margin_m", 24.0))
        walkable_margin = float(layout_extension.get("random_water_column_walkable_margin_m", 10.0))
        water_sample_radius = max(1.0, effective_water_radius - wall_margin)
        placed = []
        attempts = 0

        while len(placed) < target_columns and attempts < target_columns * 300:
            attempts += 1
            a = rng.uniform(0.0, math.tau)
            rr = math.sqrt(rng.random()) * water_sample_radius
            x = math.cos(a) * rr
            y = water_center_y + math.sin(a) * rr

            if bool(layout_extension.get("harmonious_walkable_transition", False)):
                outline = _harmonious_walkable_outline(
                    xb[0] - walkable_margin,
                    xb[1] + walkable_margin,
                    effective_rect_y_max + walkable_margin,
                    (sphere_blender[0], sphere_blender[1]),
                    float(layout_extension["sphere_platform_radius_m"]) + walkable_margin,
                    float(layout_extension.get("transition_start_y_m", 72.0)) + walkable_margin,
                    circle_join_angle_deg=float(layout_extension.get("transition_circle_angle_deg", 32.0)),
                    transition_segments=28,
                    circle_segments=200,
                )
                if _point_in_polygon_2d(x, y, outline):
                    continue
            elif _point_inside_rect_circle_union(
                x,
                y,
                (xb[0], xb[1], yb[0], effective_rect_y_max),
                (sphere_blender[0], sphere_blender[1]),
                float(layout_extension["sphere_platform_radius_m"]),
                margin=walkable_margin,
            ):
                continue
            if any(math.hypot(x - px, y - py) < 28.0 for px, py in placed):
                continue

            placed.append((x, y))
            height = rng.uniform(14.0, 31.0)
            broken = rng.uniform(0.42, 1.0)
            radius = rng.uniform(2.0, 3.2)
            col = _add_column(
                f"FloodedColumn_{len(placed)-1:02d}",
                (x * scale, y * scale, water_height * scale),
                height * scale,
                radius * scale,
                stone,
                broken=broken,
            )
            col.rotation_euler.z = rng.uniform(-math.pi, math.pi)

        if len(placed) != target_columns:
            raise RuntimeError(
                f"Could place only {len(placed)}/{target_columns} flooded columns "
                f"after {attempts} attempts."
            )
    else:
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



def _emissive_material(name: str, base_color, strength: float = 6.0, metallic: float = 0.0):
    mat = _material(name, base_color, roughness=0.32, metallic=metallic)
    bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.use_nodes else None
    if bsdf is not None:
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (*base_color, 1.0)
        elif "Emission" in bsdf.inputs:
            bsdf.inputs["Emission"].default_value = (*base_color, 1.0)
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def _surface_curve(name: str, points, bevel_depth: float, material):
    curve = bpy.data.curves.new(name, type="CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = bevel_depth
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for i, point in enumerate(points):
        spline.points[i].co = (*point, 1.0)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    curve.materials.append(material)
    return obj


def _sphere_point(center, radius: float, latitude: float, longitude: float):
    c_lat = math.cos(latitude)
    return (
        center[0] + radius * c_lat * math.sin(longitude),
        center[1] + radius * c_lat * math.cos(longitude),
        center[2] + radius * math.sin(latitude),
    )


def build_titan_prison_sphere(op: dict, root_path: Path) -> None:
    """Build the Klothys Titan prison as a standalone, arena-aligned Blender asset."""
    rng = random.Random(int(op.get("seed", 20261002)))
    scale = float(op.get("scale", 1.0))
    mapping = _kaos_mapping_from_godot(root_path)
    _validate_expected_mapping(mapping, op.get("expected_mapping", {}))
    bpy.context.scene["kaos_combat_mapping_json"] = json.dumps(mapping, sort_keys=True)

    sphere_radius = float(mapping["sphere"]["radius_m"])
    sphere_godot = mapping["sphere"]["center_godot_m"]
    center = (
        sphere_godot[0] * scale,
        sphere_godot[2] * scale,
        sphere_godot[1] * scale,
    )
    radius = sphere_radius * scale

    stone = _material("TitanPrison_ObsidianStone", (0.105, 0.095, 0.09), 0.78, 0.04)
    titan_stone = _material("TitanPrison_TitanStone", (0.19, 0.16, 0.135), 0.66, 0.03)
    gold = _emissive_material("TitanPrison_AgedDivineGold", (0.34, 0.15, 0.035), 0.65, 0.72)
    energy = _emissive_material("TitanPrison_InnerEnergy", (1.0, 0.12, 0.018), 18.0, 0.05)

    root = bpy.data.collections.new("KLOTHYS_TITAN_PRISON_SPHERE")
    bpy.context.scene.collection.children.link(root)
    before = set(bpy.context.scene.objects)

    anchor = bpy.data.objects.new("ALIGN_KLOTHYS_SPHERE_CENTER", None)
    bpy.context.scene.collection.objects.link(anchor)
    anchor.location = center
    anchor.empty_display_type = "SPHERE"
    anchor.empty_display_size = 5.0 * scale
    anchor["reference_radius_m"] = sphere_radius
    anchor["center_godot_m"] = ",".join(str(v) for v in sphere_godot)

    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=160,
        ring_count=96,
        radius=radius,
        location=center,
    )
    shell = bpy.context.object
    shell.name = "Klothys_PrisonShell_R220m"
    shell["godot_role"] = "KlothisRoot/SphereVisual"
    shell["reference_radius_m"] = sphere_radius
    shell["center_godot_m"] = ",".join(str(v) for v in sphere_godot)
    _assign_material(shell, stone)

    # Keep the nominal 220 m sphere unchanged while adding only shallow,
    # large-scale surface breakup. The exact scale/center remain derived from Godot.
    tex = bpy.data.textures.new("TitanPrison_RockBreakup", type="CLOUDS")
    tex.noise_scale = 0.72
    tex.noise_depth = 2
    disp = shell.modifiers.new("SubtleRockDeformation", type="DISPLACE")
    disp.texture = tex
    disp.texture_coords = "LOCAL"
    disp.strength = 1.65 * scale
    disp.mid_level = 0.5

    # Reuse the exact relief asset used by Godot. Its placements mirror
    # encounter/titan_reliefs.gd, but sit fractionally nearer the skin so the
    # imprisoned Titans read as bodies/faces physically pressing through it.
    relief_path = root_path / "encounter" / "assets" / "characters" / "titan_relief.glb"
    if not relief_path.exists():
        raise FileNotFoundError(f"Titan relief source missing: {relief_path}")

    imported_before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(relief_path))
    imported = [obj for obj in bpy.context.scene.objects if obj not in imported_before]
    sources = [obj for obj in imported if obj.type == "MESH"]
    if not sources:
        raise RuntimeError("titan_relief.glb imported without a mesh")
    source = max(sources, key=lambda obj: len(obj.data.vertices) if obj.data else 0)
    source.hide_render = True
    source.hide_set(True)

    titan_instances = []
    for i in range(16):
        row = i // 4
        yaw = -0.95 + float(i % 4) * 0.63 + (row % 2) * 0.12
        if row == 1 and i % 4 in (1, 2):
            yaw = -0.48 if i % 4 == 1 else 0.48
        pitch = -0.80 + row * 0.51
        n = mathutils.Vector((
            math.sin(yaw) * math.cos(pitch),
            math.cos(yaw) * math.cos(pitch),
            math.sin(pitch),
        )).normalized()

        titan = source.copy()
        titan.data = source.data
        bpy.context.scene.collection.objects.link(titan)
        titan.name = f"TitanPressureRelief_{i:02d}"
        titan.hide_render = False
        titan.hide_set(False)

        # Godot uses radius 205 m. 208 m keeps the same composition while making
        # the outer silhouette more legible against a 220 m shell.
        titan.location = mathutils.Vector(center) + n * (208.0 * scale)
        titan.rotation_euler = n.to_track_quat("Z", "Y").to_euler()
        roll = -0.12 if i % 2 == 0 else 0.14
        titan.rotation_euler.rotate_axis("Z", roll)
        s = (3.8 + (i % 3) * 0.45) * scale
        titan.scale = (s, s, s)
        _assign_material(titan, titan_stone)
        titan["source_role"] = "Godot titan_reliefs.gd"
        titan_instances.append(titan)

        # Soft under-form blends the relief into the shell so it reads as a
        # deformation rather than a separate statue pasted onto the surface.
        under_center = mathutils.Vector(center) + n * (214.5 * scale)
        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=3,
            radius=1.0,
            location=under_center,
        )
        under = bpy.context.object
        under.name = f"TitanSurfaceBulge_{i:02d}"
        under.rotation_euler = n.to_track_quat("Z", "Y").to_euler()
        under.scale = (
            (10.5 + (i % 3) * 1.2) * scale,
            (7.5 + (i % 2) * 1.0) * scale,
            (4.8 + (i % 3) * 0.55) * scale,
        )
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        _assign_material(under, stone)

    for obj in imported:
        if obj == source:
            continue
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.objects.remove(source, do_unlink=True)

    # Divine restraints: three thin, readable bands offset just above the stone.
    for idx, rotation in enumerate(((0.0, 0.0, 0.0), (0.62, 0.0, 0.38), (-0.55, 0.28, -0.46))):
        bpy.ops.mesh.primitive_torus_add(
            major_radius=(sphere_radius + 2.3) * scale,
            minor_radius=0.46 * scale,
            major_segments=192,
            minor_segments=10,
            location=center,
            rotation=rotation,
        )
        band = bpy.context.object
        band.name = f"DivineBinding_{idx:02d}"
        _assign_material(band, gold)

    # Irregular emissive fissures are lightweight curves, not destructive booleans.
    # They suggest the pressure and divine energy under the shell while keeping
    # the asset fast to regenerate and easy to edit.
    crack_count = int(op.get("crack_count", 11))
    for crack_index in range(crack_count):
        latitude = rng.uniform(-0.95, 0.95)
        longitude = rng.uniform(-1.08, 1.08) if crack_index < 8 else rng.uniform(-math.pi, math.pi)
        points = []
        angular_points = []
        lat = latitude
        lon = longitude
        segments = rng.randint(9, 17)
        for j in range(segments):
            angular_points.append((lat, lon))
            points.append(_sphere_point(center, (sphere_radius + 0.9) * scale, lat, lon))
            lat += rng.uniform(-0.055, 0.055)
            lon += rng.uniform(0.045, 0.11) * (-1 if crack_index % 3 == 0 else 1)
            lat = max(-1.34, min(1.34, lat))
        _surface_curve(
            f"EnergyFissure_{crack_index:02d}",
            points,
            rng.uniform(0.42, 0.82) * scale,
            energy,
        )

        if crack_index % 2 == 0 and len(points) > 5:
            branch_start = rng.randint(3, len(points) - 3)
            b_lat, b_lon = angular_points[branch_start]
            branch_points = []
            for _ in range(rng.randint(4, 7)):
                branch_points.append(_sphere_point(center, (sphere_radius + 1.0) * scale, b_lat, b_lon))
                b_lat += rng.uniform(-0.045, 0.045)
                b_lon += rng.uniform(-0.085, 0.085)
            _surface_curve(
                f"EnergyFissure_{crack_index:02d}_Branch",
                branch_points,
                rng.uniform(0.24, 0.42) * scale,
                energy,
            )

    # Sparse floating fragments reinforce the "strained prison" silhouette without
    # changing the gameplay-scale sphere or adding a platform.
    for i in range(24):
        u = rng.uniform(-1.0, 1.0)
        theta = rng.uniform(-math.pi, math.pi)
        ring = math.sqrt(max(0.0, 1.0 - u * u))
        n = mathutils.Vector((ring * math.cos(theta), ring * math.sin(theta), u))
        distance = rng.uniform(sphere_radius + 6.0, sphere_radius + 22.0) * scale
        loc = mathutils.Vector(center) + n * distance
        _add_rock(
            f"PrisonFragment_{i:02d}",
            loc,
            (
                rng.uniform(0.8, 2.8) * scale,
                rng.uniform(0.7, 2.4) * scale,
                rng.uniform(0.6, 2.0) * scale,
            ),
            stone,
            9200 + i,
        )

    # Preview lighting belongs to the asset file; importing the collection into the
    # arena only requires KLOTHYS_TITAN_PRISON_SPHERE.
    key = bpy.data.lights.new("TitanPrison_Key", type="AREA")
    key.energy = 52000
    key.shape = "DISK"
    key.size = 260 * scale
    key.color = (0.36, 0.45, 0.75)
    key_obj = bpy.data.objects.new("TitanPrison_Key", key)
    bpy.context.scene.collection.objects.link(key_obj)
    key_obj["preview_only"] = True
    key_obj.location = (
        center[0] - 320 * scale,
        center[1] + 360 * scale,
        center[2] + 300 * scale,
    )
    key_obj.rotation_euler = (math.radians(52), 0.0, math.radians(-42))

    rim = bpy.data.lights.new("TitanPrison_Rim", type="AREA")
    rim.energy = 36000
    rim.shape = "DISK"
    rim.size = 220 * scale
    rim.color = (1.0, 0.22, 0.055)
    rim_obj = bpy.data.objects.new("TitanPrison_Rim", rim)
    bpy.context.scene.collection.objects.link(rim_obj)
    rim_obj["preview_only"] = True
    rim_obj.location = (
        center[0] + 250 * scale,
        center[1] + 390 * scale,
        center[2] + 40 * scale,
    )
    rim_obj.rotation_euler = (math.radians(78), 0.0, math.radians(145))

    bpy.context.scene.world.color = (0.006, 0.008, 0.016)
    bpy.context.scene["titan_prison_asset_collection"] = root.name
    bpy.context.scene["titan_prison_reference_radius_m"] = sphere_radius
    bpy.context.scene["titan_prison_center_godot_m"] = ",".join(str(v) for v in sphere_godot)

    generated = [obj for obj in bpy.context.scene.objects if obj not in before]
    for obj in generated:
        if bool(obj.get("preview_only", False)):
            continue
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


def render_preview_spec(root: Path, spec: dict, runtime_output_root: Path | None = None) -> None:
    _set_camera_pose(
        vec3(spec.get("location"), (150.0, -165.0, 110.0)),
        vec3(spec.get("look_at"), (0.0, 35.0, 35.0)),
        float(spec.get("lens", 50.0)),
    )
    render_preview(
        output_path(root, spec["path"], runtime_output_root),
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
    elif kind == "build_titan_prison_sphere":
        build_titan_prison_sphere(op, root)
    elif kind == "build_titan_prison_sphere_v2":
        from titan_prison_v2 import build_titan_prison_sphere_v2
        mapping = _kaos_mapping_from_godot(root)
        _validate_expected_mapping(mapping, op.get("expected_mapping", {}))
        bpy.context.scene["kaos_combat_mapping_json"] = json.dumps(mapping, sort_keys=True)
        build_titan_prison_sphere_v2(op, root, mapping)
    else:
        raise ValueError(f"Unsupported operation: {kind!r}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--job", required=True)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output-root")
    args = parser.parse_args(argv)

    if tuple(bpy.app.version[:2]) != REQUIRED_VERSION:
        raise RuntimeError(f"Expected Blender 5.2.x, found {bpy.app.version_string}")

    root = Path(args.project_root).resolve()
    runtime_output_root = Path(args.output_root).resolve() if args.output_root else None
    if runtime_output_root is not None:
        runtime_output_root.mkdir(parents=True, exist_ok=True)
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
        operation = dict(operation)
        operation.setdefault("scene_id", job.get("scene_id", job_path.stem))
        print(f"BLENDER_AGENT_OP {index}: {operation.get('op')}", flush=True)
        execute_operation(operation, root)

    outputs = job.get("outputs", {})
    if outputs.get("previews"):
        for preview_index, spec in enumerate(outputs["previews"], start=1):
            print(f"BLENDER_AGENT_OUTPUT preview_{preview_index}", flush=True)
            render_preview_spec(root, spec, runtime_output_root)
    elif outputs.get("preview"):
        print("BLENDER_AGENT_OUTPUT preview", flush=True)
        render_preview(
            output_path(root, outputs["preview"], runtime_output_root),
            int(outputs.get("preview_width", 960)),
            int(outputs.get("preview_height", 540)),
        )
    if outputs.get("report"):
        print("BLENDER_AGENT_OUTPUT report", flush=True)
        scene_report(output_path(root, outputs["report"], runtime_output_root), job_path, job)
    if outputs.get("glb"):
        print("BLENDER_AGENT_OUTPUT glb", flush=True)
        export_glb(output_path(root, outputs["glb"], runtime_output_root))
    if outputs.get("blend"):
        print("BLENDER_AGENT_OUTPUT blend", flush=True)
        save_blend(output_path(root, outputs["blend"], runtime_output_root))

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
