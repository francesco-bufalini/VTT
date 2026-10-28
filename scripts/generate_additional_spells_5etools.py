#!/usr/bin/env python3
"""Bundle structured 5etools additionalSpells from a LOCAL 5etools-src checkout.

Usage: python scripts/generate_additional_spells_5etools.py /path/to/5etools-src
       python scripts/generate_additional_spells_5etools.py --ownership-only
       python scripts/generate_additional_spells_5etools.py --feats-only /path/to/5etools-src

Keeps original structured innate/known/prepared/expanded usage schemas.
Never parses English prose, invents spell picks, or downloads at runtime.
Unknown schema values are preserved for future compatibility, not guessed.
"""
from __future__ import annotations

import json
import sys
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "vtt/data/additional_spells_5etools.json"
OWNERSHIP = ROOT / "vtt/data/additional_spell_ownership.json"
COMPENDIUM = ROOT / "vtt/data/compendium_features_5etools.json"
FEAT_RULES = ROOT / "scripts/data/feat_spell_grants_2014.json"
SOURCES = {
    "data/feats.json": ["feat"],
    "data/races.json": ["race", "subrace"],
    "data/backgrounds.json": ["background"],
    "data/optionalfeatures.json": ["optionalfeature"],
}


def apply_ownership(entries: list, overrides: list) -> None:
    for row in entries:
        for patch in overrides:
            if (row["kind"], row["name"], row.get("source", "")) != (patch["kind"], patch["name"], patch.get("source", "")):
                continue
            if isinstance(patch.get("spell_traits"), dict):
                row.setdefault("spell_traits", {}).update(deepcopy(patch["spell_traits"]))
            for index, fields in patch.get("block_overrides", {}).items():
                i = int(index)
                if 0 <= i < len(row["blocks"]) and isinstance(fields, dict):
                    row["blocks"][i].update(deepcopy(fields))
            # Reviewed typed corrections may replace an upstream block whose
            # schema misrepresents the actual choice/ritual semantics.
            row.update(deepcopy(patch.get("entry_overrides", {})))


def ownership_rules() -> list:
    result = json.loads(OWNERSHIP.read_text(encoding="utf-8")).get("entries", [])
    if FEAT_RULES.exists():
        result += json.loads(FEAT_RULES.read_text(encoding="utf-8")).get("entries", [])
    return result


def normalize_feat_sections(compendium: dict, overrides: list) -> None:
    # Named lists are already structured source data. Reuse the existing
    # build-time extractor instead of parsing descriptions in the browser.
    try:
        from .generate_charcreation_options import feature_sections
    except ImportError:
        from generate_charcreation_options import feature_sections
    for rule in overrides:
        if rule.get("kind") != "feat" or not rule.get("normalize_feature_sections"):
            continue
        key = rule["name"].lower() + "|" + rule["source"].lower()
        entry = compendium.get("feats", {}).get(key)
        if not entry:
            raise ValueError(f"Missing feat description: {key}")
        sections = feature_sections(entry.get("entries", []))
        if not set(rule.get("spell_traits", {}).values()).issubset({row["name"] for row in sections}):
            raise ValueError(f"Missing granting feat section: {key}")
        entry["feature_sections"] = sections


def gather(checkout: Path) -> dict:
    entries = []
    for relative, kinds in SOURCES.items():
        path = checkout / relative
        data = json.loads(path.read_text(encoding="utf-8"))
        for kind in kinds:
            for item in data.get(kind, []):
                blocks = item.get("additionalSpells")
                if not isinstance(blocks, list) or not blocks:
                    continue
                if kind == "subrace" and any(
                    "additionalSpells" in version and version["additionalSpells"] is None
                    for version in item.get("_versions", [])
                ):
                    # The spell package is one selectable version, not a
                    # grant from the unspecialized subrace itself.
                    continue
                row = {
                    "kind": kind,
                    "name": item["name"],
                    "source": item.get("source", ""),
                    "blocks": blocks,
                }
                if kind == "subrace":
                    row["race_name"] = item.get("raceName", "")
                    row["race_source"] = item.get("raceSource", "")
                entries.append(row)
    # Typed links and audited source corrections are maintained separately
    # from the upstream 5eTools export; regeneration must not erase them.
    if OWNERSHIP.exists():
        overrides = ownership_rules()
        apply_ownership(entries, overrides)
    return {
        "meta": {
            "source": "5etools-mirror-3/5etools-src",
            "source_fields": "additionalSpells (structured only)",
            "origin": "; ".join(SOURCES.keys()),
            "edition": "mixed PHB / XPHB",
            "build_only": True,
            "notes": "The game normalizes innate, known cantrips and limited prepared spells. Expanded spell lists are not consumable grants. Choice entries require explicit user selection.",
        },
        "entries": entries,
    }


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    if sys.argv[1] == "--feats-only" and len(sys.argv) == 3:
        result = json.loads(OUTPUT.read_text(encoding="utf-8"))
        source = json.loads((Path(sys.argv[2]) / "data/feats.json").read_text(encoding="utf-8"))
        feats = {(item["name"], item["source"]): {"kind": "feat", "name": item["name"],
                 "source": item["source"], "blocks": item["additionalSpells"]}
                 for item in source["feat"] if item.get("additionalSpells")}
        result["entries"] = [feats.pop((row["name"], row["source"]), row) if row["kind"] == "feat" else row
                             for row in result["entries"]] + list(feats.values())
    else:
        result = json.loads(OUTPUT.read_text(encoding="utf-8")) if sys.argv[1] == "--ownership-only" else gather(Path(sys.argv[1]))
    overrides = ownership_rules()
    apply_ownership(result["entries"], overrides)
    compendium = json.loads(COMPENDIUM.read_text(encoding="utf-8"))
    normalize_feat_sections(compendium, overrides)
    OUTPUT.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    COMPENDIUM.write_text(json.dumps(compendium, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Bundled {len(result['entries'])} sources with structured additionalSpells")
