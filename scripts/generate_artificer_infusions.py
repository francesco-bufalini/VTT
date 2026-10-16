#!/usr/bin/env python3
"""Regenerate the compact TCE Artificer infusion index from structured sources.

Usage:
  python scripts/generate_artificer_infusions.py \
      /path/to/5etools-src/data/optionalfeatures.json \
      /path/to/fightclub5exml/.../optionalfeatures-tce.xml

5etools is authoritative for typed prerequisites and replicable-item tables.
FightClub5eXML's Artificer Infusions spell-class tags are cross-checked, not
loaded as castable spells. Item bonuses are exposed in the existing VTT numeric
item schema; conditional effects remain descriptive/manual.
"""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

OUTPUT = Path(__file__).resolve().parents[1] / "vtt/data/artificer_infusions_5etools.json"

# 5etools optional-feature effects are written as prose, not item bonus keys.
# Explicit, unambiguous numerical effects only; other mechanics are not guessed.
NUMERIC_ITEM_BONUSES = {
    "enhanced defense": {"bonus_ac": 1, "upgrade_level": 10},
    "enhanced weapon": {"bonus_weapon": 1, "upgrade_level": 10},
    "enhanced arcane focus": {"bonus_spell_attack": 1, "upgrade_level": 10},
    "radiant weapon": {"bonus_weapon": 1},
    "repulsion shield": {"bonus_ac": 1},
    "returning weapon": {"bonus_weapon": 1},
    "repeating shot": {"bonus_weapon": 1},
}


def normalized_name(text):
    return re.sub(r"\s*\(Level \d+\)$", "", text.removeprefix("Infusion: ").strip()).casefold()


def build(source: Path, fightclub: Path):
    optional = json.loads(source.read_text(encoding="utf-8"))["optionalfeature"]
    root = ET.parse(fightclub).getroot()
    names = {}
    for spell in root.findall("spell"):
        if spell.findtext("classes") != "Artificer Infusions [Legacy]":
            continue
        label = spell.findtext("name", "")
        if label.startswith("Infusion: "):
            names[normalized_name(label)] = label
    infusions = []
    for feat in optional:
        if feat.get("source") != "TCE" or "AI" not in feat.get("featureType", []):
            continue
        name = feat["name"]
        key = name.casefold()
        if key not in names:
            raise ValueError(f"Missing FightClub Artificer Infusion: {name}")
        prerequisite = (feat.get("prerequisite") or [{}])[0]
        target = (prerequisite.get("item") or [""])[0]
        minimum = prerequisite.get("level", {}).get("level", 2)
        row = {
            "id": f"infusion|tce|{key}", "name": name, "source": "TCE",
            "min_level": minimum, "item_prerequisite": target,
            "requires_attunement": "requires attunement" in target.casefold(),
            "fightclub_name": names[key],
        }
        if key in NUMERIC_ITEM_BONUSES:
            row["numeric_item_bonuses"] = NUMERIC_ITEM_BONUSES[key]
        if name == "Replicate Magic Item":
            replicable = []
            for value in feat.get("entries", []):
                if not isinstance(value, dict) or value.get("type") != "table":
                    continue
                caption = value.get("caption", "")
                if not caption.startswith("Replicable Items"):
                    continue
                match = re.search(r"\d+", caption)
                required_level = int(match.group()) if match else 2
                for cells in value.get("rows", []):
                    item = re.search(r"\{@item ([^}|]+)", str(cells[0]))
                    if item:
                        replicable.append({"name": item.group(1), "level": required_level})
            row["replicable_items"] = replicable
        infusions.append(row)
    if len(names) != len(infusions):
        raise ValueError("FightClub and 5etools Artificer infusion counts differ")
    return {
        "meta": {
            "primary": "5etools-src/data/optionalfeatures.json (featureType AI, TCE)",
            "secondary": "vidalvanbergen/fightclub5exml optionalfeatures-tce.xml (Infusion spell tags)",
            "notes": "Catalog mechanics and eligibility; descriptions remain in the existing 5etools compendium. Numeric mappings transcribed from unambiguous item benefits and exposed through VTT's native item bonus fields.",
        },
        "infusions": infusions,
    }


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: generate_artificer_infusions.py optionalfeatures.json optionalfeatures-tce.xml")
    output = build(Path(sys.argv[1]), Path(sys.argv[2]))
    OUTPUT.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Updated {OUTPUT}: {len(output['infusions'])} infusion definitions")


if __name__ == "__main__":
    main()
