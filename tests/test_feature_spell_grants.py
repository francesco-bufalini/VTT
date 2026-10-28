import json
from pathlib import Path
import tempfile
import unittest

from scripts.generate_feature_spell_grants import gather


class FeatureSpellGrantsTest(unittest.TestCase):
    def fixture(self, root):
        directory = root / "data/class"
        directory.mkdir(parents=True)
        data = {"subclass": [{"name": "Arcana Domain", "shortName": "Arcana",
                "source": "SCAG", "classSource": "PHB", "additionalSpells": [{
                    "known": {"1": {"_": [{"choose": "level=0|class=Wizard", "count": 2}]}},
                    "prepared": {"1": ["magic missile"], "17": [{"choose": "level=6|class=Wizard"}]}}]}],
                "subclassFeature": [{"name": name, "source": "SCAG", "classSource": "PHB",
                    "subclassShortName": "Arcana", "subclassSource": "SCAG", "level": level}
                    for name, level in [("Arcana Domain", 1), ("Arcane Initiate", 1), ("Arcane Mastery", 17)]]}
        (directory / "class-cleric.json").write_text(json.dumps(data), encoding="utf-8")
        return [{"class_name": "Cleric", "class_source": "PHB", "subclass": "Arcana", "source": "SCAG",
                 "owners": {"known": "Arcane Initiate", "prepared": "Arcana Domain"},
                 "stage_owners": {"prepared": {"17": "Arcane Mastery"}}}]

    def test_choices_and_higher_level_owners_remain_separate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rows = gather(root, self.fixture(root))["entries"]
        by_name = {row["name"]: row for row in rows}
        self.assertEqual(by_name["Arcane Initiate"]["blocks"][0]["known"]["1"]["_"][0]["count"], 2)
        self.assertEqual(by_name["Arcane Mastery"]["level"], 17)
        self.assertNotIn("17", by_name["Arcana Domain"]["blocks"][0]["prepared"])

    def test_missing_owner_fails_instead_of_attaching_to_class(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bindings = self.fixture(root)
            bindings[0]["owners"]["known"] = "Missing"
            with self.assertRaisesRegex(ValueError, "missing owner"):
                gather(root, bindings)

    def test_bundled_data_uses_latest_legacy_printings(self):
        root = Path(__file__).resolve().parents[1]
        data = json.loads((root / "vtt/data/feature_spell_grants_2014.json").read_text(encoding="utf-8"))
        rows = data["entries"]
        self.assertGreaterEqual(len(rows), 58)
        self.assertTrue(all(row["class_source"] in ("PHB", "TCE") for row in rows))
        spores = next(row for row in rows if row["subclass_short_name"] == "Spores")
        self.assertEqual(spores["subclass_source"], "TCE")
        self.assertTrue(all(row["source"] != "XPHB" for row in rows))


if __name__ == "__main__":
    unittest.main()
