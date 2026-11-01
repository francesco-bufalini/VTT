#!/usr/bin/env python3
"""Refresh structured background starting-feat refs in the local 5eTools mirror.

This does not write any VTT benefit catalog: the refs are upstream 5eTools
fields, not missing mechanics authored by VTT. Use the same 5eTools snapshot
as the other generated origin indexes.

Usage: python scripts/refresh_background_feat_refs.py /path/to/5etools-src
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "vtt/data/compendium_backgrounds_5etools.json"


def normalized_key(record):
    return (str(record.get("name", "")).casefold() + "|" +
            str(record.get("source", "")).casefold())


def apply_refs(compendium, upstream):
    available = {normalized_key(row): row for row in upstream
                 if row.get("name") and row.get("source")}
    updated = 0
    for key, row in compendium["backgrounds"].items():
        raw = available.get(key.casefold())
        if raw is None:
            continue
        if "feats" in raw:
            # Copy actual 5eTools fields as given. No prose parsing or
            # background-specific VTT rules. anyFromCategory remains a choice.
            row["feats"] = raw["feats"]
            updated += 1
        else:
            row.pop("feats", None)
    compendium.setdefault("meta", {})["backgroundFeatSource"] = "5etools-src/data/backgrounds.json"
    return updated


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: refresh_background_feat_refs.py /path/to/5etools-src")
    source = Path(sys.argv[1]) / "data/backgrounds.json"
    upstream = json.loads(source.read_text(encoding="utf-8"))["background"]
    compendium = json.loads(TARGET.read_text(encoding="utf-8"))
    count = apply_refs(compendium, upstream)
    TARGET.write_text(json.dumps(compendium, ensure_ascii=False,
                                 separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Updated {count} source-qualified background feat references in {TARGET}")


if __name__ == "__main__":
    main()
