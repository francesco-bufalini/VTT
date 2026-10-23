"""Offline checks for Fight Club-to-native-VTT counter formula conversion.

Run with: python -m unittest discover -s tests -p 'test_fightclub_resource_converter.py'
No network access or Godot executable is required.
"""
from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "scripts/generate_fightclub_resources.py"
spec = importlib.util.spec_from_file_location("fightclub_counter_generator", MODULE)
assert spec and spec.loader
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class FightClubResourceFormulaTests(unittest.TestCase):
    def test_translate_to_native_formula(self) -> None:
        for original, converted in {
            "%6": "cha_mod",
            "%5": "wis_mod",
            "1+%6": "1+cha_mod",
            "3": "3",
            "2 + %8": "2 + proficiency",
        }.items():
            with self.subTest(original=original):
                self.assertEqual(generator.to_vtt_formula(original), converted)

    def test_reject_unknown_or_unconverted_source_notation(self) -> None:
        for bad in ("%0", "%9", "%10", "1+%6+%0", "1d6", "max(1,%6)", "{@dice d6}"):
            with self.subTest(raw=bad):
                with self.assertRaises(ValueError):
                    generator.to_vtt_formula(bad)

    def test_bundled_resource_formulas_are_native(self) -> None:
        data = json.loads((ROOT / "vtt/data/class_resource_overrides.json").read_text(encoding="utf-8"))
        count = 0
        for group in data["classes"]:
            for resource in group["resources"]:
                for step in resource["steps"]:
                    maximum = str(step["value"])
                    self.assertNotIn("%", maximum, (group["class"], resource["name"]))
                    self.assertEqual(generator.to_vtt_formula(maximum), maximum.lower())
                    count += 1
        self.assertGreater(count, 0)

    def test_every_counter_names_a_source_qualified_5etools_trait(self) -> None:
        data = json.loads((ROOT / "vtt/data/class_resource_overrides.json").read_text(encoding="utf-8"))
        classes = json.loads((ROOT / "vtt/data/creature_references_5etools.json").read_text(encoding="utf-8"))["class_features"]
        subclasses = json.loads((ROOT / "vtt/data/subclass_features_5etools.json").read_text(encoding="utf-8"))["subclass_features"]

        def subclass_key(name: str) -> str:
            value = name.casefold()
            for prefix in ("school of ", "circle of ", "oath of ", "college of ", "the "):
                if value.startswith(prefix):
                    value = value[len(prefix):]
            for suffix in (" domain", " school"):
                if value.endswith(suffix):
                    value = value[:-len(suffix)]
            return value

        count = 0
        for group in data["classes"]:
            for resource in group["resources"]:
                origin = resource.get("origin_feature", resource["name"])
                subclass = resource.get("subclass", "")
                rows = subclasses if subclass else classes
                matches = [row for row in rows
                           if row.get("class_name") == group["class"]
                           and row.get("class_source", row.get("source")) == group["source"]
                           and row.get("name", "").casefold() == origin.casefold()
                           and (not subclass or subclass_key(row.get("subclass_name", "")) == subclass_key(subclass))]
                self.assertTrue(matches, (group["class"], group["source"], subclass, origin))
                count += 1
        self.assertGreaterEqual(count, 57)


if __name__ == "__main__":
    unittest.main()
