#!/usr/bin/env python3
"""Focused regression tests for source-aware background benefit migration."""
import json
import tempfile
import unittest
from pathlib import Path

from audit_background_benefits import inspect, load_benefits


class BackgroundBenefitMigrationTests(unittest.TestCase):
    def setUp(self):
        self.source = {
            "name": "Acolyte", "source": "XPHB",
            "skillProficiencies": [{"insight": True, "religion": True}],
            "toolProficiencies": [{"calligrapher's supplies": True}],
            "feats": [{"magic initiate; cleric|xphb": True}],
            "ability": [{"choose": {"weighted": {
                "from": ["int", "wis", "cha"], "weights": [2, 1]}}}],
        }
        self.comp = [{"name": "Acolyte", "source": "XPHB"}]

    def test_compiled_source_fields_never_become_supplements(self):
        result = inspect(
            [self.source], self.comp, self.comp, self.comp, {})
        self.assertEqual(result["summary"]["indexed_gaps"], 0)
        self.assertEqual(result["summary"]["supplemental_background_entries"], 0)
        self.assertEqual(result["summary"]["per_type_source_coverage"]["feat_grant"], 1)

    def test_missing_index_means_regenerate_not_copy_into_benefits(self):
        result = inspect([self.source], self.comp, [], [], {})
        self.assertEqual(result["summary"]["indexed_gaps"], 1)
        self.assertEqual(result["needs_5etools_index_refresh"][0]["missing_local_indexes"],
                         ["proficiency_index", "ability_index"])

    def test_inherited_copy_does_not_generate_false_grants(self):
        derived = {"name": "Baldur's Gate Acolyte", "source": "BGDIA",
                   "_copy": {"name": "Acolyte", "source": "PHB"}}
        result = inspect([derived], [derived], [], [], {})
        self.assertEqual(result["summary"]["indexed_gaps"], 0)

    def test_sources_are_edition_qualified(self):
        result = inspect([self.source], [{"name": "Acolyte", "source": "PHB"}],
                         [{"name": "Acolyte", "source": "PHB"}], [], {})
        self.assertEqual(result["summary"]["indexed_gaps"], 1)
        self.assertEqual(result["in_upstream_not_compendium"],
                         [{"name": "acolyte", "source": "xphb"}])

    def test_existing_overlapping_supplement_is_flagged_for_review(self):
        catalog = {
            "entries": [{
                "id": "example:background:acolyte",
                "granted_by": {"kind": "5etools",
                               "ref": {"category": "background",
                                       "name": "Acolyte", "source": "XPHB"}},
                "benefit": {"type": "proficiency"}
            }]
        }
        report = inspect([self.source], self.comp, [], [], {"proficiency": catalog})
        self.assertTrue(report["supplements_to_review"][0]["review_upstream_overlap"])

    def test_benefit_file_name_scope_and_grant_ids(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            target = folder / "roll_bonus.json"
            content = {"benefit_type": "roll_bonus", "scope": "catalog",
                       "entries": [{"id": "one"}, {"id": "two"}]}
            target.write_text(json.dumps(content), encoding="utf-8")
            self.assertEqual(len(load_benefits(folder)["roll_bonus"]["entries"]), 2)
            content["entries"][1]["id"] = "one"
            target.write_text(json.dumps(content), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                load_benefits(folder)
            content["entries"] = []
            content["scope"] = "character"
            target.write_text(json.dumps(content), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Invalid"):
                load_benefits(folder)


if __name__ == "__main__":
    unittest.main()
