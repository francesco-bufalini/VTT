#!/usr/bin/env python3
"""Audit background grants before migrating *missing* mechanics to typed catalogs.

5eTools is the source of truth. A grant already represented by a structured
5eTools field is not a candidate for a VTT supplemental benefits JSON file.

Usage:
  python scripts/audit_background_benefits.py
  python scripts/audit_background_benefits.py --upstream /path/to/5etools-src/data/backgrounds.json
  python scripts/audit_background_benefits.py --upstream /path/to/backgrounds.json --output /tmp/background-audit.json

The first form checks the bundled indexes. The second reconciles those indexes
against the actual source fields. No generated or player data is modified.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENRICHMENT = ROOT / "vtt/enrichment/benefits"
STRUCTURED_FIELDS = {
    "proficiency": ("skillProficiencies", "toolProficiencies",
                    "weaponProficiencies", "armorProficiencies", "expertise"),
    "language": ("languageProficiencies",),
    "ability_score": ("ability",),
    "feat_grant": ("feats",),
    "spell_grant": ("additionalSpells",),
    "item_grant": ("startingEquipment",),
}


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def identity(record):
    return (str(record.get("name", "")).strip().casefold(),
            str(record.get("source", "")).strip().casefold())


def inspect(upstream, compendium, proficiency, ability, benefits):
    """Return source-qualified coverage; never treat an import gap as an override."""
    known = {identity(row) for row in compendium}
    prof = {identity(row) for row in proficiency}
    scores = {identity(row) for row in ability}
    upstream_by_key = {identity(row): row for row in upstream}
    local_only = sorted(known - upstream_by_key.keys())
    upstream_only = sorted(upstream_by_key.keys() - known)
    gaps = []
    source_counts = {benefit_type: 0 for benefit_type in STRUCTURED_FIELDS}
    existing_supplements = []

    for key, row in sorted(upstream_by_key.items()):
        if not all(key):
            continue
        fields = {benefit_type: [field for field in names
                                if field in row and row[field] is not None]
                  for benefit_type, names in STRUCTURED_FIELDS.items()}
        for benefit_type, present in fields.items():
            if present:
                source_counts[benefit_type] += 1

        # A 5eTools _copy or fromFeature record inherits mechanics: resolve it
        # upstream instead of treating its absent local fields as new grants.
        inherited = bool(row.get("_copy") or row.get("fromFeature"))
        absent = []
        if not inherited:
            if (fields["proficiency"] or fields["language"]) and key not in prof:
                absent.append("proficiency_index")
            if fields["ability_score"] and key not in scores:
                absent.append("ability_index")
        if absent:
            gaps.append({"name": row["name"], "source": row["source"],
                         "missing_local_indexes": absent,
                         "provided_by_5etools": sorted(
                             field for present in fields.values() for field in present)})

    for benefit_type, catalog in sorted(benefits.items()):
        for entry in catalog.get("entries", []):
            ref = (entry.get("granted_by") or {}).get("ref") or {}
            if ref.get("category") != "background":
                continue
            origin = identity(ref)
            raw = upstream_by_key.get(origin)
            upstream_fields = STRUCTURED_FIELDS.get(benefit_type, ())
            potential_overlap = bool(raw and any(raw.get(f) is not None
                                                 for f in upstream_fields))
            existing_supplements.append({
                "id": entry.get("id"),
                "type": benefit_type,
                "name": ref.get("name"), "source": ref.get("source"),
                "review_upstream_overlap": potential_overlap,
            })

    return {
        "summary": {
            "upstream_backgrounds": len(upstream_by_key),
            "local_compendium_backgrounds": len(known),
            "local_proficiency_origins": len(prof),
            "local_ability_origins": len(scores),
            "indexed_gaps": len(gaps),
            "per_type_source_coverage": source_counts,
            "supplemental_background_entries": len(existing_supplements),
        },
        "in_upstream_not_compendium": [
            {"name": name, "source": source} for name, source in upstream_only],
        "in_compendium_not_upstream": [
            {"name": name, "source": source} for name, source in local_only],
        "needs_5etools_index_refresh": gaps,
        "supplements_to_review": existing_supplements,
        "policy": ("Fix missing 5eTools imports in source adapters/generators. "
                   "Only truly absent mechanics belong in benefits/<type>.json; "
                   "never infer mechanics from descriptions or add player "
                   "overrides to shared catalogs."),
    }


def load_benefits(directory: Path):
    catalogs = {}
    for path in sorted(directory.glob("*.json")):
        data = read_json(path)
        if data.get("benefit_type") != path.stem or data.get("scope") != "catalog":
            raise ValueError(f"Invalid per-type catalog name/scope: {path}")
        ids = [entry.get("id") for entry in data.get("entries", [])]
        if len(ids) != len(set(ids)):
            raise ValueError(f"Duplicate benefit grant IDs: {path}")
        catalogs[path.stem] = data
    return catalogs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, help="Raw 5etools-src/data/backgrounds.json")
    parser.add_argument("--output", type=Path, help="Optional JSON audit output path")
    args = parser.parse_args()
    local = read_json(ROOT / "vtt/data/compendium_backgrounds_5etools.json")
    prof = read_json(ROOT / "vtt/data/proficiency_grants_5etools.json")
    ability = read_json(ROOT / "vtt/data/structured_ability_grants_5etools.json")
    compendium = list(local["backgrounds"].values())
    raw = read_json(args.upstream).get("background", []) if args.upstream else []
    report = inspect(raw, compendium, prof.get("background", []),
                     ability.get("background", []), load_benefits(ENRICHMENT))
    if not args.upstream:
        report["note"] = ("No upstream file supplied; index gaps cannot be "
                          "classified without comparing structured source data.")
        report["summary"]["upstream_backgrounds"] = None
        report["summary"]["indexed_gaps"] = None
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n",
                               encoding="utf-8")
    else:
        print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
