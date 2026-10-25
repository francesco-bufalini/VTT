#!/usr/bin/env python3
"""Regenerate numeric ability grants from explicit 5etools 'ability' fields.

Usage: python scripts/generate_structured_ability_grants.py /path/to/5etools-src
Fixed modifiers are automatic; feat choices retain structured options for the UI.
Never parse prose or manufacture a choice on behalf of the user.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ABILITIES = ("str", "dex", "con", "int", "wis", "cha")


def fixed_ability(raw):
    options = raw if isinstance(raw, list) else [raw]
    fixed = None
    for option in options:
        if not isinstance(option, dict):
            return {}
        current = {stat: option[stat] for stat in ABILITIES
                   if isinstance(option.get(stat), (int, float))
                   and not isinstance(option[stat], bool)}
        if fixed is None:
            fixed = current
        else:
            fixed = {stat: value for stat, value in fixed.items()
                     if current.get(stat) == value}
    return fixed or {}


def build(root):
    races = json.loads((root / "data/races.json").read_text(encoding="utf-8"))
    feats = json.loads((root / "data/feats.json").read_text(encoding="utf-8"))
    backgrounds = json.loads((root / "data/backgrounds.json").read_text(encoding="utf-8"))
    sources = {
        "race": races.get("race", []),
        "subrace": races.get("subrace", []),
        "feat": feats.get("feat", []),
        "background": backgrounds.get("background", []),
    }
    output = {"meta": {
        "source": "5etools-mirror-3/5etools-src",
        "purpose": "fixed numeric increments and structured feat ability-score choices",
        "generated_from": ["data/races.json", "data/feats.json", "data/backgrounds.json"],
    }}
    for category, rows in sources.items():
        grants = []
        for raw in rows:
            if not raw.get("name") or not raw.get("source"):
                continue
            ability = raw.get("ability")
            fixed = fixed_ability(ability)
            variants = ability if isinstance(ability, list) else [ability]
            # 5etools grants can expose a score choice on species or backgrounds, too.
            # Preserve the data rather than silently discarding non-feat choices.
            choices = any(isinstance(option, dict) and isinstance(option.get("choose"), dict)
                          for option in variants)
            if not fixed and not choices:
                continue
            entry = {"name": raw["name"], "source": raw["source"]}
            if fixed:
                entry["ability"] = fixed
            if choices:
                entry["ability_choices"] = ability
            if category == "subrace":
                entry["raceName"] = raw.get("raceName", "")
                entry["raceSource"] = raw.get("raceSource", "")
            grants.append(entry)
        output[category] = grants
    return output


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: generate_structured_ability_grants.py /path/to/5etools-src")
    data = build(Path(sys.argv[1]))
    destination = ROOT / "vtt/data/structured_ability_grants_5etools.json"
    destination.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Wrote {destination}: " +
          ", ".join(f"{key}={len(data[key])}" for key in ("race", "subrace", "feat", "background")))


if __name__ == "__main__":
    main()
