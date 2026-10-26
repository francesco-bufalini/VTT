#!/usr/bin/env python3
"""Bundle structured 5etools additionalSpells from a LOCAL 5etools-src checkout.

Usage: python scripts/generate_additional_spells_5etools.py /path/to/5etools-src

Keeps original structured innate/known/prepared/expanded usage schemas.
Never parses English prose, invents spell picks, or downloads at runtime.
Unknown schema values are preserved for future compatibility, not guessed.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "vtt/data/additional_spells_5etools.json"
OWNERSHIP = ROOT / "vtt/data/additional_spell_ownership.json"
SOURCES = {
    "data/feats.json": ["feat"],
    "data/races.json": ["race", "subrace"],
    "data/backgrounds.json": ["background"],
    "data/optionalfeatures.json": ["optionalfeature"],
}


def gather(checkout: Path) -> dict:
    entries = []
    for relative, kinds in SOURCES.items():
        path = checkout / relative
        data = json.loads(path.read_text(encoding="utf-8"))
        for kind in kinds:
            for item in data.get(kind, []):
                blocks = item.get("additionalSpells")
                if not isinstance(blocks, list) or not blocks:
                    continue
                if kind == "subrace" and any(
                    "additionalSpells" in version and version["additionalSpells"] is None
                    for version in item.get("_versions", [])
                ):
                    # The spell package is one selectable version, not a
                    # grant from the unspecialized subrace itself.
                    continue
                row = {
                    "kind": kind,
                    "name": item["name"],
                    "source": item.get("source", ""),
                    "blocks": blocks,
                }
                if kind == "subrace":
                    row["race_name"] = item.get("raceName", "")
                    row["race_source"] = item.get("raceSource", "")
                entries.append(row)
    # Typed links and audited source corrections are maintained separately
    # from the upstream 5eTools export; regeneration must not erase them.
    if OWNERSHIP.exists():
        overrides = json.loads(OWNERSHIP.read_text(encoding="utf-8")).get("entries", [])
        typed = {
            (row["kind"], row["name"], row.get("source", "")): row
            for row in overrides
        }
        for row in entries:
            patch = typed.get((row["kind"], row["name"], row.get("source", "")))
            if not patch:
                continue
            if isinstance(patch.get("spell_traits"), dict):
                row["spell_traits"] = patch["spell_traits"]
            for index, fields in patch.get("block_overrides", {}).items():
                i = int(index)
                if 0 <= i < len(row["blocks"]) and isinstance(fields, dict):
                    row["blocks"][i].update(fields)
    return {
        "meta": {
            "source": "5etools-mirror-3/5etools-src",
            "source_fields": "additionalSpells (structured only)",
            "origin": "; ".join(SOURCES.keys()),
            "edition": "mixed PHB / XPHB",
            "build_only": True,
            "notes": "The game normalizes innate, known cantrips and limited prepared spells. Expanded spell lists are not consumable grants. Choice entries require explicit user selection.",
        },
        "entries": entries,
    }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    result = gather(Path(sys.argv[1]))
    OUTPUT.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Bundled {len(result['entries'])} sources with structured additionalSpells")
