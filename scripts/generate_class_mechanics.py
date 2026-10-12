#!/usr/bin/env python3
"""Generate non-spell class mechanics from structured 5etools class JSON.

No class name, feature name, progression or translated label is enumerated here.
Usage: python scripts/generate_class_mechanics.py /path/to/5etools-src
"""
import json
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "vtt/data/structured_class_mechanics_5etools.json"


def build(root: Path) -> dict:
    index = json.loads((root / "data/class/index.json").read_text(encoding="utf-8"))
    classes = []
    for filename in sorted(set(index.values())):
        data = json.loads((root / "data/class" / filename).read_text(encoding="utf-8"))
        for raw in data.get("class", []):
            name, source = raw.get("name", ""), raw.get("source", "")
            if not name or not source:
                continue
            hd = raw.get("hd", {})
            features = []
            for ref in raw.get("classFeatures", []):
                if isinstance(ref, dict):
                    ref = ref.get("classFeature", "")
                if not isinstance(ref, str):
                    continue
                parts = ref.split("|")
                if len(parts) < 4:
                    continue
                try:
                    level = int(parts[-1])
                except ValueError:
                    continue
                features.append({"name": parts[0], "level": level})
            columns = []
            for group in raw.get("classTableGroups", []):
                labels, rows = group.get("colLabels", []), group.get("rows", [])
                for idx, label in enumerate(labels):
                    # Spell slots/counts and links to spell/optional-feature
                    # pickers are managed elsewhere, not by resource trackers.
                    if not isinstance(label, str) or label.startswith("{@"):
                        continue
                    if "spell" in label.lower() or "cantrip" in label.lower() or "slot" in label.lower():
                        continue
                    values = [row[idx] if idx < len(row) else None for row in rows]
                    columns.append({"name": label, "levels": values})
            classes.append({
                "name": name, "source": source,
                "hit_dice": int(hd.get("faces", 0)),
                "features": features, "columns": columns
            })
    classes.sort(key=lambda c: (c["name"].lower(), c["source"]))
    return {"meta": {
        "source": "5etools-src/data/class/class-*.json",
        "kind": "structured classTableGroups, classFeatures and hd",
        "note": "Raw typed table values preserved; no class-specific tracker mapping or translations."
    }, "classes": classes}


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: generate_class_mechanics.py /path/to/5etools-src")
    data = build(Path(sys.argv[1]))
    OUT.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Generated structured mechanics for {len(data['classes'])} classes: {OUT}")


if __name__ == "__main__":
    main()
