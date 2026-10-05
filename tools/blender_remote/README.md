# Blender Remote Daemon

Persistent bridge between GitHub issue comments and the Blender MCP add-on running on the same Windows PC.

## Architecture

ChatGPT -> GitHub Issue #2 -> daemon.py -> 127.0.0.1:9876 -> Blender MCP add-on -> Blender

The PC never exposes an inbound port to the Internet. The daemon only polls GitHub and opens a local TCP connection to Blender.

## First start

1. Open Blender.
2. In the 3D View press `N`, open **BlenderMCP**, and start the MCP server.
3. Verify GitHub CLI:

   ```powershell
   gh auth status
   ```

   If needed:

   ```powershell
   winget install --id GitHub.cli
   gh auth login
   ```

4. From the repository root run:

   ```powershell
   .\tools\blender_remote\start.ps1
   ```

The first launch deliberately ignores commands that were already present in Issue #2. Start the daemon first, then post a new command.

## Supported commands

Commands are GitHub comments on Issue #2 with this exact marker:

````text
<!-- blender-remote:v1 -->
```json
{
  "id": "example-001",
  "action": "ping"
}
```
````

Actions enabled by default:

- `ping`: verify Blender connectivity.
- `scene`: return basic scene information.
- `workspaces` (alias `ui`): return the active workspace/screen, Blender mode, active/selected objects, all workspaces, windows, and open editor area types.
- `viewport`: return every open 3D viewport's perspective, orbit target, distance, quaternion rotation, lens, clipping, shading, and camera.
- `screenshot` (alias `render_preview`): capture the largest open 3D viewport, resize/compress it to a GitHub-comment-safe JPEG, and return it as base64 so ChatGPT can display it directly.
- `object`: return information about one object. Add `"object": "Cube"`.
- `transform`: set absolute location/rotation/scale on one object.
- `undo`: run one Blender undo.
- `save`: save the currently open .blend in place.

Example transform:

````text
<!-- blender-remote:v1 -->
```json
{
  "id": "move-cube-001",
  "action": "transform",
  "object": "Cube",
  "location": [1.0, 0.0, 0.0]
}
```
````

## Arbitrary Blender Python

Disabled by default. Enable it only for a session you trust:

```powershell
.\tools\blender_remote\start.ps1 -AllowPython
```

Then the `python` action is accepted:

````text
<!-- blender-remote:v1 -->
```json
{
  "id": "python-001",
  "action": "python",
  "code": "import bpy\nprint([o.name for o in bpy.context.scene.objects])"
}
```
````

Arbitrary Blender Python is effectively high privilege. The daemon therefore accepts commands only from the GitHub login `francesco-bufalini`, and Python must additionally be enabled locally.

## Local state

The last consumed GitHub comment ID is stored outside the repository at:

`%LOCALAPPDATA%\VTT\blender_remote_state.json`

This prevents an old mutation from being executed again after a daemon restart.


## Viewport inspection

````text
<!-- blender-remote:v1 -->
```json
{
  "id": "viewport-001",
  "action": "viewport"
}
```
````

## Viewport screenshot

````text
<!-- blender-remote:v1 -->
```json
{
  "id": "screenshot-001",
  "action": "screenshot",
  "max_width": 640,
  "quality": 55
}
```
````

The daemon captures the largest currently open `VIEW_3D` editor with Blender's screenshot-area operator. The image is automatically reduced until the JPEG can fit in a single GitHub comment. No GitHub Action, public web server, Tailscale endpoint, or repository commit is used for the image transfer.
