#!/usr/bin/env python3
"""Regenerate VTT-native monster recharge supplements from a LOCAL Fight Club checkout.

Usage:
    python scripts/generate_fightclub_monster_resources.py /path/to/FightClub5eXML
    python scripts/generate_fightclub_monster_resources.py /path/to/FightClub5eXML --check

Input sources are pinned in the checked-in JSON files' source_files allowlists.
Only literal <recharge> tags are converted; feature prose is never parsed.
No source files or copyrighted descriptions are bundled or fetched at runtime.
"""
from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = [
    ROOT / "vtt/data/fightclub_monster_resources_2014_a.json",
    ROOT / "vtt/data/fightclub_monster_resources_2014_b.json",
    ROOT / "vtt/data/fightclub_monster_resources_2014_c.json",
]
# Fight Club filenames are not always 5etools source IDs.
# Checked against 5etools data/bestiary/index.json.
SOURCE_ALIASES = {
    "MOSH": "SCC", "BOMT": "BMT", "TWBTW": "WBtW",
    "PABSO": "PaBTSO", "PAM": "MPP", "VER": "VEoR",
    "QIS": "QftIS", "KGV": "KftGV",
    "MC2DC": "MCV2DC", "MC1SC": "MCV1SC", "MC4EC": "MCV4EC",
    "MMV1": "MisMV1", "VRGTR": "VRGR",
}
SECTIONS = {"trait", "action", "bonus", "reaction", "legendary", "mythic"}


def convert_recharge(raw: str) -> dict:
    """Only machine-readable counts/cooldowns; unknown codes fail closed."""
    value = raw.strip().upper()
    die = re.fullmatch(r"D([2-6])", value)
    if die:
        return {"max": 1, "recharge": "d6", "recharge_min": int(die[1])}
    periodic = re.fullmatch(r"([1-9][0-9]?)\/(DAY|TURN)", value)
    if periodic:
        return {
            "max": int(periodic[1]),
            "recharge": "long_rest" if periodic[2] == "DAY" else "turn",
        }
    if value in ("SHORT", "LONG"):
        return {"max": 1, "recharge": "short_rest" if value == "SHORT" else "long_rest"}
    return {}


def parse_bestiary(path: Path, source: str) -> list[dict]:
    result: list[dict] = []
    root = ET.parse(path).getroot()
    for monster in root.findall("monster"):
        name = (monster.findtext("name") or "").strip()
        if not name:
            continue
        resources: list[dict] = []
        seen: set[tuple[str, str]] = set()
        for section in monster:
            if section.tag not in SECTIONS:
                continue
            feature_name = (section.findtext("name") or "").strip()
            usage = convert_recharge(section.findtext("recharge") or "")
            identity = (section.tag, feature_name.casefold())
            if not feature_name or not usage or identity in seen:
                continue
            seen.add(identity)
            resource = {"section": section.tag, "name": feature_name, **usage}
            if (section.tag == "legendary" and usage["recharge"] == "turn"
                    and re.fullmatch(r"Legendary Actions \([0-9]+/Turn\)", feature_name, re.I)):
                resource["legendary_pool"] = True
            resources.append(resource)
        if resources:
            result.append({"source": source, "name": name, "resources": resources})
    return sorted(result, key=lambda row: (row["source"], row["name"].casefold()))


def regenerate(checkout: Path, *, check: bool = False) -> int:
    total = 0
    for target in OUTPUTS:
        original = json.loads(target.read_text(encoding="utf-8"))
        rows: list[dict] = []
        for relative in original["source_files"]:
            path = checkout / relative
            if not path.is_file():
                raise FileNotFoundError(path)
            match = re.fullmatch(r"bestiary-([a-z0-9]+)\.xml", path.name, re.I)
            if not match:
                raise ValueError(f"Unexpected source file: {path}")
            source_id = SOURCE_ALIASES.get(match[1].upper(), match[1].upper()).upper()
            rows.extend(parse_bestiary(path, source_id))
        unique: dict[tuple[str, str], dict] = {}
        for row in rows:
            identity = (row["source"], row["name"].casefold())
            if identity in unique:
                raise ValueError(f"Duplicate source-qualified monster: {identity}")
            unique[identity] = row
        document = {
            "schema_version": 1,
            "origin_repository": original["origin_repository"],
            "edition": "2014",
            "source_files": original["source_files"],
            "monsters": sorted(rows, key=lambda r: (r["source"], r["name"].casefold())),
        }
        data = json.dumps(document, ensure_ascii=False, indent=2) + "\n"
        if check:
            # Compare semantics, not JSON whitespace or historical ordering.
            if sorted(original["monsters"], key=lambda r: (r["source"], r["name"].casefold())) != document["monsters"]:
                raise ValueError(f"Fight Club monster supplement is stale: {target}")
        else:
            target.write_text(data, encoding="utf-8")
        total += len(rows)
    print(f"PASS: {total} Fight Club monster records across {len(OUTPUTS)} supplements")
    return total


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] != "--check"):
        raise SystemExit(__doc__)
    regenerate(Path(sys.argv[1]), check="--check" in sys.argv)
