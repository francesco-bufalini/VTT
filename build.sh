#!/usr/bin/env bash
set -euo pipefail
GODOT="${GODOT:-godot}"
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$PROJECT_ROOT/build}"
TARGET="${1:-all}"
case "$TARGET" in all|windows|macos|android) ;; *) echo 'Uso: bash build.sh [all|windows|macos|android]'; exit 1;; esac
[[ "$("$GODOT" --version)" == 4.7.2.stable* ]] || { echo 'Servono Godot 4.7.2 stable e i relativi export template'; exit 1; }
run_godot() {
  local log status=0
  log="$("$GODOT" "$@" 2>&1)" || status=$?
  printf '%s\n' "$log"
  if [[ "$status" != 0 || "$log" == *'SCRIPT ERROR:'* || "$log" == *$'\nERROR:'* || "$log" == 'ERROR:'* ]]; then
    echo 'Godot ha segnalato un errore durante la build' >&2
    return 1
  fi
}
run_godot --headless --path "$PROJECT_ROOT" --editor --import --quit
if [[ "$TARGET" == all || "$TARGET" == windows ]]; then
  mkdir -p "$OUTPUT_ROOT/windows"
  run_godot --headless --path "$PROJECT_ROOT" --export-release 'Windows Desktop' "$OUTPUT_ROOT/windows/VTT.exe"
  [[ -f "$OUTPUT_ROOT/windows/VTT.exe" && -f "$OUTPUT_ROOT/windows/VTT.pck" ]]
fi
if [[ "$TARGET" == all || "$TARGET" == macos ]]; then
  mkdir -p "$OUTPUT_ROOT/macos"
  run_godot --headless --path "$PROJECT_ROOT" --export-release macOS "$OUTPUT_ROOT/macos/VTT-macOS.zip"
  [[ -f "$OUTPUT_ROOT/macos/VTT-macOS.zip" ]]
fi
if [[ "$TARGET" == all || "$TARGET" == android ]]; then
  mkdir -p "$OUTPUT_ROOT/android"
  run_godot --headless --path "$PROJECT_ROOT" --export-release Android "$OUTPUT_ROOT/android/VTT-Android.apk"
  [[ -f "$OUTPUT_ROOT/android/VTT-Android.apk" ]]
fi