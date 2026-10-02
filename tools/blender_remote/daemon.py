#!/usr/bin/env python3
"""Persistent GitHub -> Blender MCP bridge.

Reads command comments from one GitHub issue and forwards allowed operations to
the Blender MCP add-on socket listening on localhost:9876. No inbound network
port is opened on this computer.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

COMMAND_MARKER = "<!-- blender-remote:v1 -->"
RESULT_MARKER = "<!-- blender-remote-result:v1 -->"

REPO = os.getenv("BLENDER_REMOTE_REPO", "francesco-bufalini/VTT").strip()
ISSUE_NUMBER = int(os.getenv("BLENDER_REMOTE_ISSUE", "2"))
ALLOWED_LOGINS = {
    value.strip().lower()
    for value in os.getenv("BLENDER_REMOTE_ALLOWED", "francesco-bufalini").split(",")
    if value.strip()
}
ALLOW_PYTHON = os.getenv("BLENDER_REMOTE_ALLOW_PYTHON", "0") == "1"
SKIP_PENDING = os.getenv("BLENDER_REMOTE_SKIP_PENDING", "0") == "1"

BLENDER_HOST = os.getenv("BLENDER_REMOTE_HOST", "127.0.0.1")
BLENDER_PORT = int(os.getenv("BLENDER_REMOTE_PORT", "9876"))
POLL_SECONDS = max(1.0, float(os.getenv("BLENDER_REMOTE_POLL_SECONDS", "3")))
RESTART_REQUESTED = False
GITHUB_API_VERSION = "2022-11-28"

STATE_ROOT = Path(os.getenv("LOCALAPPDATA", str(Path.home()))) / "VTT"
STATE_PATH = STATE_ROOT / "blender_remote_state.json"


def fail(message: str) -> None:
    raise RuntimeError(message)


def github_token() -> str:
    token = os.getenv("GH_TOKEN") or os.getenv("GITHUB_TOKEN")
    if token:
        return token.strip()

    gh = shutil.which("gh")
    if not gh:
        fail(
            "GitHub CLI (gh) not found. Install it with "
            "`winget install --id GitHub.cli`, then run `gh auth login`."
        )

    result = subprocess.run(
        [gh, "auth", "token"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        fail("Could not obtain a GitHub token. Run `gh auth login` first.")
    return result.stdout.strip()


TOKEN = github_token()
COMMENTS_URL = (
    f"https://api.github.com/repos/{REPO}/issues/{ISSUE_NUMBER}/comments"
)


def github_request(
    method: str,
    url: str,
    payload: dict[str, Any] | None = None,
    etag: str | None = None,
) -> tuple[int, Any, dict[str, str]]:
    body = None
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {TOKEN}",
        "User-Agent": "VTT-Blender-Remote/1.0",
        "X-GitHub-Api-Version": GITHUB_API_VERSION,
    }
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if etag:
        headers["If-None-Match"] = etag

    request = urllib.request.Request(
        url,
        data=body,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
            data = json.loads(raw.decode("utf-8")) if raw else None
            return response.status, data, dict(response.headers.items())
    except urllib.error.HTTPError as exc:
        if exc.code == 304:
            return 304, None, dict(exc.headers.items())
        raw = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"GitHub API {method} {url} failed: HTTP {exc.code}: {raw}"
        ) from exc


def blender_command(
    command_type: str,
    params: dict[str, Any] | None = None,
    timeout: float = 120,
) -> dict[str, Any]:
    payload = {"type": command_type, "params": params or {}}
    raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")

    try:
        sock = socket.create_connection((BLENDER_HOST, BLENDER_PORT), timeout=5)
    except OSError as exc:
        raise RuntimeError(
            f"Cannot connect to Blender MCP at {BLENDER_HOST}:{BLENDER_PORT}. "
            "In Blender open N > BlenderMCP and press Start MCP Server."
        ) from exc

    with sock:
        sock.settimeout(timeout)
        sock.sendall(raw)
        buffer = b""
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                raise RuntimeError(
                    "Blender MCP closed the connection before returning JSON."
                )
            buffer += chunk
            try:
                response = json.loads(buffer.decode("utf-8"))
            except json.JSONDecodeError:
                continue
            if not isinstance(response, dict):
                raise RuntimeError("Blender MCP returned a non-object JSON response.")
            return response


def extract_command(body: str) -> dict[str, Any] | None:
    if COMMAND_MARKER not in body:
        return None

    match = re.search(
        r"```json\s*(\{.*?\})\s*```",
        body,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if not match:
        raise ValueError("Command marker found, but no JSON code block exists.")

    command = json.loads(match.group(1))
    if not isinstance(command, dict):
        raise ValueError("Command JSON must be an object.")
    return command


def normalized_vector(value: Any, field: str) -> list[float]:
    if not isinstance(value, list) or len(value) != 3:
        raise ValueError(f"{field} must be a JSON array of three numbers.")
    return [float(v) for v in value]


def fixed_transform(command: dict[str, Any]) -> dict[str, Any]:
    name = str(command["object"])
    assignments: list[str] = []

    if "location" in command:
        v = normalized_vector(command["location"], "location")
        assignments.append(f"obj.location = {v!r}")
    if "rotation" in command:
        v = normalized_vector(command["rotation"], "rotation")
        assignments.append(f"obj.rotation_euler = {v!r}")
    if "scale" in command:
        v = normalized_vector(command["scale"], "scale")
        assignments.append(f"obj.scale = {v!r}")

    if not assignments:
        raise ValueError("transform requires location, rotation, or scale.")

    code = "\n".join(
        [
            "import bpy, json",
            f"name = {name!r}",
            "obj = bpy.data.objects.get(name)",
            "if obj is None: raise ValueError(f'Object not found: {name}')",
            *assignments,
            "bpy.context.view_layer.update()",
            "print(json.dumps({",
            "  'name': obj.name,",
            "  'location': list(obj.location),",
            "  'rotation': list(obj.rotation_euler),",
            "  'scale': list(obj.scale)",
            "}))",
        ]
    )
    return blender_command("execute_code", {"code": code})


def execute_json_code(code: str, timeout: float = 120) -> dict[str, Any]:
    response = blender_command("execute_code", {"code": code}, timeout=timeout)
    if response.get("status") != "success":
        return response

    outer = response.get("result") or {}
    stdout = str(outer.get("result") or "").strip()
    if not stdout:
        return response

    # Blender code may emit extra lines. The final non-empty line is our JSON payload.
    for line in reversed(stdout.splitlines()):
        line = line.strip()
        if not line:
            continue
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            continue
        return {"status": "success", "result": parsed}

    return response


def workspace_info() -> dict[str, Any]:
    code = """import bpy, json
