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
    args = sys.argv[1:]
    background_only = "--backgrounds-only" in args
    args = [arg for arg in args if arg != "--backgrounds-only"]
    if len(args) != 1:
        raise SystemExit("Usage: generate_structured_ability_grants.py /path/to/5etools-src [--backgrounds-only]")
    root = Path(args[0])
    destination = ROOT / "vtt/data/structured_ability_grants_5etools.json"
    if background_only:
        upstream = json.loads((root / "data/backgrounds.json").read_text(encoding="utf-8"))
        # Reuse the same explicit 5eTools projection as the full generator,
        # without changing the already-audited race/subrace/feat indexes.
        entries = []
        for raw in upstream.get("background", []):
            if not raw.get("name") or not raw.get("source"):
                continue
            ability = raw.get("ability")
            fixed = fixed_ability(ability)
            variants = ability if isinstance(ability, list) else [ability]
            has_choice = any(isinstance(option, dict) and isinstance(option.get("choose"), dict)
                             for option in variants)
            if not fixed and not has_choice:
                continue
            entry = {"name": raw["name"], "source": raw["source"]}
            if fixed:
                entry["ability"] = fixed
            if has_choice:
                entry["ability_choices"] = ability
            entries.append(entry)
        data = json.loads(destination.read_text(encoding="utf-8"))
        data["background"] = sorted(entries,
                                    key=lambda row: (row["name"].casefold(), row["source"].casefold()))
        data.setdefault("meta", {})["backgroundSource"] = "data/backgrounds.json"
    else:
        data = build(root)
    destination.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Wrote {destination}: " +
          ", ".join(f"{key}={len(data[key])}" for key in ("race", "subrace", "feat", "background")))


if __name__ == "__main__":
    main()
