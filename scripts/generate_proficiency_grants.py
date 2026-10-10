#!/usr/bin/env python3
"""Regenerate structured proficiency grants from 5etools-src JSON.

Usage:
    python scripts/generate_proficiency_grants.py /path/to/5etools-src

No prose parsing is performed. Class features and subclass features currently
lack structured proficiency fields in upstream data and are not inferred.
"""
import json
import sys
from pathlib import Path

FIELDS = (
    "skillProficiencies",
    "weaponProficiencies",
    "armorProficiencies",
    "toolProficiencies",
    "languageProficiencies",
    "expertise",
)
IGNORED_SOURCES = {"XDMG", "EFA"}


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def convert(kind: str, records: list[dict]) -> list[dict]:
    output = []
    for record in records:
        if not record.get("name") or not record.get("source"):
            continue
        if (record.get("edition") == "one" and record["source"] != "XPHB") or record["source"] in IGNORED_SOURCES:
            continue
        row = {"name": record["name"], "source": record["source"]}
        if kind == "subrace":
            row["raceName"] = record.get("raceName", "")
            row["raceSource"] = record.get("raceSource", "")
        for field in FIELDS:
            if field in record:
                row[field] = record[field]
        if kind == "class":
            if "proficiency" in record:
                row["savingThrows"] = record["proficiency"]
            if "startingProficiencies" in record:
                row["startingProficiencies"] = record["startingProficiencies"]
            multiclass = record.get("multiclassing", {})
            if "proficienciesGained" in multiclass:
                row["multiclassProficiencies"] = multiclass["proficienciesGained"]
            hit_dice = record.get("hd", {})
            equipment = record.get("startingEquipment", {})
            row["startingMeta"] = {
                "hitDice": f"1d{hit_dice['faces']}" if hit_dice.get("faces") else "",
                "hitPointsAtFirst": hit_dice.get("faces"),
                "equipment": equipment.get("default", []),
                "multiclass": multiclass.get("requirements", {}),
                "gold": equipment.get("goldAlternative", ""),
            }
        if any(key in row for key in FIELDS + (
            "savingThrows", "startingProficiencies", "multiclassProficiencies"
        )):
            output.append(row)
    return output


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: generate_proficiency_grants.py /path/to/5etools-src")
    root = Path(sys.argv[1])
    index = read_json(root / "data/class/index.json")
    sources = {
        "class": [],
        "race": [],
        "subrace": [],
        "background": [],
        "feat": [],
    }
    for file in index.values():
        data = read_json(root / "data/class" / file)
        sources["class"].extend(data.get("class", []))
    for filename in ["races.json", "backgrounds.json", "feats.json"]:
        data = read_json(root / "data" / filename)
        for category in ["race", "subrace", "background", "feat"]:
            sources[category].extend(data.get(category, []))
    out = {
        "meta": {
            "source": "5etools-mirror-3/5etools-src",
            "snapshot": "2026-10-10",
            "note": "Only structured proficiency fields; no natural-language extraction",
        }
    }
    for category, entries in sources.items():
        out[category] = convert(category, entries)
    destination = Path(__file__).resolve().parent.parent / "vtt/data/proficiency_grants_5etools.json"
    destination.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Wrote {destination}: " + ", ".join(f"{k}: {len(out[k])}" for k in sources))


if __name__ == "__main__":
    main()
