"""Rebuild the local, compact 5etools subclass and feature indexes.

This generator retains identifiers, class/source associations and feature levels.
It retains the upstream structured feature text for offline display. For reproducible
offline builds, populate .5etools-cache/class from the upstream repository.
"""
import argparse
import json
import urllib.request
from pathlib import Path
from urllib.parse import quote

from generate_effects_catalog import ROOT

BASE = "https://raw.githubusercontent.com/5etools-mirror-3/5etools-src/main/data/"


def build(offline=False, refresh=False):
    def read(filename):
        cache = ROOT / ".5etools-cache" / filename
        if refresh or not cache.exists():
            if offline:
                raise RuntimeError("Offline cache missing: " + filename)
            with urllib.request.urlopen(BASE + filename, timeout=30) as response:
                payload = response.read()
            json.loads(payload)
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_bytes(payload)
        return json.loads(cache.read_text(encoding="utf-8"))

    def encode(parts):
        # Match the encodeURIComponent IDs of the shipped catalogs.
        return quote("|".join(str(part) for part in parts).lower(), safe="-_.!~*'()")

    subclasses = {}
    features = {}
    feature_raws = {}
    class_index = read("class/index.json")
    for key, filename in sorted(class_index.items()):
        if key in ("mystic", "sidekick"):
            continue
        data = read("class/" + filename)
        for raw in data.get("subclass", []):
            name = str(raw.get("name", ""))
            short_name = str(raw.get("shortName", name))
            class_name = str(raw.get("className", key))
            class_source = str(raw.get("classSource", ""))
            source = str(raw.get("source", ""))
            if not name or not class_name:
                continue
            row_id = "5etools:subclasses:" + encode(
                [class_name, class_source, source, short_name]
            )
            subclasses[row_id] = {
                "id": row_id,
                "name": name,
                "short_name": short_name,
                "source": source,
                "class_name": class_name,
                "class_source": class_source,
                "origin": "5etools",
            }
        for raw in data.get("subclassFeature", []):
            name = str(raw.get("name", ""))
            class_name = str(raw.get("className", key))
            class_source = str(raw.get("classSource", ""))
            short_name = str(raw.get("subclassShortName", ""))
            subclass_source = str(raw.get("subclassSource", ""))
            level = raw.get("level", 0)
            source = str(raw.get("source", ""))
            if not short_name or not name:
                continue
            row_id = "5etools:subclass_features:" + encode(
                [class_name, class_source, short_name, subclass_source, level, source, name]
            )
            feature_raws[row_id] = raw
            features[row_id] = {
                "id": row_id,
                "name": name,
                "source": source,
                "class_name": class_name,
                "class_source": class_source,
                "subclass_short_name": short_name,
                "subclass_source": subclass_source,
                "level": level,
                "entries": raw.get("entries", []),
                "origin": "5etools",
            }

    # Resolve 5etools inheritance: newer-edition records frequently use
    # _copy rather than repeating the structured feature text.
    def inherited_entries(feature_id, seen=None):
        seen = set() if seen is None else seen
        if feature_id in seen or feature_id not in features:
            return []
        seen.add(feature_id)
        feature = features[feature_id]
        if feature["entries"]:
            return feature["entries"]
        raw = feature_raws[feature_id]
        copy = raw.get("_copy", {})
        if not copy:
            return []
        target = "5etools:subclass_features:" + encode([
            copy.get("className", raw.get("className", "")),
            copy.get("classSource", raw.get("classSource", "")),
            copy.get("subclassShortName", raw.get("subclassShortName", "")),
            copy.get("subclassSource", raw.get("subclassSource", "")),
            copy.get("level", raw.get("level", 0)),
            copy.get("source", raw.get("source", "")),
            copy.get("name", raw.get("name", "")),
        ])
        return inherited_entries(target, seen)

    for feature_id, feature in features.items():
        if not feature["entries"]:
            feature["entries"] = inherited_entries(feature_id)

    full_names = {
        (row["class_name"].lower(), row["class_source"].lower(),
         row["short_name"].lower(), row["source"].lower()): row["name"]
        for row in subclasses.values()
    }
    for row in features.values():
        key = (row["class_name"].lower(), row["class_source"].lower(),
               row["subclass_short_name"].lower(), row["subclass_source"].lower())
        row["subclass_name"] = full_names.get(key, row["subclass_short_name"])
        if row["subclass_name"] == row["subclass_short_name"]:
            alternate = next((
                subclass["name"] for subclass in subclasses.values()
                if subclass["class_name"].lower() == key[0]
                and subclass["short_name"].lower() == key[2]
                and subclass["source"].lower() == key[3]
            ), None)
            if alternate:
                row["subclass_name"] = alternate

    data_dir = ROOT / "vtt/data"
    for filename, key, records in [
        ("subclasses_5etools.json", "subclasses", subclasses),
        ("subclass_features_5etools.json", "subclass_features", features),
    ]:
        target = data_dir / filename
        target.write_text(
            json.dumps({key: list(records.values())}, ensure_ascii=False,
                       separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        print(f"Wrote {len(records)} {key} entries: {target}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    build(args.offline, args.refresh)
