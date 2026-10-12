#!/usr/bin/env python3
"""Regenerate fixed ability-score increases from 5etools structured `ability`.

Choice-based increases are never inferred or silently selected. The generated
snapshot replaces manual maintenance of the 171 pre-existing grants.
Usage: python scripts/generate_ability_grants.py /path/to/5etools-src
"""
import json
import sys
from pathlib import Path

ABILITIES = ("str", "dex", "con", "int", "wis", "cha")
OUT = Path(__file__).resolve().parents[1] / "vtt/data/structured_ability_grants_5etools.json"


def fixed_scores(raw):
    options = raw if isinstance(raw, list) else [raw]
    intersection = None
    for option in options:
        if not isinstance(option, dict):
            return {}
        current = {
            ability: option[ability] for ability in ABILITIES
            if isinstance(option.get(ability), (float, int))
            and not isinstance(option.get(ability), bool)
        }
        if intersection is None:
            intersection = current
        else:
            intersection = {
                ability: score for ability, score in intersection.items()
                if current.get(ability) == score
            }
    return intersection or {}


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
    output = {
        "meta": {"source": "5etools-mirror-3/5etools-src",
                 "purpose": "fixed structured ability-score increments; mutually exclusive ability choices excluded"}
    }
    for category, entries in sources.items():
        rows = []
        for entry in entries:
            if not entry.get("name") or not entry.get("source") or "ability" not in entry:
                continue
            fixed = fixed_scores(entry["ability"])
            if not fixed:
                continue
            row = {"name": entry["name"], "source": entry["source"], "ability": fixed}
            if category == "subrace":
                row["raceName"] = entry.get("raceName", "")
                row["raceSource"] = entry.get("raceSource", "")
            rows.append(row)
        output[category] = rows
    return output


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python scripts/generate_ability_grants.py /path/to/5etools-src")
    data = build(Path(sys.argv[1]))
    OUT.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print("Generated fixed ability grants: " + ", ".join(
        f"{key}={len(data[key])}" for key in ("race", "subrace", "feat", "background")))


if __name__ == "__main__":
    main()
