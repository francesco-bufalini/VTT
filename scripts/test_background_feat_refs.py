#!/usr/bin/env python3
"""Protect the 5eTools starting feat mirror against prose-based duplication."""
import copy
import unittest

from refresh_background_feat_refs import apply_refs


class BackgroundFeatRefsTests(unittest.TestCase):
    def test_only_explicit_structured_source_refs_are_applied(self):
        original = {"meta": {}, "backgrounds": {
            "acolyte|xphb": {"name": "Acolyte", "source": "XPHB", "entries": ["text"]},
            "acolyte|phb": {"name": "Acolyte", "source": "PHB", "entries": ["text"]},
        }}
        upstream = [
            {"name": "Acolyte", "source": "XPHB",
             "feats": [{"magic initiate; cleric|xphb": True}]},
            {"name": "Acolyte", "source": "PHB", "entries": ["Feat: Lucky"]},
        ]
        expected = copy.deepcopy(original)
        self.assertEqual(apply_refs(expected, upstream), 1)
        self.assertEqual(expected["backgrounds"]["acolyte|xphb"]["feats"],
                         [{"magic initiate; cleric|xphb": True}])
        self.assertNotIn("feats", expected["backgrounds"]["acolyte|phb"])
        self.assertEqual(expected["backgrounds"]["acolyte|xphb"]["entries"], ["text"])

    def test_removes_obsolete_generated_refs_but_preserves_other_fields(self):
        rows = {"meta": {}, "backgrounds": {"x|y": {
            "name": "X", "source": "Y", "feats": [{"old|y": True}],
            "fluff": ["unchanged"]}}}
        self.assertEqual(apply_refs(rows, [{"name": "X", "source": "Y"}]), 0)
        self.assertNotIn("feats", rows["backgrounds"]["x|y"])
        self.assertEqual(rows["backgrounds"]["x|y"]["fluff"], ["unchanged"])


if __name__ == "__main__":
    unittest.main()
