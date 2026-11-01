#!/usr/bin/env python3
"""Validate benefit-type authoring contracts, fixtures and legacy spell geometry."""
from __future__ import annotations

import json
from pathlib import Path
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[1]
SCHEMAS = ROOT / "vtt" / "enrichment" / "authoring"
EXAMPLES = SCHEMAS / "examples"
GENERIC = {"benefit.schema.json", "catalog.schema.json", "spell_geometry.schema.json"}


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    schema_paths = sorted(SCHEMAS.glob("*.schema.json"))
    registry = Registry().with_resources(
        (path.resolve().as_uri(), Resource.from_contents(load(path)))
        for path in schema_paths
    )
    for path in schema_paths:
        Draft202012Validator.check_schema(load(path))

    def check(schema_name, instance, label):
        path = (SCHEMAS / schema_name).resolve()
        validator = Draft202012Validator({"$ref": path.as_uri()}, registry=registry)
        problems = list(validator.iter_errors(instance))
        if problems:
            p = problems[0]
            location = ".".join(map(str, p.absolute_path)) or "<root>"
            raise AssertionError(f"{label} ({location}): {p.message}")

    def rejected(schema_name, instance, label):
        try:
            check(schema_name, instance, label)
        except AssertionError:
            return
        raise AssertionError(f"Rejected invalid example passed: {label}")

    types = load(SCHEMAS / "catalog.schema.json")["properties"]["benefit_type"]["enum"]
    assert len(set(types)) == len(types)
    assert "other" not in types, "Avoid bypassing type-based validation"
    schema_types = [p.stem.removesuffix(".schema") for p in schema_paths if p.name not in GENERIC]
    assert set(types) == set(schema_types), "One schema per benefit type is required"

    seen = set()
    for benefit_type in types:
        example = load(EXAMPLES / (benefit_type + ".json"))
        assert example["benefit_type"] == benefit_type
        assert example["scope"] == "catalog"
        ids = [row["id"] for row in example["entries"]]
        assert len(ids) == len(set(ids)), f"Duplicate grant IDs: {benefit_type}"
        check(benefit_type + ".schema.json", example, benefit_type)
        seen.add(benefit_type)
    assert len(seen) == len(types)

    manual = load(EXAMPLES / "roll_bonus.character.json")
    check("roll_bonus.schema.json", manual, "manually added trait benefit")
    assert manual["entries"][0]["granted_by"]["kind"] == "character_trait"
    assert manual["entries"][0]["granted_by"]["trait_key"]

    # Deliberately wrong origin and payload kinds must fail.
    example = load(EXAMPLES / "roll_bonus.json")
    rejected("proficiency.schema.json", example, "wrong benefit type")
    bad_source = dict(example["entries"][0])
    bad_source["granted_by"] = {
        "kind": "5etools",
        "ref": {"category": "class_feature", "name": "Only Name"},
    }
    rejected("roll_bonus.schema.json",
             {**example, "entries": [bad_source]},
             "5eTools entry without source")
    bad_scope = dict(example["entries"][0])
    bad_scope["granted_by"] = manual["entries"][0]["granted_by"]
    rejected("roll_bonus.schema.json",
             {**example, "entries": [bad_scope]},
             "manual grant placed in shared catalog")
    rejected("roll_bonus.schema.json", {**manual, "character_id": None},
             "missing character ID for manual grant")
    rejected("roll_bonus.schema.json", {**manual, "scope": "catalog"},
             "character-scoped grant placed in rulebook scope")

    # Authoritative per-type benefit catalogs are now consumed by the PWA.
    live = ROOT / "vtt" / "enrichment" / "benefits"
    for path in sorted(live.glob("*.json")):
        benefit_type = path.stem
        assert benefit_type in types, f"Unrecognized catalog type: {path}"
        data = load(path)
        assert data["benefit_type"] == benefit_type
        assert data["scope"] == "catalog"
        grant_ids = [entry["id"] for entry in data["entries"]]
        assert len(set(grant_ids)) == len(grant_ids), f"Duplicate grant ID: {path}"
        check(benefit_type + ".schema.json", data, path.name)

    legacy = load(SCHEMAS / "legacy_sources.json")
    for source in legacy["sources"]:
        original = ROOT / source["path"]
        assert original.exists(), original
        data = load(original)
        for section in source["sections"]:
            assert section in data, f"{original}: missing {section}"
        assert set(source["types"]) <= set(types), source

    geometries = load(ROOT / "assets" / "spell_area_geometry.json")
    assert len(geometries) >= 600, "Existing geometry catalog truncated"
    for ref, geometry in geometries.items():
        check("spell_geometry.schema.json", geometry, ref)

    print(f"PASS: {len(types)} typed catalogs/examples, one character override, "
          f"{len(schema_paths)} schemas, {len(legacy['sources'])} legacy source inventories, "
          f"{len(geometries)} spell geometries, and negative tests")


if __name__ == "__main__":
    main()
