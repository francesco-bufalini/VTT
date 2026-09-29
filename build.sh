#!/usr/bin/env bash
set -euo pipefail
GODOT="${GODOT:-godot}"
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-all}"
case "$TARGET" in all|windows|macos) ;; *) echo 'Uso: bash build.sh [all|windows|macos]'; exit 1;; esac
[[ "$("$GODOT" --version)" == 4.7.2.stable* ]] || { echo 'Servono Godot 4.7.2 stable e i relativi export template'; exit 1; }
"$GODOT" --headless --path "$PROJECT_ROOT" --editor --import --quit
if [[ "$TARGET" == all || "$TARGET" == windows ]]; then
  mkdir -p "$PROJECT_ROOT/build/windows"
  "$GODOT" --headless --path "$PROJECT_ROOT" --export-release 'Windows Desktop' "$PROJECT_ROOT/build/windows/Astrolabe.exe"
fi
if [[ "$TARGET" == all || "$TARGET" == macos ]]; then
  mkdir -p "$PROJECT_ROOT/build/macos"
  "$GODOT" --headless --path "$PROJECT_ROOT" --export-release macOS "$PROJECT_ROOT/build/macos/Astrolabe.zip"
fi
