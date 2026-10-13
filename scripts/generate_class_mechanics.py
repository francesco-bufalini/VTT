#!/usr/bin/env python3
"""Generate non-spell class mechanics from 5etools classTableGroups and hd.

Usage: python scripts/generate_class_mechanics.py /path/to/5etools-src
Retains numeric/typed columns without copying individual progressions or class
to feature mappings into VTT. Classification is conservative: equipment/skill
selection capacities are not consumable resources.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Generic semantic clues, never class-specific row/level/value associations.
RESOURCE_LABEL = re.compile(r"(?:\bpoints\b|\brages\b|\bchannel divinity\b|\bwild shape\b|\bsecond wind\b)", re.I)
SPELL_LABEL = re.compile(r"(?:\{@filter|\bspell slots\b|\bslot level\b)", re.I)


def scalar(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        text = value.strip()
        if text.lower() == "unlimited":
            return "unlimited"
        if re.fullmatch(r"[+-]?\d+", text):
            return int(text)
        return None
    if isinstance(value, dict) and value.get("type") == "bonus":
        raw = value.get("value")
        if isinstance(raw, (int, float)) and not isinstance(raw, bool):
            return raw
    return None


def feature_name(raw):
    ref = raw.get("classFeature", "") if isinstance(raw, dict) else raw
    return str(ref).split("|")[0].strip()


def references_column(value, column):
    # Genuine 5etools refClassFeature object; this is not prose parsing.
    if isinstance(value, dict):
        if value.get("type") == "refClassFeature" and str(
            value.get("classFeature", "")).split("|")[0].casefold() == column.casefold():
            return True
        return any(references_column(v, column) for v in value.values())
    if isinstance(value, list):
        return any(references_column(v, column) for v in value)
    return False


def origin_for(column, class_row, features):
    names = [feature_name(x) for x in class_row.get("classFeatures", [])]
    simple = column.casefold()
    singular = simple[:-1] if simple.endswith("s") else simple
    base = re.sub(r"\s+points$", "", simple)
    for name in names:
        if name.casefold() in (simple, singular, base):
            return name
    # Match first at the level the table column becomes available.
    # A feature that REFERENCES the column is stronger evidence than a
    # vaguely similar title (e.g. Innate Sorcery vs Font of Magic).
    positive = None
    for group in class_row.get("classTableGroups", []):
        for index, label in enumerate(group.get("colLabels", [])):
            if label != column:
                continue
            for level, row in enumerate(group.get("rows", []), 1):
                if isinstance(row, list) and index < len(row):
                    value = scalar(row[index])
                    if isinstance(value, (int, float)) and value > 0:
                        positive = level
                        break
            if positive is not None:
                break
    ranked = []
    for feat in features:
        if feat.get("className") != class_row.get("name") or feat.get("classSource") != class_row.get("source"):
            continue
        name = feat.get("name", "")
        if name not in names or (positive is not None and feat.get("level") != positive):
            continue
        body = json.dumps(feat.get("entries", [])).casefold()
        score = 0
        if references_column(feat.get("entries", []), column):
            score = 4
        elif f"{simple} column" in body or f"column of" in body and simple in body:
            score = 3
        elif f"represented by {simple}" in body:
            score = 2
        elif simple in body:
            score = 1
        if score:
            ranked.append((score, name))
    ranked.sort(reverse=True)
    if ranked and (len(ranked) == 1 or ranked[0][0] > ranked[1][0]):
        return ranked[0][1]
    for name in names:
        if base and base in name.casefold() and len(base) >= 3:
            return name
    return column


def build(root):
    index = json.loads((root / "data/class/index.json").read_text(encoding="utf-8"))
    rows = []
    for filename in sorted(set(index.values())):
        if filename in {"class-mystic.json", "class-sidekick.json"}:
            continue
        doc = json.loads((root / "data/class" / filename).read_text(encoding="utf-8"))
        for cls in doc.get("class", []):
            if cls.get("source") in {"EFA", "XDMG"}:
                continue
            hd = cls.get("hd", {}).get("faces")
            columns = []
            for group in cls.get("classTableGroups", []):
                labels = group.get("colLabels", [])
                for idx, label in enumerate(labels):
                    if SPELL_LABEL.search(str(label)):
                        continue
                    values = [scalar(row[idx]) if isinstance(row, list) and idx < len(row) else None
                              for row in group.get("rows", [])]
                    if not any(v is not None for v in values):
                        continue
                    typed_bonus = any(
                        isinstance(row, list) and idx < len(row) and isinstance(row[idx], dict)
                        and row[idx].get("type") == "bonus"
                        for row in group.get("rows", []))
                    kind = ("bonus" if typed_bonus else
                            "resource" if RESOURCE_LABEL.search(label) else "capacity")
                    columns.append({
                        "name": label, "kind": kind,
                        "origin_feature": origin_for(label, cls, doc.get("classFeature", [])),
                        "levels": values,
                    })
            rows.append({
                "name": cls["name"], "source": cls["source"], "hit_die": hd,
                "columns": columns,
                "spellcasting": {key: cls[key] for key in (
                    "cantripProgression", "spellsKnownProgression", "preparedSpells",
                    "preparedSpellsProgression", "spellsKnownProgressionFixed") if key in cls},
            })
    return {"meta": {
        "source": "5etools-src/data/class/class-*.json",
        "note": "Raw classTableGroups values. Generic classification; no hand-copied progressions or translated names."
    }, "classes": rows}


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit("Usage: generate_class_mechanics.py /path/to/5etools-src")
    result = build(Path(sys.argv[1]))
    output = ROOT / "vtt/data/class_mechanics_5etools.json"
    if len(sys.argv) == 3 and sys.argv[2] == "--spellcasting-only":
        previous = json.loads(output.read_text(encoding="utf-8"))
        spellcasting = {(row["name"], row["source"]): row.get("spellcasting", {}) for row in result["classes"]}
        for row in previous["classes"]:
            row["spellcasting"] = spellcasting.get((row["name"], row["source"]), {})
        result = previous
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {output}: {len(result['classes'])} classes")


if __name__ == "__main__":
    main()
