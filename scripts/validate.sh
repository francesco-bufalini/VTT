#!/usr/bin/env bash
set -euo pipefail

GODOT="${GODOT:-godot}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node "$PROJECT_ROOT/scripts/check_pwa_assets.mjs"
RUN_TESTS=false

if [[ "${1:-}" == "--tests" ]]; then
  RUN_TESTS=true
elif [[ -n "${1:-}" ]]; then
  echo "Usage: bash scripts/validate.sh [--tests]" >&2
  exit 2
fi

version="$("$GODOT" --version)"
[[ "$version" == 4.7.2.stable* ]] || {
  echo "Expected Godot 4.7.2 stable, found: $version" >&2
  exit 1
}

echo "== Import / parse =="
"$GODOT" --headless --path "$PROJECT_ROOT" --editor --import --quit

if $RUN_TESTS; then
  while IFS= read -r test_file; do
    relative="res://tests/$(basename "$test_file")"
    echo "== $relative =="
    "$GODOT" --headless --path "$PROJECT_ROOT" --script "$relative"
  done < <(find "$PROJECT_ROOT/tests" -maxdepth 1 -type f -name 'test_*.gd' | sort)
fi

echo "Validation passed."
