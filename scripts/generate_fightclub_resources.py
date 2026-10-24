#!/usr/bin/env python3
"""Refresh the curated Fight Club class-counter supplement from a LOCAL checkout.

Usage:
  python scripts/generate_fightclub_resources.py /path/to/fightclub5exml

This is a build-time utility, not part of the game. Never downloads network
content at runtime. The checked-in JSON is a curated allowlist: running this
script refreshes existing approved names, not arbitrary new counters.
Other Fight Club structured fields can be added to this pipeline later.
"""
from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "vtt/data/class_resource_overrides.json"
SOURCE = Path(
    "Sources/DND_5e/WizardsOfTheCoast/01_Core/01_Players_Handbook"
)

# Fight Club notation must never be persisted into the VTT's JSON files.
# Convert external counters once, during asset preparation, to the native
# arithmetic formula syntax already used by creature_bonus_rules.gd.
FIGHTCLUB_MODIFIERS = {
    "1": "str_mod",
    "2": "dex_mod",
    "3": "con_mod",
    "4": "int_mod",
    "5": "wis_mod",
    "6": "cha_mod",
    "7": "level",
    "8": "proficiency",
}
VTT_FORMULA_SYMBOLS = {
    *(f"{ability}_{kind}" for ability in ("str", "dex", "con", "int", "wis", "cha")
      for kind in ("mod", "score")),
    "proficiency", "prof", "level", "initiative", "ac", "speed",
    "climb_speed", "swim_speed", "fly_speed", "burrow_speed",
    "max_hp", "passive_perception",
}


def to_vtt_formula(raw: str) -> str:
    """Convert selected Fight Club counter maxima to VTT-native expressions.

    Fail closed for unknown placeholders, dice, function calls or unsupported
    identifiers. These counters represent quantities, not roll formulas.
    """
    raw = str(raw).strip()

    def convert_placeholder(match: re.Match[str]) -> str:
        index = match.group(1)
        if index not in FIGHTCLUB_MODIFIERS:
            raise ValueError(f"Unsupported Fight Club counter token: {match.group()}")
        return FIGHTCLUB_MODIFIERS[index]

    converted = re.sub(r"%(\d+)", convert_placeholder, raw).lower()
    if not re.fullmatch(r"[0-9a-z_ .+*/()\-]+", converted):
        raise ValueError(f"Invalid or unconverted counter formula: {raw!r}")
    unknown = set(re.findall(r"[a-z_][a-z0-9_]*", converted)) - VTT_FORMULA_SYMBOLS
    if unknown:
        raise ValueError(f"Unsupported native formula symbol(s) {sorted(unknown)}: {raw!r}")
    return converted



def read_counters(xml_file: Path) -> dict[tuple[str, str], list[dict]]:
    result: dict[tuple[str, str], list[dict]] = {}
    document = ET.parse(xml_file).getroot()
    for klass in document.findall("class"):
        for auto in klass.findall("autolevel"):
            level = int(auto.get("level", 0))
            for counter in auto.findall("counter"):
                name = (counter.findtext("name") or "").strip()
                subclass = (counter.findtext("subclass") or "").strip()
                value = (counter.findtext("value") or "").strip()
                reset = (counter.findtext("reset") or "").strip()
                if not name or not value or reset not in ("L", "S"):
                    continue
                result.setdefault((name, subclass), []).append({
                    "level": level,
                    "value": value,
                    "reset": "short_rest" if reset == "S" else "long_rest",
                })
    return result


def main(checkout: Path) -> None:
    existing = json.loads(OUTPUT.read_text(encoding="utf-8"))
    changed = 0
    for group in existing["classes"]:
        if group["source"] != "PHB":
            continue
        class_name = group["class"].lower()
        file = checkout / SOURCE / f"class-{class_name}-phb.xml"
        if not file.exists():
            raise FileNotFoundError(file)
        counters = read_counters(file)
        for definition in group["resources"]:
            if definition.get("source", group["source"]) != "PHB":
                # This importer reads PHB XML only. Preserve separately
                # source-qualified subclass counters from later books.
                continue
            key = (definition.get("source_counter", definition["name"]), definition.get("subclass", ""))
            # Older XML has two subclass features without a <subclass> tag.
            original_key = key
            if key == ("Natural Recovery", "Circle of the Land"):
                original_key = ("Natural Recovery", "")
            source_steps = counters.get(original_key, [])
            if not source_steps:
                raise ValueError(f"Curated counter missing upstream: {group['class']} {key}")
            # Preserve verified corrections to upstream data.
            for step in source_steps:
                if (class_name == "fighter" and key[0] == "Indomitable"
                        or class_name == "wizard" and key[0] == "Arcane Recovery"):
                    step["reset"] = "long_rest"
            unique = {row["level"]: row for row in source_steps}
            # Source XML is only interpreted here; the game loads VTT-native
            # values with no Fight Club placeholder translation at runtime.
            definition["steps"] = [
                {**unique[level], "value": to_vtt_formula(unique[level]["value"])}
                for level in sorted(unique)
            ]
            changed += 1
    OUTPUT.write_text(
        json.dumps(existing, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Refreshed {changed} curated counters from local Fight Club XML")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(Path(sys.argv[1]))
