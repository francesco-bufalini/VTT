import unittest

from scripts.generate_additional_spells_5etools import apply_ownership, normalize_feat_sections
from scripts.audit_feat_spells_2014 import audit


class AdditionalSpellOwnershipTest(unittest.TestCase):
    def test_inventory_rejects_an_unreviewed_grant_and_skips_new_edition_reprints(self):
        manifest = {"meta": {"sources": ["PHB", "TCE"], "feat_source_snapshot": "fixture"},
                    "entries": [{"name": "Reviewed", "source": "TCE"}]}
        rows = [{"name": "Reviewed", "source": "TCE", "additionalSpells": [{}], "reprintedAs": ["Reviewed|XPHB"]},
                {"name": "Ordinary", "source": "PHB"}]
        self.assertEqual(audit(rows, manifest)["spell_grant_feats"], 1)
        with self.assertRaisesRegex(ValueError, "missing"):
            audit(rows + [{"name": "Missing", "source": "PHB", "additionalSpells": [{}]}], manifest)

    def test_declared_feat_sections_are_normalized_from_named_source_items(self):
        rule = {"kind": "feat", "name": "Cartomancer", "source": "BMT",
                "spell_traits": {"prestidigitation": "Card Tricks"},
                "normalize_feature_sections": True}
        compendium = {"feats": {"cartomancer|bmt": {"entries": [
            {"type": "list", "items": [{"type": "item", "name": "Card Tricks", "entries": ["Cantrip"]},
                                      {"type": "item", "name": "Hidden Ace", "entries": ["Separate benefit"]}]}]}}}
        normalize_feat_sections(compendium, [rule])
        sections = compendium["feats"]["cartomancer|bmt"]["feature_sections"]
        self.assertEqual([row["name"] for row in sections], ["Card Tricks", "Hidden Ace"])
        self.assertEqual(sections[0]["entries"], ["Cantrip"])
        rule["spell_traits"]["prestidigitation"] = "Missing"
        with self.assertRaisesRegex(ValueError, "Missing granting feat section"):
            normalize_feat_sections(compendium, [rule])

    def test_ownership_overrides_do_not_affect_another_source(self):
        entries = [{"kind": "feat", "name": "Cartomancer", "source": source,
                    "blocks": [{"known": {"_": ["prestidigitation#c"]}}]} for source in ["BMT", "HB"]]
        apply_ownership(entries, [{"kind": "feat", "name": "Cartomancer", "source": "BMT",
            "spell_traits": {"prestidigitation": "Card Tricks"},
            "block_overrides": {"0": {"casting_ability_not_required": True}}}])
        self.assertEqual(entries[0]["spell_traits"], {"prestidigitation": "Card Tricks"})
        self.assertTrue(entries[0]["blocks"][0]["casting_ability_not_required"])
        self.assertNotIn("spell_traits", entries[1])
        self.assertNotIn("casting_ability_not_required", entries[1]["blocks"][0])


if __name__ == "__main__":
    unittest.main()
