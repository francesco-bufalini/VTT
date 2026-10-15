#!/usr/bin/env bash
# Build the same isolated, 2D-only mobile app used by the Android workflow.
# This copy is used only by macOS CI; the Windows PowerShell script is unchanged.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: bash tools/prepare_mobile_export.sh <source> <new-destination>" >&2
  exit 2
fi
source_dir="$(cd "$1" && pwd -P)"
dest="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$2")"
case "$dest" in
  "$source_dir"|"$source_dir"/*) echo "Staging must be outside the source checkout" >&2; exit 2;;
esac
if [[ -e "$dest" ]]; then
  echo "Staging directory already exists: $dest" >&2
  exit 2
fi
mkdir -p "$dest"
rsync -a \
  --exclude='/.git/' --exclude='/.godot/' --exclude='/build/' \
  --exclude='/outputs/' --exclude='/blender/' --exclude='/export_templates/' \
  --exclude='/encounter/assets/' --exclude='/assets/presets/' \
  --exclude='*.glb' --exclude='*.gltf' --exclude='*.blend' \
  --exclude='*.obj' --exclude='*.fbx' --exclude='*.stl' \
  --exclude='*.scn' --exclude='*.exr' \
  "$source_dir/" "$dest/"

python3 - "$dest" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
presets_file = root / "export_presets.cfg"
project_file = root / "project.godot"
presets = presets_file.read_text(encoding="utf-8")
old_roots = 'export_files=PackedStringArray("res://vtt/menu/main_menu.tscn", "res://vtt/mobile/creatures_mobile.tscn")'
new_roots = 'export_files=PackedStringArray("res://vtt/mobile/creatures_mobile.tscn")'
if presets.count(old_roots) != 2:  # Android + iOS share the same mobile export roots.
    raise SystemExit("Unexpected Android/iOS resource selection: keep mobile staging in sync.")
presets = presets.replace(old_roots, new_roots)
# Keep the Android emulator architecture switch isolated to staging, as on Windows.
if presets.count("architectures/x86_64=true") != 1:
    raise SystemExit("Expected exactly one Android x86_64 architecture setting.")
presets = presets.replace("architectures/x86_64=true", "architectures/x86_64=false")
presets_file.write_text(presets, encoding="utf-8")
project = project_file.read_text(encoding="utf-8")
old_scene = 'run/main_scene="res://vtt/menu/main_menu.tscn"'
if project.count(old_scene) != 1:
    raise SystemExit("Could not find expected desktop main scene.")
project_file.write_text(project.replace(old_scene, 'run/main_scene="res://vtt/mobile/creatures_mobile.tscn"'), encoding="utf-8")

required = [
    "project.godot", "vtt/menu/main_menu.tscn",
    "vtt/mobile/creatures_mobile.tscn",
    "vtt/data/player_5etools_catalog.json",
    "vtt/data/compendium_items_5etools.json",
    "vtt/data/miniature_bestiary.json",
]
missing = [p for p in required if not (root / p).is_file()]
if missing:
    raise SystemExit(f"Missing mobile resources in staging: {missing}")
forbidden = {".glb", ".gltf", ".blend", ".obj", ".fbx", ".stl", ".scn", ".exr"}
leaked = [str(p.relative_to(root)) for p in root.rglob("*") if p.is_file() and p.suffix.lower() in forbidden]
if leaked:
    raise SystemExit(f"Desktop-only resources leaked to mobile staging: {leaked[:10]}")
print(f"Portable mobile stage verified at: {root}")
PY
