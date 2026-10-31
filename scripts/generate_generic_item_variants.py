#!/usr/bin/env python3
"""Project 5eTools data/magicvariants.json into the offline PWA catalog.

Usage: python scripts/generate_generic_item_variants.py /path/to/5etools-src
The source JSON is not fetched at PWA runtime; generated output is committed.
"""
import copy
import json
import sys
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(sys.argv[1]) / "data/magicvariants.json" if len(sys.argv) > 1 else None
if SOURCE is None or not SOURCE.is_file():
    raise SystemExit("Provide a 5eTools checkout with data/magicvariants.json")
entries = json.loads(SOURCE.read_text(encoding="utf-8"))["magicvariant"]

def source(row):
    return row.get("source") or row.get("inherits", {}).get("source") or row.get("type", "").split("|")[-1]

by_key = {(row["name"], source(row)): row for row in entries}
cache = {}

def expanded(row):
    key = (row["name"], source(row))
    if key in cache:
        return cache[key]
    copied = row.get("_copy")
    parent = expanded(by_key[(copied["name"], copied["source"])]) if copied else {}
    merged = {**copy.deepcopy(parent), **copy.deepcopy(row),
              "inherits": {**copy.deepcopy(parent.get("inherits", {})), **copy.deepcopy(row.get("inherits", {}))}}
    for path, spec in (copied or {}).get("_mod", {}).items():
        field = path.split(".")[-1]
        mode = spec if isinstance(spec, str) else spec["mode"]
        if mode == "remove":
            merged["inherits"].pop(field, None)
        elif mode == "setProp":
            merged["inherits"][field] = spec["value"]
        elif mode in ("appendArr", "appendIfNotExistsArr"):
            values = spec["items"] if isinstance(spec["items"], list) else [spec["items"]]
            current = merged["inherits"].setdefault(field, [])
            for value in values:
                if mode == "appendArr" or value not in current:
                    current.append(value)
        else:
            raise ValueError(f"Unsupported 5eTools copy mode: {mode}")
    merged["name"], merged["source"] = row["name"], row.get("source") or merged["inherits"].get("source", "")
    merged.pop("_copy", None)
    cache[key] = copy.deepcopy(merged)
    return merged

variants = []
for row in entries:
    value = expanded(row)
    ident = lambda s: quote(s.lower(), safe="~!*'()-_.")
    item = {
        "id": "generic-variant:" + ident(value["source"]) + ":" + ident(value["name"]),
        "name": value["name"], "source": value["source"],
    }
    if value.get("edition"):
        item["edition"] = value["edition"]
    item["requires"] = value.get("requires", [])
    if value.get("excludes"):
        item["excludes"] = value["excludes"]
    item["inherits"] = value.get("inherits", {})
    if value.get("entries"):
        item["entries"] = value["entries"]
    variants.append(item)
out = ROOT / "pwa/catalog/generic_item_variants.json"
out.write_text(json.dumps({
    "version": 1,
    "source": "5etools-mirror-3/5etools-src data/magicvariants.json",
    "variants": variants,
}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(f"Exported {len(variants)} generic variants to {out}")
