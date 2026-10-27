"""Source-qualified feature grants and reviewed fallback normalization."""
import importlib.util
import json
import unittest
from unittest.mock import patch
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("proficiency_generator", ROOT / "scripts/generate_proficiency_grants.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class FeatureProficiencyTests(unittest.TestCase):
    def feature(self, **overrides):
        return {"name": "Training", "source": "TCE", "className": "Artificer", "classSource": "TCE", "level": 3, **overrides}

    def test_class_features_preserve_typed_choices_and_existing_ids(self):
        raw = self.feature(skillProficiencies=[{"choose": {"from": ["arcana", "history"], "count": 1}}])
        row = generator.convert_features("classFeature", [raw], [])[0]
        self.assertEqual(row["id"], "5etools:class_features:tce:training:artificer:3")
        self.assertEqual(row["class_source"], "TCE")
        self.assertEqual(row["skillProficiencies"], raw["skillProficiencies"])
        self.assertEqual(row["level"], 3)

    def test_same_name_and_book_do_not_merge_different_parent_classes(self):
        a = self.feature(languageProficiencies=[{"druidic": True}])
        b = self.feature(classSource="EFA", languageProficiencies=[{"draconic": True}])
        rows = generator.convert_features("classFeature", [a, b], [])
        self.assertEqual(len(rows), 2)
        self.assertEqual({row["class_source"] for row in rows}, {"TCE", "EFA"})

    def test_subclass_features_keep_parent_source_and_level_identity(self):
        raw = self.feature(subclassShortName="Armorer", subclassSource="TCE", armorProficiencies=[{"heavy": True}])
        row = generator.convert_features("subclassFeature", [raw], [])[0]
        self.assertEqual(row["id"], "5etools:subclass_features:artificer%7Ctce%7Carmorer%7Ctce%7C3%7Ctce%7Ctraining")
        self.assertEqual(row["subclass_source"], "TCE")
        self.assertEqual(row["armorProficiencies"], [{"heavy": True}])

    def test_reviewed_supplements_fill_missing_fields_without_overriding_upstream(self):
        raw = self.feature(toolProficiencies=[{"tinker's tools": True}])
        rule = self.feature(kind="classFeature", toolProficiencies=[{"smith's tools": True}], armorProficiencies=[{"heavy": True}])
        row = generator.convert_features("classFeature", [raw], [rule])[0]
        self.assertEqual(row["toolProficiencies"], raw["toolProficiencies"])
        self.assertEqual(row["armorProficiencies"], [{"heavy": True}])
        self.assertNotIn("armorProficiencies", raw)
        self.assertEqual(generator.convert_features("classFeature", [], [rule]), [])

    def test_prose_and_incomplete_identities_never_create_grants(self):
        prose = self.feature(entries=["You gain proficiency with heavy armor."])
        self.assertEqual(generator.convert_features("classFeature", [prose], []), [])
        raw = self.feature(classSource="", armorProficiencies=[{"heavy": True}])
        self.assertEqual(generator.convert_features("classFeature", [raw], []), [])
        self.assertEqual(generator.convert_features("subclassFeature", [self.feature(armorProficiencies=[{"heavy": True}])], []), [])

    def test_generator_collects_both_feature_groups_from_class_files(self):
        base = self.feature(languageProficiencies=[{"draconic": True}])
        sub = self.feature(subclassShortName="Armorer", subclassSource="TCE", armorProficiencies=[{"heavy": True}])
        files = {
            "package.json": {"version": "fixture"}, "index.json": {"artificer": "class-artificer.json"},
            "class-artificer.json": {"classFeature": [base], "subclassFeature": [sub]},
            "races.json": {}, "backgrounds.json": {}, "feats.json": {},
            "feature_proficiency_grants.json": {"entries": []},
            "proficiency_feature_ownership.json": {"entries": []},
        }
        with patch("sys.argv", ["generate_proficiency_grants.py", "fixture-root"]), \
             patch.object(generator, "read_json", side_effect=lambda path: files[path.name]), \
             patch.object(Path, "write_text") as write, \
             patch.object(generator, "generate_language_catalog", return_value=(Path("languages.json"), 0)):
            generator.main()
        output = json.loads(write.call_args.args[0])
        self.assertEqual(output["classFeature"][0]["languageProficiencies"], [{"draconic": True}])
        self.assertEqual(output["subclassFeature"][0]["armorProficiencies"], [{"heavy": True}])

    def test_catalog_features_match_the_shipped_trait_catalog_and_both_outputs(self):
        native = json.loads((ROOT / "vtt/data/proficiency_grants_5etools.json").read_text(encoding="utf-8"))
        browser = json.loads((ROOT / "pwa/catalog/proficiency_grants.json").read_text(encoding="utf-8"))
        traits = json.loads((ROOT / "pwa/catalog/classes.json").read_text(encoding="utf-8"))
        for group, field in [("classFeature", "class_features"), ("subclassFeature", "subclass_features")]:
            self.assertEqual(native[group], browser[group])
            for row in native[group]:
                self.assertTrue(any(trait["id"] == row["id"] and trait["class_source"] == row["class_source"] for trait in traits[field]), row["id"])


if __name__ == "__main__":
    unittest.main()