ctx = bpy.context
windows = []
wm = ctx.window_manager
for index, window in enumerate(wm.windows):
    screen = window.screen
    areas = []
    for area in screen.areas:
        areas.append({
            "type": area.type,
            "ui_type": area.ui_type,
            "width": area.width,
            "height": area.height,
        })
    windows.append({
        "index": index,
        "workspace": window.workspace.name if window.workspace else None,
        "screen": screen.name if screen else None,
        "areas": areas,
    })

payload = {
    "active_workspace": ctx.window.workspace.name if ctx.window and ctx.window.workspace else None,
    "active_screen": ctx.window.screen.name if ctx.window and ctx.window.screen else None,
    "mode": ctx.mode,
    "active_object": ctx.active_object.name if ctx.active_object else None,
    "selected_objects": [obj.name for obj in ctx.selected_objects],
    "workspaces": [workspace.name for workspace in bpy.data.workspaces],
    "windows": windows,
}
print(json.dumps(payload))
"""
    return execute_json_code(code)


def self_update() -> dict[str, Any]:
    repo_root = Path(__file__).resolve().parents[2]
    daemon_rel = "tools/blender_remote/daemon.py"

    # Only protect the daemon itself from being overwritten if the user has
    # edited it locally. Unrelated dirty project files must not block updates.
    status = subprocess.run(
        ["git", "status", "--porcelain", "--", daemon_rel],
        cwd=repo_root,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if status.returncode != 0:
        raise RuntimeError(f"git status failed: {status.stderr.strip()}")
    if status.stdout.strip():
        raise RuntimeError(
            "daemon.py has local modifications; self_update refused to overwrite it."
        )

    fetch = subprocess.run(
        ["git", "fetch", "origin", "main"],
        cwd=repo_root,
        capture_output=True,
        text=True,
        timeout=120,
    )
    if fetch.returncode != 0:
        raise RuntimeError(f"git fetch failed: {fetch.stderr.strip()}")

    show = subprocess.run(
        ["git", "show", f"origin/main:{daemon_rel}"],
        cwd=repo_root,
        capture_output=True,
        timeout=30,
    )
    if show.returncode != 0:
        stderr = show.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"git show failed: {stderr}")

    daemon_path = Path(__file__).resolve()
    temp_path = daemon_path.with_suffix(".py.update")
    temp_path.write_bytes(show.stdout)
    temp_path.replace(daemon_path)

    result = {
        "updated": True,
        "repo_root": str(repo_root),
        "daemon_path": str(daemon_path),
        "restart": "scheduled",
    }

    global RESTART_REQUESTED
    RESTART_REQUESTED = True
    return {"status": "success", "result": result}


def import_titan_reference() -> dict[str, Any]:
    code = r"""import bpy, json, os, tempfile, urllib.request
from mathutils import Vector

