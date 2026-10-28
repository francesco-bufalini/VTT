#!/usr/bin/env python3
"""Export trait-owned 2014 additionalSpells from a local 5etools checkout.

Usage: python scripts/generate_feature_spell_grants.py /path/to/5etools-src
Ownership is audited typed input; spell lists/progressions remain upstream data.
"""
from __future__ import annotations

from copy import deepcopy
import json
import hashlib
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
BINDINGS = ROOT / "scripts/data/feature_spell_ownership_2014.json"
OUTPUT = ROOT / "vtt/data/feature_spell_grants_2014.json"


def merge_choices(value):
    """Two identical one-spell picks are one explicit choice with count two."""
    if isinstance(value, dict):
        return {key: merge_choices(item) for key, item in value.items()}
    if not isinstance(value, list):
        return deepcopy(value)
    result = []
    for item in value:
        if isinstance(item, dict) and isinstance(item.get("choose"), str):
            previous = next((row for row in result if isinstance(row, dict)
                             and row.get("choose") == item["choose"]), None)
            if previous is not None:
                previous["count"] = previous.get("count", 1) + item.get("count", 1)
                continue
        result.append(merge_choices(item))
    return result


def gather(checkout: Path, bindings: list[dict] | None = None) -> dict:
    if bindings is None:
        bindings = json.loads(BINDINGS.read_text(encoding="utf-8"))["bindings"]
    entries = []
    for binding in bindings:
        name = binding["class_name"]
        data = json.loads((checkout / f"data/class/class-{name.lower()}.json").read_text(encoding="utf-8"))
        subclasses = [row for row in data["subclass"]
                      if row.get("classSource", "PHB") == binding["class_source"]
                      and binding["subclass"] in (row.get("shortName"), row["name"])
                      and row["source"] == binding["source"]]
        if len(subclasses) != 1:
            raise ValueError(f"Ambiguous/missing subclass: {binding}")
        subclass = subclasses[0]
        features = [row for row in data["subclassFeature"]
                    if row.get("classSource", "PHB") == binding["class_source"]
                    and row.get("subclassShortName") == subclass.get("shortName", subclass["name"])
                    and row.get("subclassSource") == binding["source"]]
        by_owner = {}
        for block in subclass.get("additionalSpells", []):
            for mode, default_owner in binding["owners"].items():
                for stage, values in block.get(mode, {}).items():
                    owner = binding.get("stage_owners", {}).get(mode, {}).get(stage, default_owner)
                    candidates = [row for row in features if row["name"] == owner]
                    if len(candidates) != 1:
                        raise ValueError(f"Ambiguous/missing owner {owner}: {binding}")
                    feature = candidates[0]
                    row = by_owner.setdefault(owner, {
                        "kind": "subclassFeature", "name": owner, "source": feature["source"],
                        "class_name": name, "class_source": binding["class_source"],
                        "subclass_name": subclass["name"], "subclass_short_name": subclass.get("shortName", subclass["name"]),
                        "subclass_source": subclass["source"], "level": feature["level"],
                        "blocks": [],
                    })
                    label = block.get("name", "")
                    # Unnamed alternatives (e.g. Arcane Archer) retain their
                    # original block position; never merge their spell picks.
                    index = subclass["additionalSpells"].index(block)
                    target = next((item for item in row["blocks"] if item["source_block"] == index), None)
                    if target is None:
                        target = {"source_block": index, **({"name": label} if label else {})}
                        row["blocks"].append(target)
                    target.setdefault(mode, {})[stage] = merge_choices(values)
                    if "ability" in block:
                        target["ability"] = deepcopy(block["ability"])
                    else:
                        parent = next((item for item in data.get("class", [])
                                       if item["source"] == binding["class_source"]), {})
                        ability = subclass.get("spellcastingAbility", parent.get("spellcastingAbility"))
                        if ability:
                            target["ability"] = ability
                    if binding.get("ability"):
                        target["ability"] = binding["ability"]
                    if binding.get("casting_ability_not_required"):
                        target["casting_ability_not_required"] = True
        for owner, overrides in binding.get("block_overrides", {}).items():
            if owner not in by_owner or len(by_owner[owner]["blocks"]) != 1:
                raise ValueError(f"Ambiguous block override: {owner}")
            by_owner[owner]["blocks"][0].update(deepcopy(overrides))
        for extra in binding.get("extra_grants", []):
            candidates = [row for row in features if row["name"] == extra["name"]]
            if len(candidates) != 1:
                raise ValueError(f"Ambiguous supplemental owner: {extra['name']}")
            feature = candidates[0]
            by_owner[extra["name"]] = {"kind": "subclassFeature", "name": feature["name"],
                "source": feature["source"], "class_name": name, "class_source": binding["class_source"],
                "subclass_name": subclass["name"], "subclass_short_name": subclass.get("shortName", subclass["name"]),
                "subclass_source": subclass["source"], "level": feature["level"], "blocks": deepcopy(extra["blocks"])}
        entries.extend(by_owner.values())
    upstream = sorted({f"data/class/class-{binding['class_name'].lower()}.json" for binding in bindings})
    return {"meta": {"edition": "2014", "source": "5etools-src v2.37.0 data/class/class-*.json",
                     "upstream_sha256": {path: hashlib.sha256((checkout / path).read_bytes()).hexdigest() for path in upstream},
                     "ownership": "scripts/data/feature_spell_ownership_2014.json",
                     "notes": "Latest printing within 2014 rules. Class-level gates and exact trait ownership; expanded lists are not automatic grants."},
            "entries": entries}


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    result = gather(Path(sys.argv[1]))
    OUTPUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Bundled {len(result['entries'])} trait-owned spell progressions")
