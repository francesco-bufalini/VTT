"""Variant subraces cannot inherit grants that one exclusive choice removes."""
import importlib.util
import json
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "proficiency_generator", ROOT / "scripts/generate_proficiency_grants.py")
assert spec and spec.loader
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)

spell_spec = importlib.util.spec_from_file_location(
    "additional_spell_generator", ROOT / "scripts/generate_additional_spells_5etools.py")
assert spell_spec and spell_spec.loader
spell_generator = importlib.util.module_from_spec(spell_spec)
spell_spec.loader.exec_module(spell_generator)


class VariantProficiencyTests(unittest.TestCase):
    def test_exclusive_half_elf_options_do_not_stack_parent_proficiencies(self) -> None:
        rows = generator.convert("subrace", [{
            "name": "Variant; Wood Elf Descent", "source": "SCAG",
            "raceName": "Half-Elf", "raceSource": "PHB",
            "skillProficiencies": [{"any": 2}],
            "weaponProficiencies": [{"longsword|phb": True}],
            "_versions": [
                {"name": "Skill Versatility", "weaponProficiencies": None},
                {"name": "Elf Weapon Training", "skillProficiencies": None},
            ],
        }])
        self.assertEqual(rows, [])

    def test_fixed_subrace_grant_is_preserved(self) -> None:
        rows = generator.convert("subrace", [{
            "name": "Mountain", "source": "PHB", "raceName": "Dwarf", "raceSource": "PHB",
            "armorProficiencies": [{"light": True, "medium": True}],
        }])
        self.assertEqual(rows[0]["armorProficiencies"], [{"light": True, "medium": True}])

    def test_browser_keeps_variant_identity_without_unselected_grants(self) -> None:
        browser = json.loads((ROOT / "pwa/catalog/proficiency_grants.json").read_text(encoding="utf-8"))
        mechanics = json.loads((ROOT / "pwa/catalog/class_mechanics.json").read_text(encoding="utf-8"))
        variants = {"Variant; Drow Descent", "Variant; Moon Elf or Sun Elf Descent",
                    "Variant; Wood Elf Descent"}
        self.assertFalse(any(row.get("raceName") == "Half-Elf" and row.get("source") == "SCAG"
                             and row["name"] in variants for row in browser["subrace"]))
        selectable = {row["name"] for row in mechanics["subraces"]
                      if row.get("raceName") == "Half-Elf" and row.get("source") == "SCAG"}
        self.assertTrue(variants.issubset(selectable))

    def test_exclusive_spell_option_is_not_an_unconditional_grant(self) -> None:
        races = {"subrace": [
            {"name": "Drow Descent", "source": "SCAG", "raceName": "Half-Elf",
             "raceSource": "PHB", "additionalSpells": [{"known": {"1": ["dancing lights#c"]}}],
             "_versions": [{"name": "Drow Magic"},
                           {"name": "Skill Versatility", "additionalSpells": None}]},
            {"name": "Devil's Tongue", "source": "SCAG", "raceName": "Tiefling",
             "raceSource": "PHB", "additionalSpells": [{"known": {"1": ["vicious mockery#c"]}}]},
        ]}
        with patch.object(spell_generator, "SOURCES", {"data/races.json": ["subrace"]}), \
             patch.object(Path, "read_text", return_value=json.dumps(races)):
            rows = spell_generator.gather(ROOT)["entries"]
        self.assertEqual([row["name"] for row in rows], ["Devil's Tongue"])


if __name__ == "__main__":
    unittest.main()
