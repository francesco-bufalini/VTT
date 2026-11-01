#!/usr/bin/env python3
"""Validate source-owned enrichment schemas, examples and the entire existing spell AoE catalog.

Requires jsonschema>=4.18. No runtime/gameplay migration is performed by this script.
"""
from __future__ import annotations

import json
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[1]
AUTHORING = ROOT / "vtt" / "enrichment" / "authoring"
EXAMPLES = AUTHORING / "examples"


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    schema_files = sorted(AUTHORING.glob("*.schema.json"))
    assert schema_files, "No authoring schemas found"
    registry = Registry().with_resources(
        (path.resolve().as_uri(), Resource.from_contents(read_json(path)))
        for path in schema_files
    )

    def validate(schema_name: str, instance, label: str) -> None:
        path = AUTHORING / schema_name
        validator = Draft202012Validator({"$ref": path.resolve().as_uri()}, registry=registry)
        errors = list(validator.iter_errors(instance))
        if errors:
            problem = errors[0]
            field = ".".join(str(part) for part in problem.absolute_path)
            raise AssertionError(f"{label} ({field or '<root>'}): {problem.message}")

    for path in schema_files:
        Draft202012Validator.check_schema(read_json(path))

    examples = sorted(EXAMPLES.rglob("*.json"))
    assert examples, "No origin authoring examples found"
    categories = set()
    for path in examples:
        example = read_json(path)
        category = example["category"]
        assert path.relative_to(EXAMPLES).parts[0] == category, path
        validate("origin.schema.json", example, str(path))
        validate(f"{category}.schema.json", example, str(path))
        categories.add(category)
    assert {"classes", "species", "feats", "items", "backgrounds", "spells", "subclasses"} <= categories

    geometry_catalog = read_json(ROOT / "assets" / "spell_area_geometry.json")
    assert len(geometry_catalog) >= 600, "Unexpectedly truncated legacy geometry catalog"
    for spell_key, geometry_spec in geometry_catalog.items():
        validate("spell_geometry.schema.json", geometry_spec, spell_key)

    # Important negative checks: strictly forbid invented mechanics types and misplaced categories.
    example = read_json(EXAMPLES / "classes" / "rogue.phb.json")
    invalid_category = {**example, "category": "feats"}
    try:
        validate("classes.schema.json", invalid_category, "wrong category")
    except AssertionError:
        pass
    else:
        raise AssertionError("Category schema accepted a wrong category")

    invalid_type = {
        "schema_version": 2,
        "category": "feats",
        "entries": [{"ref": {"name": "Test", "source": "HOMEBREW"}, "benefits": [{"type": "unknown_effect"}]}],
    }
    try:
        validate("feats.schema.json", invalid_type, "invalid benefit type")
    except AssertionError:
        pass
    else:
        raise AssertionError("Unknown benefit type was accepted")

    print(f"PASS: {len(schema_files)} authoring schemas, {len(examples)} origin examples, "
          f"{len(geometry_catalog)} spell geometries; negative validation checks passed")


if __name__ == "__main__":
    main()
