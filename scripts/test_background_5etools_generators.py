#!/usr/bin/env python3
"""Regression checks for 5eTools background-only regeneration paths."""
import unittest

from generate_proficiency_grants import convert
from generate_structured_ability_grants import fixed_ability


class BackgroundIndexGenerationTests(unittest.TestCase):
    def test_2024_background_source_kept_even_when_not_xphb(self):
        original = {
            "name": "Example Traveler", "source": "EFA", "edition": "one",
            "skillProficiencies": [{"history": True}],
            "toolProficiencies": [{"disguise kit": True}],
        }
        result = convert("background", [original])
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["source"], "EFA")
        self.assertEqual(result[0]["skillProficiencies"], [{"history": True}])

    def test_no_proficiency_is_invented_for_unresolved_copy(self):
        inherited = {"name": "Variant Noble", "source": "PHB",
                     "_copy": {"name": "Noble", "source": "PHB"}}
        self.assertEqual(convert("background", [inherited]), [])

    def test_edition_filter_still_applies_to_unrelated_sources(self):
        race = {"name": "A new species", "source": "EFA",
                "edition": "one", "skillProficiencies": [{"history": True}]}
        self.assertEqual(convert("race", [race]), [])

    def test_weighted_2024_background_has_no_automatic_fixed_score(self):
        raw = [
            {"choose": {"weighted": {"from": ["int", "wis", "cha"],
                                     "weights": [2, 1]}}},
            {"choose": {"weighted": {"from": ["int", "wis", "cha"],
                                     "weights": [1, 1, 1]}}},
        ]
        self.assertEqual(fixed_ability(raw), {})

    def test_fixed_scores_preserved_when_identical_across_options(self):
        self.assertEqual(fixed_ability([{"str": 2, "dex": 1},
                                        {"str": 2, "cha": 1}]), {"str": 2})


if __name__ == "__main__":
    unittest.main()
