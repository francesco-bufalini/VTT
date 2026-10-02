#!/usr/bin/env python3
"""Build the compact creature-size index used by the token converter.

The index can be built either from a local 5etools-src checkout or directly
from the public 5etools-src GitHub mirror. Only compact creature size metadata
is retained; the full bestiary is never copied into the VTT repository.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from creature_size_lookup import SIZE_CODE_TO_NAME, SIZE_TO_FOOTPRINT

DEFAULT_BASE_URL = (
    "https://raw.githubusercontent.com/"
    "5etools-mirror-3/5etools-src/main/data/bestiary"
)
SOURCE_EDITIONS = {
    "MM": "2014",
    "XMM": "2024",
}


def edition_for_source(source: str) -> str:
    return SOURCE_EDITIONS.get(source, "unknown")


def extract_size_name(raw: Any) -> str | None:
    values = raw if isinstance(raw, list) else [raw]
    names: list[str] = []
    for value in values:
        code = ""
        if isinstance(value, str):
            code = value
        elif isinstance(value, dict):
            code = str(value.get("size", ""))
        name = SIZE_CODE_TO_NAME.get(code)
        if name and name not in names:
            names.append(name)
    return names[0] if len(names) == 1 else None


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "root",
        nargs="?",
        help="Optional local 5etools-src checkout.",
    )
    parser.add_argument(
        "--online",
        action="store_true",
        help="Download bestiary JSON from the public 5etools-src GitHub mirror.",
    )
    parser.add_argument("--output", required=True)
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    return parser.parse_args(argv)


def read_json_url(url: str) -> dict:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "VTT-token-converter/1.0"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def load_sources(args: argparse.Namespace) -> tuple[dict, callable]:
    if args.online:
        base_url = args.base_url.rstrip("/")
        index = read_json_url(f"{base_url}/index.json")

        def load_file(filename: str) -> dict:
            return read_json_url(f"{base_url}/{filename}")

        return index, load_file

    if not args.root:
        raise SystemExit("Pass a 5etools-src checkout or use --online.")

    root = Path(args.root).expanduser().resolve()
    bestiary = root / "data" / "bestiary"
    index_path = bestiary / "index.json"
    if not index_path.is_file():
        raise SystemExit(f"5eTools bestiary index not found: {index_path}")
    index = json.loads(index_path.read_text(encoding="utf-8"))

    def load_file(filename: str) -> dict:
        path = bestiary / filename
        return json.loads(path.read_text(encoding="utf-8"))

    return index, load_file


def main() -> None:
    args = parse_args()
    index, load_file = load_sources(args)
    filenames = sorted({str(v) for v in index.values() if str(v).endswith(".json")})

    records: list[dict[str, Any]] = []
    skipped_ambiguous_size = 0
    loaded_files = 0
    for filename in filenames:
        try:
            payload = load_file(filename)
        except Exception as exc:
            print(f"WARNING: could not load {filename}: {exc}")
            continue
        loaded_files += 1
        for monster in payload.get("monster", []):
            name = str(monster.get("name", "")).strip()
            source = str(monster.get("source", "")).strip()
            if not name or not source:
                continue
            size_name = extract_size_name(monster.get("size"))
            if not size_name:
                skipped_ambiguous_size += 1
                continue
            records.append({
                "name": name,
                "source": source,
                "edition": edition_for_source(source),
                "size_name": size_name,
                "footprint": SIZE_TO_FOOTPRINT[size_name],
            })

    if loaded_files == 0 or not records:
        raise SystemExit("No 5eTools bestiary data could be loaded.")

    records.sort(key=lambda r: (str(r["name"]).lower(), str(r["source"])))
    output = Path(args.output).expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({
        "schema_version": 1,
        "generated_from": (
            args.base_url if args.online else str(Path(args.root).resolve())
        ),
        "preferred_ruleset": "2014",
        "creatures": records,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"Wrote {len(records)} creature size records -> {output}")
    print(f"Loaded bestiary files: {loaded_files}/{len(filenames)}")
    if skipped_ambiguous_size:
        print(f"Skipped {skipped_ambiguous_size} records with conditional/ambiguous size")


if __name__ == "__main__":
    main()