url = 'https://raw.githubusercontent.com/programasweights/avatar/main/public/assets/character.glb'
collection_name = 'REF_Titan_Normal'
center = Vector((0.0, -230.0, 385.0))
target_height = 430.0

# Remove only the previous reference collection and objects owned by it.
old_col = bpy.data.collections.get(collection_name)
if old_col is not None:
    for obj in list(old_col.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(old_col)

tmp_dir = tempfile.gettempdir()
glb_path = os.path.join(tmp_dir, 'quaternius_superhero_male_cc0.glb')
urllib.request.urlretrieve(url, glb_path)

before_names = set(bpy.data.objects.keys())
bpy.ops.import_scene.gltf(filepath=glb_path)
imported = [obj for obj in bpy.data.objects if obj.name not in before_names]
if not imported:
    raise RuntimeError('GLB import completed but no objects were created')

# Link imported objects to a dedicated reference collection WITHOUT unlinking
# them from the collection created by Blender's glTF importer.
ref_col = bpy.data.collections.new(collection_name)
bpy.context.scene.collection.children.link(ref_col)
for obj in imported:
    if ref_col not in obj.users_collection:
        ref_col.objects.link(obj)

mesh_objs = [obj for obj in imported if obj.type == 'MESH']
armatures = [obj for obj in imported if obj.type == 'ARMATURE']
if not mesh_objs:
    raise RuntimeError('Imported GLB has no mesh objects')

def bounds_world(objects):
    mins = Vector((1e30, 1e30, 1e30))
    maxs = Vector((-1e30, -1e30, -1e30))
    for obj in objects:
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            mins.x = min(mins.x, p.x); mins.y = min(mins.y, p.y); mins.z = min(mins.z, p.z)
            maxs.x = max(maxs.x, p.x); maxs.y = max(maxs.y, p.y); maxs.z = max(maxs.z, p.z)
    return mins, maxs

mins, maxs = bounds_world(mesh_objs)
height = maxs.z - mins.z
if height <= 1e-6:
    raise RuntimeError('Imported titan has invalid height')

roots = [obj for obj in imported if obj.parent is None]
scale_factor = target_height / height
for obj in roots:
    obj.scale = obj.scale * scale_factor
bpy.context.view_layer.update()

mins, maxs = bounds_world(mesh_objs)
bbox_center = (mins + maxs) * 0.5
delta = center - bbox_center
for obj in roots:
    obj.location = obj.location + delta
bpy.context.view_layer.update()

# Hide whichever prison shell variant exists.
shell_names = (
    'Klothys_PrisonShell_V2_R220m',
    'COMBAT_KlothysSphere_R220m',
    'SphereBinding',
)
hidden_shells = []
for name in shell_names:
    shell = bpy.data.objects.get(name)
    if shell is not None:
        shell.hide_viewport = True
        shell.hide_render = True
        hidden_shells.append(name)

# Select the imported rig and mesh.
bpy.ops.object.select_all(action='DESELECT')
for obj in imported:
    obj.select_set(True)
if armatures:
    bpy.context.view_layer.objects.active = armatures[0]
else:
    bpy.context.view_layer.objects.active = mesh_objs[0]

# Center every 3D viewport on the imported titan and force a redraw.
for window in bpy.context.window_manager.windows:
    screen = window.screen
    if not screen:
        continue
    for area in screen.areas:
        if area.type != 'VIEW_3D':
            continue
        space = area.spaces.active
        if space.region_3d:
            space.region_3d.view_location = center
            space.region_3d.view_distance = target_height * 0.75
        area.tag_redraw()

bpy.context.view_layer.update()

print(json.dumps({
    'collection': collection_name,
    'collection_object_count': len(ref_col.objects),
    'objects': [obj.name for obj in imported],
    'mesh_objects': [obj.name for obj in mesh_objs],
    'armatures': [obj.name for obj in armatures],
    'scale_factor': scale_factor,
    'target_center': list(center),
    'target_height': target_height,
    'hidden_shells': hidden_shells,
    'source_url': url,
}))
"""
    return execute_json_code(code, timeout=300)


def blender_file_info() -> dict[str, Any]:
    code = r"""import bpy, json
print(json.dumps({
    'filepath': bpy.data.filepath,
    'current_scene': bpy.context.scene.name if bpy.context.scene else None,
    'scenes': [
        {
            'name': scene.name,
            'object_count': len(scene.objects),
        }
        for scene in bpy.data.scenes
    ],
    'collections': [
        {
            'name': col.name,
            'object_count': len(col.objects),
        }
        for col in bpy.data.collections
    ],
    'objects_total': len(bpy.data.objects),
}))
"""
    return execute_json_code(code)


def focus_titan_reference() -> dict[str, Any]:
    code = r"""import bpy, json, math
from mathutils import Quaternion, Vector

mesh = bpy.data.objects.get('SuperHero_Male')
arm = bpy.data.objects.get('Armature')
if mesh is None:
    raise RuntimeError('SuperHero_Male not found')

# Keep the rig, but make the mesh the active visible reference.
bpy.ops.object.select_all(action='DESELECT')
mesh.hide_viewport = False
mesh.hide_render = False
mesh.select_set(True)
bpy.context.view_layer.objects.active = mesh

# Do not delete or alter the rig; only hide it in the viewport so the body is readable.
if arm is not None:
    arm.hide_viewport = True

# Use the mesh bounds to center the view.
corners = [mesh.matrix_world @ Vector(c) for c in mesh.bound_box]
mins = Vector((min(p.x for p in corners), min(p.y for p in corners), min(p.z for p in corners)))
maxs = Vector((max(p.x for p in corners), max(p.y for p in corners), max(p.z for p in corners)))
center = (mins + maxs) * 0.5
height = maxs.z - mins.z

changed = []
for window in bpy.context.window_manager.windows:
    screen = window.screen
    if not screen:
        continue
    for area in screen.areas:
        if area.type != 'VIEW_3D':
            continue
        space = area.spaces.active
        r3d = space.region_3d
        if r3d:
            r3d.view_location = center
            r3d.view_distance = max(height * 0.75, 50.0)
            # Front view, looking along -Y with Z up.
            r3d.view_rotation = Quaternion((1.0, 0.0, 0.0, 0.0))
            r3d.view_perspective = 'ORTHO'
        space.shading.type = 'MATERIAL'
        area.tag_redraw()
        changed.append({'area': area.type, 'center': list(center), 'height': height})

bpy.context.view_layer.update()
print(json.dumps({
    'mesh': mesh.name,
    'armature_hidden_in_viewport': bool(arm is not None),
    'center': list(center),
    'height': height,
    'views_changed': changed,
}))
"""
    return execute_json_code(code)


def set_viewport_shading(command: dict[str, Any]) -> dict[str, Any]:
    shading = str(command.get("shading", "RENDERED")).strip().upper()
    allowed = {"WIREFRAME", "SOLID", "MATERIAL", "RENDERED"}
    if shading not in allowed:
        raise ValueError(f"shading must be one of: {', '.join(sorted(allowed))}")

    code = f"""import bpy, json
changed = []
for window_index, window in enumerate(bpy.context.window_manager.windows):
    screen = window.screen
    if not screen:
        continue
    for area_index, area in enumerate(screen.areas):
        if area.type != 'VIEW_3D':
            continue
        space = area.spaces.active
        space.shading.type = {shading!r}
        changed.append({{
            'window_index': window_index,
            'area_index': area_index,
            'shading': space.shading.type,
        }})
print(json.dumps({{'changed': changed}}))
"""
    return execute_json_code(code)


def viewport_info() -> dict[str, Any]:
    code = """import bpy, json
ctx = bpy.context
views = []
wm = ctx.window_manager
for window_index, window in enumerate(wm.windows):
    screen = window.screen
    if not screen:
        continue
    for area_index, area in enumerate(screen.areas):
        if area.type != 'VIEW_3D':
            continue
        space = area.spaces.active
        region_3d = space.region_3d
        region = next((r for r in area.regions if r.type == 'WINDOW'), None)
        views.append({
            "window_index": window_index,
            "area_index": area_index,
            "width": region.width if region else area.width,
            "height": region.height if region else area.height,
            "workspace": window.workspace.name if window.workspace else None,
            "screen": screen.name,
            "view_perspective": region_3d.view_perspective,
            "view_location": list(region_3d.view_location),
            "view_distance": region_3d.view_distance,
            "view_rotation_quaternion": list(region_3d.view_rotation),
            "view_camera_zoom": region_3d.view_camera_zoom,
            "lens_mm": space.lens,
            "clip_start": space.clip_start,
            "clip_end": space.clip_end,
            "shading": space.shading.type,
            "camera": space.camera.name if space.camera else None,
        })

payload = {
    "mode": ctx.mode,
    "active_object": ctx.active_object.name if ctx.active_object else None,
    "views": views,
}
print(json.dumps(payload))
"""
    return execute_json_code(code)


def viewport_screenshot(command: dict[str, Any]) -> dict[str, Any]:
    requested_width = int(command.get("max_width", 640))
    max_width = max(256, min(requested_width, 800))
    requested_quality = int(command.get("quality", 55))
    quality = max(25, min(requested_quality, 70))

    # Keep the JPEG small enough that base64 + JSON fits safely in one GitHub comment.
    target_bytes = 32000

    code = f"""import bpy, json, base64, os, tempfile
ctx = bpy.context
candidates = []
for window_index, window in enumerate(ctx.window_manager.windows):
    screen = window.screen
    if not screen:
        continue
    for area_index, area in enumerate(screen.areas):
        if area.type != 'VIEW_3D':
            continue
        region = next((r for r in area.regions if r.type == 'WINDOW'), None)
        width = region.width if region else area.width
        height = region.height if region else area.height
        candidates.append((width * height, window_index, area_index, window, area, width, height))

if not candidates:
    raise RuntimeError('No VIEW_3D editor is open')

_, window_index, area_index, window, area, source_w, source_h = max(candidates, key=lambda item: item[0])

tmp_dir = tempfile.gettempdir()
raw_path = os.path.join(tmp_dir, 'vtt_blender_remote_viewport.png')
jpg_path = os.path.join(tmp_dir, 'vtt_blender_remote_viewport.jpg')

with ctx.temp_override(window=window, screen=window.screen, area=area):
    bpy.ops.screen.screenshot_area(filepath=raw_path, check_existing=False)

img = bpy.data.images.load(raw_path, check_existing=False)
scene = window.scene
settings = scene.render.image_settings
old_format = settings.file_format
old_color_mode = settings.color_mode
old_quality = settings.quality

try:
    original_w, original_h = int(img.size[0]), int(img.size[1])
    max_width = {max_width}
    if original_w > max_width:
        scaled_h = max(1, int(round(original_h * (max_width / original_w))))
        img.scale(max_width, scaled_h)

    settings.file_format = 'JPEG'
    settings.color_mode = 'RGB'

    qualities = []
    for q in [{quality}, 45, 35, 25]:
        if q not in qualities:
            qualities.append(q)

    target_bytes = {target_bytes}
    encoded = None
    final_quality = qualities[-1]

    for pass_index in range(3):
        for q in qualities:
            settings.quality = q
            img.save_render(jpg_path, scene=scene)
            size = os.path.getsize(jpg_path)
            final_quality = q
            if size <= target_bytes:
                encoded = base64.b64encode(open(jpg_path, 'rb').read()).decode('ascii')
                break
        if encoded is not None:
            break

        new_w = max(256, int(img.size[0] * 0.75))
        if new_w >= img.size[0]:
            break
        new_h = max(1, int(round(img.size[1] * (new_w / img.size[0]))))
        img.scale(new_w, new_h)

    if encoded is None:
        settings.quality = 20
        img.save_render(jpg_path, scene=scene)
        data = open(jpg_path, 'rb').read()
        if len(data) > 40000:
            raise RuntimeError(f'Viewport screenshot remains too large for GitHub comment: {{len(data)}} bytes')
        encoded = base64.b64encode(data).decode('ascii')
        final_quality = 20

    payload = {{
        "mime": "image/jpeg",
        "width": int(img.size[0]),
        "height": int(img.size[1]),
        "source_width": int(source_w),
        "source_height": int(source_h),
        "bytes": os.path.getsize(jpg_path),
        "quality": final_quality,
        "window_index": window_index,
        "area_index": area_index,
        "workspace": window.workspace.name if window.workspace else None,
        "screen": window.screen.name if window.screen else None,
        "base64": encoded,
    }}
    print(json.dumps(payload))
finally:
    settings.file_format = old_format
    settings.color_mode = old_color_mode
    settings.quality = old_quality
    bpy.data.images.remove(img)
    for path in (raw_path, jpg_path):
        try:
            os.remove(path)
        except OSError:
            pass
"""
    return execute_json_code(code, timeout=180)


def titan_relief(command: dict[str, Any]) -> dict[str, Any]:
    influence = max(5.0, min(float(command.get("influence", 48.0)), 120.0))
    skin = max(0.0, min(float(command.get("skin", 26.0)), 80.0))
    max_push = max(0.0, min(float(command.get("max_push", 32.0)), 100.0))
    reserve_inner = max(0.0, min(float(command.get("reserve_inner", 52.0)), 180.0))
    reserve_outer = max(reserve_inner + 1.0, min(float(command.get("reserve_outer", 92.0)), 210.0))
    strength = max(0.0, min(float(command.get("strength", 1.0)), 1.5))

    code = f"""import bpy, json, math
from mathutils import kdtree, Vector

shell_name = 'Klothys_PrisonShell_V2_R220m'
titan_names = ['ImprisonedTitan_A_Demon', 'ImprisonedTitan_B_Orc']
key_name = 'TitanLatexRelief'

shell = bpy.data.objects.get(shell_name)
if shell is None or shell.type != 'MESH':
    raise RuntimeError(f'Shell not found or not a mesh: {{shell_name}}')

titans = []
for name in titan_names:
    obj = bpy.data.objects.get(name)
    if obj is None or obj.type != 'MESH':
        raise RuntimeError(f'Titan not found or not a mesh: {{name}}')
    titans.append(obj)

# Ensure a reversible basis + dedicated relief shape key.
if shell.data.shape_keys is None:
    shell.shape_key_add(name='Basis', from_mix=False)

existing = shell.data.shape_keys.key_blocks.get(key_name)
if existing is not None:
    shell.shape_key_remove(existing)

relief = shell.shape_key_add(name=key_name, from_mix=False)
basis = shell.data.shape_keys.key_blocks.get('Basis')

depsgraph = bpy.context.evaluated_depsgraph_get()
trees = []
for titan in titans:
    eval_obj = titan.evaluated_get(depsgraph)
    eval_mesh = eval_obj.to_mesh()
    tree = kdtree.KDTree(len(eval_mesh.vertices))
    matrix = eval_obj.matrix_world.copy()
    for i, vert in enumerate(eval_mesh.vertices):
        tree.insert(matrix @ vert.co, i)
    tree.balance()
    trees.append((tree, eval_obj, eval_mesh))

center = shell.matrix_world.translation.copy()
shell_world = shell.matrix_world.copy()
shell_inv = shell_world.inverted()

influence = {influence!r}
skin = {skin!r}
max_push = {max_push!r}
reserve_inner = {reserve_inner!r}
reserve_outer = {reserve_outer!r}
strength = {strength!r}

changed = 0
push_sum = 0.0
push_peak = 0.0

try:
    for i, basis_point in enumerate(basis.data):
        world = shell_world @ basis_point.co
        radial = world - center
        radius = radial.length
        if radius <= 1e-6:
            relief.data[i].co = basis_point.co
            continue

        # Preserve a central vertical corridor for Klothys. Fade the relief in
        # gradually outside that corridor to avoid a hard seam.
        abs_x = abs(world.x - center.x)
        if abs_x <= reserve_inner:
            center_mask = 0.0
        elif abs_x >= reserve_outer:
            center_mask = 1.0
        else:
            t = (abs_x - reserve_inner) / (reserve_outer - reserve_inner)
            center_mask = t * t * (3.0 - 2.0 * t)

        if center_mask <= 0.0:
            relief.data[i].co = basis_point.co
            continue

        best_dist = 1.0e30
        best_point = None
        for tree, _, _ in trees:
            co, _, dist = tree.find(world)
            if co is not None and dist < best_dist:
                best_dist = dist
                best_point = co

        if best_point is None or best_dist >= influence:
            relief.data[i].co = basis_point.co
            continue

        # Smooth proximity falloff.
        t = 1.0 - best_dist / influence
        falloff = t * t * (3.0 - 2.0 * t)

        titan_radius = (best_point - center).length
        desired_radius = titan_radius + skin
        raw_push = max(0.0, desired_radius - radius)
        push = min(max_push, raw_push * falloff * center_mask * strength)

        if push <= 1e-5:
            relief.data[i].co = basis_point.co
            continue

        new_world = center + radial.normalized() * (radius + push)
        relief.data[i].co = shell_inv @ new_world
        changed += 1
        push_sum += push
        push_peak = max(push_peak, push)

finally:
    for _, eval_obj, eval_mesh in trees:
        eval_obj.to_mesh_clear()

relief.value = 1.0
shell.active_shape_key_index = shell.data.shape_keys.key_blocks.find(key_name)
bpy.context.view_layer.update()

print(json.dumps({{
    'shell': shell.name,
    'shape_key': key_name,
    'titans': titan_names,
    'vertices_total': len(shell.data.vertices),
    'vertices_deformed': changed,
    'mean_push': (push_sum / changed) if changed else 0.0,
    'max_push_actual': push_peak,
    'parameters': {{
        'influence': influence,
        'skin': skin,
        'max_push': max_push,
        'reserve_inner': reserve_inner,
        'reserve_outer': reserve_outer,
        'strength': strength,
    }}
}}))
"""
    return execute_json_code(code, timeout=300)


def set_named_prefixes_visible(prefixes: tuple[str, ...], visible: bool) -> dict[str, Any]:
    hidden_flag = "False" if visible else "True"
    visible_literal = "True" if visible else "False"
    code = f"""import bpy, json
prefixes = {prefixes!r}
changed = []
for obj in bpy.data.objects:
    if obj.name.startswith(prefixes):
        obj.hide_viewport = {hidden_flag}
        obj.hide_render = {hidden_flag}
        changed.append(obj.name)
print(json.dumps({{'visible': {visible_literal}, 'count': len(changed), 'objects': changed}}))
"""
    return execute_json_code(code)


def set_titan_helpers_visible(visible: bool) -> dict[str, Any]:
    hidden_flag = "False" if visible else "True"
    visible_literal = "True" if visible else "False"
    code = f"""import bpy, json
prefixes = ('ImprisonedTitan_A_Demon_StoneRoot_', 'ImprisonedTitan_B_Orc_StoneRoot_')
changed = []
for obj in bpy.data.objects:
    if obj.name.startswith(prefixes):
        obj.hide_viewport = {hidden_flag}
        obj.hide_render = {hidden_flag}
        changed.append(obj.name)
print(json.dumps({{'visible': {visible_literal}, 'count': len(changed), 'objects': changed}}))
"""
    return execute_json_code(code)


def reset_titan_relief() -> dict[str, Any]:
    code = """import bpy, json
shell = bpy.data.objects.get('Klothys_PrisonShell_V2_R220m')
if shell is None:
    raise RuntimeError('Klothys_PrisonShell_V2_R220m not found')
key = shell.data.shape_keys.key_blocks.get('TitanLatexRelief') if shell.data.shape_keys else None
if key is None:
    print(json.dumps({'found': False, 'value': 0.0}))
else:
    key.value = 0.0
    bpy.context.view_layer.update()
    print(json.dumps({'found': True, 'value': key.value}))
"""
    return execute_json_code(code)


def execute(command: dict[str, Any]) -> dict[str, Any]:
    action = str(command.get("action", "")).strip().lower()

    if action == "ping":
        response = blender_command("get_scene_info")
        if response.get("status") != "success":
            return response
        scene = response.get("result") or {}
        return {
            "status": "success",
            "result": {
                "connected": True,
                "scene": scene.get("name"),
                "object_count": scene.get("object_count"),
            },
        }

    if action == "scene":
        return blender_command("get_scene_info")

    if action in {"workspaces", "ui"}:
        return workspace_info()

    if action == "viewport":
        return viewport_info()

    if action in {"set_viewport_shading", "viewport_shading"}:
        return set_viewport_shading(command)

    if action == "focus_titan_reference":
        return focus_titan_reference()

    if action in {"file_info", "blend_info"}:
        return blender_file_info()

    if action == "import_titan_reference":
        return import_titan_reference()

    if action == "self_update":
        return self_update()

    if action in {"screenshot", "render_preview"}:
        return viewport_screenshot(command)

    if action in {"titan_relief", "latex_titans"}:
        return titan_relief(command)

    if action == "reset_titan_relief":
        return reset_titan_relief()

    if action == "hide_titan_helpers":
        return set_titan_helpers_visible(False)

    if action == "show_titan_helpers":
        return set_titan_helpers_visible(True)

    if action == "hide_runic_seals":
        return set_named_prefixes_visible(("RunicSeal_",), False)

    if action == "show_runic_seals":
        return set_named_prefixes_visible(("RunicSeal_",), True)

    if action == "hide_stress_cracks":
        return set_named_prefixes_visible(("TitanStressCrack_",), False)

    if action == "show_stress_cracks":
        return set_named_prefixes_visible(("TitanStressCrack_",), True)

    if action == "hide_floating_shards":
        return set_named_prefixes_visible(("FloatingPrisonShard_",), False)

    if action == "show_floating_shards":
        return set_named_prefixes_visible(("FloatingPrisonShard_",), True)

    if action == "object":
        name = str(command["object"])
        return blender_command("get_object_info", {"name": name})

    if action == "transform":
        return fixed_transform(command)

    if action == "undo":
        code = "import bpy\nbpy.ops.ed.undo()\nprint('undo complete')\n"
        return blender_command("execute_code", {"code": code})

    if action == "save":
        code = (
            "import bpy\n"
            "if not bpy.data.filepath: "
            "raise RuntimeError('Current Blender file has never been saved')\n"
            "bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)\n"
            "print(bpy.data.filepath)\n"
        )
        return blender_command("execute_code", {"code": code}, timeout=300)

    if action == "python":
        if not ALLOW_PYTHON:
            raise PermissionError(
                "Arbitrary Blender Python is disabled. "
                "Restart with start.ps1 -AllowPython to enable it locally."
            )
        code = str(command.get("code", ""))
        if not code.strip():
            raise ValueError("python action requires a non-empty code field.")
        return blender_command("execute_code", {"code": code}, timeout=300)

    raise ValueError(
        "Unknown action. Supported: ping, scene, workspaces, viewport, set_viewport_shading, file_info, import_titan_reference, self_update, screenshot, render_preview, titan_relief, reset_titan_relief, hide_titan_helpers, show_titan_helpers, hide_runic_seals, show_runic_seals, hide_stress_cracks, show_stress_cracks, hide_floating_shards, show_floating_shards, object, transform, undo, save"
        + (", python" if ALLOW_PYTHON else "")
    )


def compact_result(value: Any) -> str:
    text = json.dumps(value, ensure_ascii=False, indent=2, default=str)
    if len(text) > 55000:
        text = text[:55000] + "\n... result truncated by daemon ..."
    return text


def post_result(
    command_id: str,
    source_comment_id: int,
    ok: bool,
    result: Any,
) -> None:
    label = "OK" if ok else "ERROR"
    body = (
        f"{RESULT_MARKER}\n\n"
        f"**{command_id}: {label}**  \n"
        f"Source comment: `{source_comment_id}`\n\n"
        f"```json\n{compact_result(result)}\n```\n"
    )
    github_request("POST", COMMENTS_URL, {"body": body})


def load_state() -> dict[str, Any]:
    try:
        return json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def save_state(state: dict[str, Any]) -> None:
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    temp = STATE_PATH.with_suffix(".tmp")
    temp.write_text(json.dumps(state, indent=2), encoding="utf-8")
    temp.replace(STATE_PATH)


def fetch_comments_since(since: datetime) -> list[dict[str, Any]]:
    # GitHub's issue-comment endpoint supports `since`, but not reliable
    # descending sort for this use case. Poll only the recent time window and
    # filter by monotonically increasing comment IDs in main().
    query = urllib.parse.urlencode(
        {
            "per_page": 100,
            "since": since.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
        }
    )
    _, comments, _ = github_request("GET", f"{COMMENTS_URL}?{query}")
    return sorted(list(comments or []), key=lambda item: int(item["id"]))


def main() -> int:
    if not REPO or "/" not in REPO:
        fail("BLENDER_REMOTE_REPO must be owner/repository.")
    if not ALLOWED_LOGINS:
        fail("BLENDER_REMOTE_ALLOWED must contain at least one GitHub login.")

    # Interactive mode is intentionally session-scoped: commands that existed
    # before this daemon process started are never replayed. If the daemon was
    # offline, resend the command after "Waiting for commands" appears.
    session_started = datetime.now(timezone.utc)
    last_comment_id = 0
    state = {
        "console": f"{REPO}#{ISSUE_NUMBER}",
        "session_started": session_started.isoformat(),
        "last_comment_id": 0,
    }
    save_state(state)

    print("Blender Remote Daemon")
    print(f"  Console : https://github.com/{REPO}/issues/{ISSUE_NUMBER}")
    print(f"  Allowed : {', '.join(sorted(ALLOWED_LOGINS))}")
    print(f"  Blender : {BLENDER_HOST}:{BLENDER_PORT}")
    print(f"  Poll    : {POLL_SECONDS:g}s")
    print(f"  Python  : {'ENABLED' if ALLOW_PYTHON else 'disabled'}")
    print("  Session : fresh (pre-existing GitHub comments ignored)")
    print()
    print("Waiting for commands. Ctrl+C to stop.")

    poll_since = session_started

    while True:
        try:
            # Advance the cursor only after a successful fetch. This means a
            # long Blender operation cannot make commands posted meanwhile fall
            # out of a fixed polling window.
            poll_started = datetime.now(timezone.utc)
            comments = fetch_comments_since(poll_since)

            for comment in comments:
                comment_id = int(comment["id"])
                if comment_id <= last_comment_id:
                    continue

                author = str((comment.get("user") or {}).get("login", "")).lower()
                body = str(comment.get("body") or "")

                # Mark the comment consumed before executing side effects, so a
                # daemon restart cannot accidentally execute the same mutation twice.
                last_comment_id = comment_id
                state["last_comment_id"] = last_comment_id
                save_state(state)

                try:
                    command = extract_command(body)
                except Exception as exc:
                    command = None
                    if COMMAND_MARKER in body and author in ALLOWED_LOGINS:
                        post_result(
                            f"github-{comment_id}",
                            comment_id,
                            False,
                            {"error": type(exc).__name__, "message": str(exc)},
                        )

                if command is None:
                    continue

                if author not in ALLOWED_LOGINS:
                    print(f"Ignored unauthorized command from {author!r}")
                    continue

                command_id = str(command.get("id") or f"github-{comment_id}")
                action = str(command.get("action") or "")
                print(f"> {command_id} [{author}] {action}")

                try:
                    result = execute(command)
                    post_result(command_id, comment_id, True, result)
                    print(f"< {command_id} OK")
                    if RESTART_REQUESTED:
                        print("Self-update complete. Restarting daemon...")
                        os.execv(sys.executable, [sys.executable, str(Path(__file__).resolve())])
                except Exception as exc:
                    error = {
                        "error": type(exc).__name__,
                        "message": str(exc),
                    }
                    post_result(command_id, comment_id, False, error)
                    print(f"< {command_id} ERROR: {exc}")

            # Five seconds of overlap handles clock skew and eventual
            # consistency; last_comment_id prevents duplicate execution.
            poll_since = max(session_started, poll_started - timedelta(seconds=5))

        except KeyboardInterrupt:
            print("\nStopped.")
            return 0
        except Exception as exc:
            print(f"[bridge error] {type(exc).__name__}: {exc}", file=sys.stderr)
            time.sleep(10)
            continue

        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    raise SystemExit(main())
