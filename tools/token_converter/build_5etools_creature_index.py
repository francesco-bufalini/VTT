#!/usr/bin/env python3
"""Build the compact creature-size index used by the token converter.

This intentionally stores only name/source/edition/size metadata, not 5eTools'
full bestiary text. It reuses the same local 5etools-src checkout already used
by vtt/spells/generate_5etools_catalog.py.

Usage:
    python tools/token_converter/build_5etools_creature_index.py C:/path/to/5etools-src
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from creature_size_lookup import SIZE_CODE_TO_NAME, SIZE_TO_FOOTPRINT

PROJECT_ROOT = Path(__file__).resolve().parents[2]
OUTPUT = PROJECT_ROOT / "assets" / "tokens" / "5etools_creature_index.json"
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


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    if len(argv) != 1:
        raise SystemExit("Pass a complete 5etools-src checkout.")
    root = Path(argv[0]).resolve()
    bestiary = root / "data" / "bestiary"
    index_path = bestiary / "index.json"
    if not index_path.is_file():
        raise SystemExit(f"5eTools bestiary index not found: {index_path}")

    index = json.loads(index_path.read_text(encoding="utf-8"))
    filenames = sorted({str(v) for v in index.values() if str(v).endswith(".json")})

    records: list[dict[str, Any]] = []
    skipped_ambiguous_size = 0
    for filename in filenames:
        path = bestiary / filename
        if not path.is_file():
            continue
        payload = json.loads(path.read_text(encoding="utf-8"))
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

    records.sort(key=lambda r: (str(r["name"]).lower(), str(r["source"])))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps({
        "schema_version": 1,
        "generated_from": "5etools-src/data/bestiary/index.json",
        "preferred_ruleset": "2014",
        "creatures": records,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(records)} creature size records -> {OUTPUT}")
    if skipped_ambiguous_size:
        print(f"Skipped {skipped_ambiguous_size} records with conditional/ambiguous size")


if __name__ == "__main__":
    main()
