from __future__ import annotations

import math
import os
import random
import urllib.request
from pathlib import Path

import bpy
import mathutils


DEMON_URL = "https://raw.githubusercontent.com/yerdaulet-damir/liminal/ff9ee5b57e2531b4f8841d6e7564283f943f6d34/client/public/models/monster_Demon.gltf"
ORC_URL = "https://raw.githubusercontent.com/yerdaulet-damir/liminal/ff9ee5b57e2531b4f8841d6e7564283f943f6d34/client/public/models/monster_Orc.gltf"
SOURCE_LICENSE = "Quaternius Ultimate Monsters - CC0 1.0"


def _assign_material(obj, material) -> None:
    if getattr(obj, "data", None) is not None and hasattr(obj.data, "materials"):
        obj.data.materials.clear()
        obj.data.materials.append(material)


def _stone_material(name: str, dark=(0.105, 0.085, 0.075, 1.0), light=(0.25, 0.20, 0.16, 1.0)):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    noise = nodes.new("ShaderNodeTexNoise")
    ramp = nodes.new("ShaderNodeValToRGB")
    bump_noise = nodes.new("ShaderNodeTexNoise")
    bump = nodes.new("ShaderNodeBump")

    noise.inputs["Scale"].default_value = 2.2
    noise.inputs["Detail"].default_value = 5.0
    noise.inputs["Roughness"].default_value = 0.72
    bump_noise.inputs["Scale"].default_value = 7.5
    bump_noise.inputs["Detail"].default_value = 4.0
    bump_noise.inputs["Roughness"].default_value = 0.78
    bump.inputs["Strength"].default_value = 0.55
    bump.inputs["Distance"].default_value = 0.28

    ramp.color_ramp.elements[0].position = 0.24
    ramp.color_ramp.elements[0].color = dark
    ramp.color_ramp.elements[1].position = 0.80
    ramp.color_ramp.elements[1].color = light

    bsdf.inputs["Roughness"].default_value = 0.87
    bsdf.inputs["Metallic"].default_value = 0.03

    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(bump_noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def _simple_material(name: str, color, roughness=0.7, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def _emissive_material(name: str, color, strength: float):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.28
    if "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
    elif "Emission" in bsdf.inputs:
        bsdf.inputs["Emission"].default_value = (*color, 1.0)
    if "Emission Strength" in bsdf.inputs:
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def _curve_object(name: str, points, bevel_depth: float, material, cyclic=False):
    curve = bpy.data.curves.new(name, type="CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = bevel_depth
    curve.bevel_resolution = 3
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for i, point in enumerate(points):
        spline.points[i].co = (*point, 1.0)
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    curve.materials.append(material)
    return obj


def _direction(yaw: float, latitude: float):
    c = math.cos(latitude)
    return mathutils.Vector((
        math.sin(yaw) * c,
        math.cos(yaw) * c,
        math.sin(latitude),
    )).normalized()


def _basis_for_direction(n):
    up = mathutils.Vector((0.0, 0.0, 1.0))
    tx = up.cross(n)
    if tx.length < 1e-5:
        tx = mathutils.Vector((1.0, 0.0, 0.0))
    tx.normalize()
    tz = n.cross(tx).normalized()
    return tx, tz


def _surface_point(center, radius: float, yaw: float, latitude: float):
    return mathutils.Vector(center) + _direction(yaw, latitude) * radius


def _asset_root(root_path: Path) -> Path:
    configured = os.environ.get("VTT_BLENDER_ASSET_ROOT", "").strip()
    root = Path(configured) if configured else (root_path / ".vtt_assets")
    path = root / "downloads" / "klothys_titan_prison_v2"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _fetch(url: str, destination: Path) -> Path:
    if destination.exists() and destination.stat().st_size > 4096:
        return destination
    tmp = destination.with_suffix(destination.suffix + ".part")
    request = urllib.request.Request(url, headers={"User-Agent": "VTT-Blender/2.0"})
    with urllib.request.urlopen(request, timeout=120) as response, tmp.open("wb") as handle:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            handle.write(chunk)
    tmp.replace(destination)
    return destination


def _import_rigged(path: Path, frame: int):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    meshes = [obj for obj in imported if obj.type == "MESH"]
    armatures = [obj for obj in imported if obj.type == "ARMATURE"]
    if not meshes:
        raise RuntimeError(f"No mesh imported from {path}")

    bpy.context.scene.frame_set(frame)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    return imported, meshes, armatures, depsgraph


def _collect_evaluated_geometry(mesh_objects, depsgraph):
    vertices = []
    faces = []
    for obj in mesh_objects:
        eval_obj = obj.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(
            eval_obj,
            preserve_all_data_layers=False,
            depsgraph=depsgraph,
        )
        offset = len(vertices)
        matrix = obj.matrix_world
        vertices.extend(matrix @ v.co for v in mesh.vertices)
        for poly in mesh.polygons:
            faces.append(tuple(offset + i for i in poly.vertices))
        bpy.data.meshes.remove(mesh)
    return vertices, faces


def _remove_import(imported) -> None:
    for obj in list(imported):
        if obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)


def _radial_relief(
    name: str,
    source_vertices,
    source_faces,
    center,
    radius: float,
    yaw: float,
    latitude: float,
    patch_width_angle: float,
    patch_height_angle: float,
    stone,
    seed: int,
):
    if not source_vertices:
        raise RuntimeError(f"{name}: empty source geometry")
    rng = random.Random(seed)

    min_x = min(v.x for v in source_vertices)
    max_x = max(v.x for v in source_vertices)
    min_y = min(v.y for v in source_vertices)
    max_y = max(v.y for v in source_vertices)
    min_z = min(v.z for v in source_vertices)
    max_z = max(v.z for v in source_vertices)
    sx = max(max_x - min_x, 1e-6)
    sy = max(max_y - min_y, 1e-6)
    sz = max(max_z - min_z, 1e-6)

    n = _direction(yaw, latitude)
    tx, tz = _basis_for_direction(n)
    mapped = []

    for co in source_vertices:
        nx = ((co.x - min_x) / sx) * 2.0 - 1.0
        ny = ((co.y - min_y) / sy) * 2.0 - 1.0
        nz = ((co.z - min_z) / sz) * 2.0 - 1.0

        nx *= 0.92 - 0.12 * (nz * nz)
        nz = math.copysign(abs(nz) ** 0.88, nz)
        nx += math.sin((nz + 1.0) * 3.1 + seed) * 0.035
        nz += math.sin((nx + 1.0) * 2.3 + seed * 0.3) * 0.025

        horizontal = nx * patch_width_angle
        vertical = nz * patch_height_angle
        patch_dir = (
            n
            + tx * math.tan(horizontal)
            + tz * math.tan(vertical)
        ).normalized()

        edge = min(1.0, math.sqrt((nx * 0.88) ** 2 + (nz * 0.78) ** 2))
        body_bulge = max(0.0, 1.0 - edge ** 1.65)
        depth_term = ny * 2.6
        radial = radius - 2.0 + body_bulge * 18.0 + depth_term * 1.15
        radial += rng.uniform(-0.20, 0.20)
        mapped.append(mathutils.Vector(center) + patch_dir * radial)

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(mapped, [], source_faces)
    mesh.update()
    for poly in mesh.polygons:
        poly.use_smooth = True

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    _assign_material(obj, stone)
    obj["relief_style"] = "radially_wrapped_carbonite"
    obj["source_license"] = SOURCE_LICENSE

    tex = bpy.data.textures.new(name + "_RockTexture", type="CLOUDS")
    tex.noise_scale = 0.52
    tex.noise_depth = 2
    disp = obj.modifiers.new("CreatureStoneBreakup", type="DISPLACE")
    disp.texture = tex
    disp.texture_coords = "LOCAL"
    disp.strength = 1.15
    disp.mid_level = 0.5

    return obj


def _pressure_tendrils(prefix: str, center, radius: float, yaw: float, stone, rng: random.Random, side_sign: float):
    for i in range(6):
        start_lat = rng.uniform(-0.58, 0.62)
        start_yaw = yaw + side_sign * rng.uniform(0.18, 0.38)
        points = []
        lat = start_lat
        ang = start_yaw
        length = rng.randint(6, 10)
        for step in range(length):
            points.append(tuple(_surface_point(center, radius + rng.uniform(3.0, 6.5), ang, lat)))
            ang += side_sign * rng.uniform(0.035, 0.075)
            lat += rng.uniform(-0.045, 0.045)
        _curve_object(
            f"{prefix}_StoneTendril_{i:02d}",
            points,
            rng.uniform(1.0, 2.4),
            stone,
        )


def _crack_pair(name: str, points, groove, glow, width: float):
    _curve_object(name + "_Groove", points, width * 1.85, groove)
    center_guess = mathutils.Vector((0.0, -230.0, 385.0))
    glow_points = []
    for point in points:
        p = mathutils.Vector(point)
        direction = (p - center_guess).normalized()
        glow_points.append(tuple(p + direction * 1.15))
    _curve_object(name + "_Glow", glow_points, width * 0.82, glow)


def _add_cracks(center, radius: float, groove, glow, rng: random.Random):
    crack_index = 0
    for side in (-1.0, 1.0):
        for _ in range(10):
            yaw = side * rng.uniform(0.54, 1.36)
            lat = rng.uniform(-0.82, 0.82)
            points = []
            count = rng.randint(6, 11)
            for step in range(count):
                points.append(tuple(_surface_point(center, radius + 3.25, yaw, lat)))
                yaw += side * rng.uniform(0.025, 0.07)
                lat += rng.uniform(-0.055, 0.055)
                if abs(yaw) < 0.50:
                    yaw = side * 0.50
            _crack_pair(
                f"TitanStressCrack_{crack_index:02d}",
                points,
                groove,
                glow,
                rng.uniform(0.32, 0.62),
            )
            if crack_index % 3 == 0 and len(points) > 4:
                b_yaw = side * rng.uniform(0.72, 1.30)
                b_lat = lat + rng.uniform(-0.15, 0.15)
                branch = []
                for _ in range(rng.randint(4, 7)):
                    branch.append(tuple(_surface_point(center, radius + 3.35, b_yaw, b_lat)))
                    b_yaw += rng.uniform(-0.05, 0.05)
                    b_lat += rng.uniform(-0.06, 0.06)
                _crack_pair(
                    f"TitanStressCrack_{crack_index:02d}_Branch",
                    branch,
                    groove,
                    glow,
                    rng.uniform(0.20, 0.38),
                )
            crack_index += 1


def _surface_ring(name: str, center, radius: float, yaw: float, latitude: float, size: float, groove, glow):
    n = _direction(yaw, latitude)
    tx, tz = _basis_for_direction(n)
    points = []
    segments = 48
    angular_size = size / radius
    for i in range(segments):
        a = (i / segments) * math.tau
        direction = (
            n
            + tx * (math.cos(a) * angular_size)
            + tz * (math.sin(a) * angular_size)
        ).normalized()
        points.append(tuple(mathutils.Vector(center) + direction * (radius + 3.15)))
    _curve_object(name + "_Groove", points, 1.05, groove, cyclic=True)
    glow_points = []
    for point in points:
        p = mathutils.Vector(point)
        glow_points.append(tuple(p + (p - mathutils.Vector(center)).normalized() * 1.25))
    _curve_object(name + "_Glow", glow_points, 0.52, glow, cyclic=True)

    for j, angle in enumerate((0.0, 2.1, 4.2)):
        inner = []
        for k in range(5):
            t = 0.25 + 0.13 * k
            offset = (
                tx * (math.cos(angle) * angular_size * t)
                + tz * (math.sin(angle) * angular_size * t)
            )
            direction = (n + offset).normalized()
            inner.append(tuple(mathutils.Vector(center) + direction * (radius + 3.35)))
        _curve_object(f"{name}_Mark{j}_Groove", inner, 0.75, groove)
        inner_glow = []
        for point in inner:
            p = mathutils.Vector(point)
            inner_glow.append(tuple(p + (p - mathutils.Vector(center)).normalized() * 1.0))
        _curve_object(f"{name}_Mark{j}_Glow", inner_glow, 0.34, glow)


def _add_runes(center, radius: float, groove, glow):
    seals = [
        (-1.38, 0.48, 17.0),
        (-1.14, -0.42, 13.0),
        (-0.82, 0.76, 11.0),
        (1.34, 0.44, 16.0),
        (1.12, -0.44, 13.0),
        (0.84, 0.72, 10.0),
    ]
    for index, (yaw, lat, size) in enumerate(seals):
        _surface_ring(
            f"RunicSeal_{index:02d}",
            center,
            radius,
            yaw,
            lat,
            size,
            groove,
            glow,
        )


def _add_binding_arc(name: str, center, radius: float, latitude: float, metal, start_yaw: float, end_yaw: float, links: int):
    for i in range(links):
        t = i / max(links - 1, 1)
        yaw = start_yaw + (end_yaw - start_yaw) * t
        n = _direction(yaw, latitude)
        location = mathutils.Vector(center) + n * (radius + 8.0)
        tangent = (_direction(yaw + 0.02, latitude) - _direction(yaw - 0.02, latitude)).normalized()

        bpy.ops.mesh.primitive_torus_add(
            major_radius=7.0,
            minor_radius=1.35,
            major_segments=28,
            minor_segments=8,
            location=location,
        )
        link = bpy.context.object
        link.name = f"{name}_Link_{i:02d}"
        normal = n if i % 2 == 0 else tangent
        link.rotation_euler = normal.to_track_quat("Z", "Y").to_euler()
        _assign_material(link, metal)


def _add_bindings(center, radius: float, metal):
    for row, lat in enumerate((-0.46, 0.52)):
        _add_binding_arc(
            f"Binding_{row}_Left",
            center,
            radius,
            lat,
            metal,
            0.52,
            math.pi - 0.15,
            30,
        )
        _add_binding_arc(
            f"Binding_{row}_Right",
            center,
            radius,
            lat,
            metal,
            -0.52,
            -math.pi + 0.15,
            30,
        )


def _add_preview_lights(center, scale: float):
    sun_data = bpy.data.lights.new("TitanPrisonV2_KeySun", type="SUN")
    sun_data.energy = 5.2
    sun_data.angle = math.radians(18.0)
    sun_data.color = (1.0, 0.68, 0.48)
    sun = bpy.data.objects.new("TitanPrisonV2_KeySun", sun_data)
    bpy.context.scene.collection.objects.link(sun)
    sun.rotation_euler = tuple(math.radians(v) for v in (38.0, -24.0, -34.0))
    sun["preview_only"] = True

    fill_data = bpy.data.lights.new("TitanPrisonV2_Fill", type="AREA")
    fill_data.energy = 78000
    fill_data.shape = "DISK"
    fill_data.size = 250 * scale
    fill_data.color = (0.24, 0.36, 0.62)
    fill = bpy.data.objects.new("TitanPrisonV2_Fill", fill_data)
    bpy.context.scene.collection.objects.link(fill)
    fill.location = (
        center[0] - 300 * scale,
        center[1] + 320 * scale,
        center[2] + 250 * scale,
    )
    direction = mathutils.Vector(center) - fill.location
    fill.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    fill["preview_only"] = True

    rim_data = bpy.data.lights.new("TitanPrisonV2_Rim", type="AREA")
    rim_data.energy = 68000
    rim_data.shape = "DISK"
    rim_data.size = 180 * scale
    rim_data.color = (1.0, 0.16, 0.035)
    rim = bpy.data.objects.new("TitanPrisonV2_Rim", rim_data)
    bpy.context.scene.collection.objects.link(rim)
    rim.location = (
        center[0] + 250 * scale,
        center[1] - 180 * scale,
        center[2] + 80 * scale,
    )
    direction = mathutils.Vector(center) - rim.location
    rim.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    rim["preview_only"] = True


def build_titan_prison_sphere_v2(op: dict, root_path: Path, mapping: dict) -> None:
    rng = random.Random(int(op.get("seed", 20261002)))
    scale = float(op.get("scale", 1.0))
    sphere_radius = float(mapping["sphere"]["radius_m"])
    sphere_godot = mapping["sphere"]["center_godot_m"]
    center = (
        sphere_godot[0] * scale,
        sphere_godot[2] * scale,
        sphere_godot[1] * scale,
    )
    radius = sphere_radius * scale

    stone = _stone_material(
        "TitanPrisonV2_Stone",
        dark=(0.125, 0.095, 0.078, 1.0),
        light=(0.36, 0.275, 0.19, 1.0),
    )
    relief_stone = _stone_material(
        "TitanPrisonV2_ReliefStone",
        dark=(0.15, 0.11, 0.085, 1.0),
        light=(0.43, 0.31, 0.205, 1.0),
    )
    groove = _simple_material("TitanPrisonV2_CrackGroove", (0.014, 0.008, 0.006), 0.96, 0.0)
    glow = _emissive_material("TitanPrisonV2_CrackGlow", (1.0, 0.08, 0.008), 70.0)
    rune_glow = _emissive_material("TitanPrisonV2_RuneGlow", (1.0, 0.30, 0.035), 48.0)
    metal = _simple_material("TitanPrisonV2_BindingMetal", (0.08, 0.055, 0.035), 0.47, 0.72)

    root = bpy.data.collections.new("KLOTHYS_TITAN_PRISON_SPHERE_V2")
    bpy.context.scene.collection.children.link(root)
    before = set(bpy.context.scene.objects)

    anchor = bpy.data.objects.new("ALIGN_KLOTHYS_SPHERE_CENTER_V2", None)
    bpy.context.scene.collection.objects.link(anchor)
    anchor.location = center
    anchor.empty_display_type = "SPHERE"
    anchor.empty_display_size = 6.0 * scale
    anchor["reference_radius_m"] = sphere_radius
    anchor["center_godot_m"] = ",".join(str(v) for v in sphere_godot)

    reserve = bpy.data.objects.new("RESERVED_KLOTHYS_FRONT_AXIS", None)
    bpy.context.scene.collection.objects.link(reserve)
    reserve.location = (
        center[0],
        center[1] + (sphere_radius + 20.0) * scale,
        center[2],
    )
    reserve.empty_display_type = "PLAIN_AXES"
    reserve.empty_display_size = 18.0 * scale
    reserve["reserved_front_half_angle_degrees"] = 40.0
    reserve["reserved_character_height_m"] = 440.0
    reserve["purpose"] = "Klothys body and binding hair - keep clear"

    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=192,
        ring_count=128,
        radius=radius,
        location=center,
    )
    shell = bpy.context.object
    shell.name = "Klothys_PrisonShell_V2_R220m"
    shell["godot_role"] = "KlothisRoot/SphereVisual"
    shell["reference_radius_m"] = sphere_radius
    shell["center_godot_m"] = ",".join(str(v) for v in sphere_godot)
    _assign_material(shell, stone)
    for poly in shell.data.polygons:
        poly.use_smooth = True

    rock_tex = bpy.data.textures.new("TitanPrisonV2_ShellBreakup", type="CLOUDS")
    rock_tex.noise_scale = 0.44
    rock_tex.noise_depth = 2
    disp = shell.modifiers.new("GeologicalSurface", type="DISPLACE")
    disp.texture = rock_tex
    disp.texture_coords = "LOCAL"
    disp.strength = 2.6 * scale
    disp.mid_level = 0.5

    assets = _asset_root(root_path)
    demon_path = _fetch(DEMON_URL, assets / "quaternius_demon.gltf")
    orc_path = _fetch(ORC_URL, assets / "quaternius_orc.gltf")

    creature_specs = [
        {
            "name": "ImprisonedTitan_A_Demon",
            "path": demon_path,
            "frame": 13,
            "yaw": -1.16,
            "latitude": 0.10,
            "width": 0.38,
            "height": 0.57,
            "seed": 421,
        },
        {
            "name": "ImprisonedTitan_B_Orc",
            "path": orc_path,
            "frame": 18,
            "yaw": 1.18,
            "latitude": -0.08,
            "width": 0.39,
            "height": 0.59,
            "seed": 997,
        },
    ]

    for index, spec in enumerate(creature_specs):
        imported, meshes, armatures, depsgraph = _import_rigged(spec["path"], spec["frame"])
        source_vertices, source_faces = _collect_evaluated_geometry(meshes, depsgraph)
        relief = _radial_relief(
            spec["name"],
            source_vertices,
            source_faces,
            center,
            radius,
            spec["yaw"],
            spec["latitude"],
            spec["width"],
            spec["height"],
            relief_stone,
            spec["seed"],
        )
        relief["source_url"] = DEMON_URL if index == 0 else ORC_URL
        relief["source_was_rigged"] = bool(armatures)
        relief["animation_sample_frame"] = spec["frame"]
        _remove_import(imported)

        side_sign = -1.0 if index == 0 else 1.0
        _pressure_tendrils(
            spec["name"],
            center,
            radius,
            spec["yaw"],
            stone,
            rng,
            side_sign,
        )

    _add_cracks(center, radius, groove, glow, rng)
    _add_runes(center, radius, groove, rune_glow)
    _add_bindings(center, radius, metal)

    for i in range(18):
        side = -1.0 if i % 2 == 0 else 1.0
        yaw = side * rng.uniform(0.72, 2.5)
        lat = rng.uniform(-0.92, 0.92)
        n = _direction(yaw, lat)
        location = mathutils.Vector(center) + n * rng.uniform(radius + 9.0, radius + 27.0)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=location)
        rock = bpy.context.object
        rock.name = f"FloatingPrisonShard_{i:02d}"
        rock.scale = (
            rng.uniform(1.2, 4.2),
            rng.uniform(0.9, 3.4),
            rng.uniform(0.8, 3.1),
        )
        rock.rotation_euler = (
            rng.uniform(-1.0, 1.0),
            rng.uniform(-1.0, 1.0),
            rng.uniform(-math.pi, math.pi),
        )
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        _assign_material(rock, stone)

    _add_preview_lights(center, scale)
    bpy.context.scene.world.color = (0.045, 0.052, 0.068)
    bpy.context.scene.view_settings.exposure = 1.25
    bpy.context.scene["titan_prison_asset_collection"] = root.name
    bpy.context.scene["titan_prison_reference_radius_m"] = sphere_radius
    bpy.context.scene["titan_prison_center_godot_m"] = ",".join(str(v) for v in sphere_godot)
    bpy.context.scene["titan_prison_v2_sources"] = SOURCE_LICENSE
    bpy.context.scene["klothys_reserved_front_half_angle_degrees"] = 40.0

    generated = [obj for obj in bpy.context.scene.objects if obj not in before]
    for obj in generated:
        if bool(obj.get("preview_only", False)):
            continue
        for collection in list(obj.users_collection):
            collection.objects.unlink(obj)
        root.objects.link(obj)
