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

BLENDER_HOST = os.getenv("BLENDER_REMOTE_HOST", "127.0.0.1")
BLENDER_PORT = int(os.getenv("BLENDER_REMOTE_PORT", "9876"))
POLL_SECONDS = max(1.0, float(os.getenv("BLENDER_REMOTE_POLL_SECONDS", "3")))
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
        "Unknown action. Supported: ping, scene, object, transform, undo, save"
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


def fetch_latest_comment_id() -> int:
    query = urllib.parse.urlencode(
        {"per_page": 1, "sort": "created", "direction": "desc"}
    )
    _, comments, _ = github_request("GET", f"{COMMENTS_URL}?{query}")
    if not comments:
        return 0
    return int(comments[0]["id"])


def fetch_comments(etag: str | None) -> tuple[list[dict[str, Any]], str | None]:
    query = urllib.parse.urlencode(
        {"per_page": 100, "sort": "created", "direction": "desc"}
    )
    status, comments, headers = github_request(
        "GET",
        f"{COMMENTS_URL}?{query}",
        etag=etag,
    )
    if status == 304:
        return [], etag
    new_etag = headers.get("ETag") or headers.get("Etag")
    ordered = sorted(list(comments or []), key=lambda item: int(item["id"]))
    return ordered, new_etag


def main() -> int:
    if not REPO or "/" not in REPO:
        fail("BLENDER_REMOTE_REPO must be owner/repository.")
    if not ALLOWED_LOGINS:
        fail("BLENDER_REMOTE_ALLOWED must contain at least one GitHub login.")

    state = load_state()
    state_key = f"{REPO}#{ISSUE_NUMBER}"

    if state.get("console") != state_key:
        last_comment_id = fetch_latest_comment_id()
        state = {"console": state_key, "last_comment_id": last_comment_id}
        save_state(state)
    else:
        last_comment_id = int(state.get("last_comment_id", 0))

    print("Blender Remote Daemon")
    print(f"  Console : https://github.com/{REPO}/issues/{ISSUE_NUMBER}")
    print(f"  Allowed : {', '.join(sorted(ALLOWED_LOGINS))}")
    print(f"  Blender : {BLENDER_HOST}:{BLENDER_PORT}")
    print(f"  Poll    : {POLL_SECONDS:g}s")
    print(f"  Python  : {'ENABLED' if ALLOW_PYTHON else 'disabled'}")
    print(f"  Resume  : after GitHub comment id {last_comment_id}")
    print()
    print("Waiting for commands. Ctrl+C to stop.")

    etag: str | None = None

    while True:
        try:
            comments, etag = fetch_comments(etag)

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
                except Exception as exc:
                    error = {
                        "error": type(exc).__name__,
                        "message": str(exc),
                    }
                    post_result(command_id, comment_id, False, error)
                    print(f"< {command_id} ERROR: {exc}")

        except KeyboardInterrupt:
            print("\nStopped.")
            return 0
        except Exception as exc:
            print(f"[bridge error] {type(exc).__name__}: {exc}", file=sys.stderr)
            etag = None
            time.sleep(10)
            continue

        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    raise SystemExit(main())
