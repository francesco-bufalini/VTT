"""Offline validation of Fight Club monster recharge conversion; no HTTP required."""
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "scripts" / "generate_fightclub_monster_resources.py"
spec = importlib.util.spec_from_file_location("fightclub_monsters", path)
assert spec and spec.loader
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)


class FightClubMonsterResourceTests(unittest.TestCase):
    def test_only_literal_known_recharge_fields(self):
        self.assertEqual(converter.convert_recharge("D5"),
                         {"max": 1, "recharge": "d6", "recharge_min": 5})
        self.assertEqual(converter.convert_recharge("3/DAY"),
                         {"max": 3, "recharge": "long_rest"})
        self.assertEqual(converter.convert_recharge("2/TURN"),
                         {"max": 2, "recharge": "turn"})
        self.assertEqual(converter.convert_recharge("SHORT"),
                         {"max": 1, "recharge": "short_rest"})
        self.assertEqual(converter.convert_recharge("LONG"),
                         {"max": 1, "recharge": "long_rest"})
        for unsupported in ("", "no limit", "Recharge 5-6", "%6", "D1", "3/WEEK",
                            "3/DAY plus 1", "2/REST", "at will"):
            self.assertEqual(converter.convert_recharge(unsupported), {},
                             f"Refuse unstructured or unsupported reset {unsupported!r}")

    def test_parse_does_not_invent_from_feature_text(self):
        xml = """<compendium>
        <monster>
          <name>Sample Fiend</name>
          <trait><name>Legendary Resistance (3/Day)</name>
            <recharge>3/DAY</recharge><text>Three uses</text></trait>
          <action><name>Breath (Recharge 5-6)</name><recharge>D5</recharge></action>
          <reaction><name>Ward (Recharges after a Short Rest)</name>
            <recharge>SHORT</recharge></reaction>
          <legendary><name>Legendary Actions (3/Turn)</name>
            <recharge>3/TURN</recharge></legendary>
          <action><name>Eye Ray (4/Day)</name><text>Four uses</text></action>
          <action><name>Arcane Burst</name><recharge>unlimited</recharge></action>
          <trait><name>Spellcasting</name><text>Three spell slots</text></trait>
          <slots>0,4,3</slots>
        </monster></compendium>"""
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "bestiary-abc.xml"
            file.write_text(xml, encoding="utf-8")
            rows = converter.parse_bestiary(file, "ABC")
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(rows[0]["resources"]), 4)
        self.assertEqual(rows[0]["resources"][-1]["legendary_pool"], True)
        self.assertNotIn("slots", rows[0], "Slots are intentionally outside this increment")

    def test_bundled_index_is_source_qualified_and_safe(self):
        total = 0
        all_sources: set[str] = set()
        for target in converter.OUTPUTS:
            data = json.loads(target.read_text(encoding="utf-8"))
            self.assertEqual(data["schema_version"], 1)
            self.assertEqual(data["edition"], "2014")
            self.assertEqual(data["origin_repository"], "vidalvanbergen/FightClub5eXML")
            self.assertEqual(len(data["source_files"]), len(set(data["source_files"])))
            identities: set[tuple[str, str]] = set()
            for row in data["monsters"]:
                key = (row["source"], row["name"].casefold())
                self.assertNotIn(key, identities)
                identities.add(key)
                self.assertTrue(row["resources"])
                all_sources.add(row["source"])
                for item in row["resources"]:
                    self.assertIn(item["section"], converter.SECTIONS)
                    self.assertGreater(item["max"], 0)
                    self.assertIn(item["recharge"], ("d6", "turn", "short_rest", "long_rest"))
                    if item["recharge"] == "d6":
                        self.assertIn(item["recharge_min"], range(2, 7))
            total += len(data["monsters"])
        self.assertGreaterEqual(len(all_sources), 20)
        self.assertGreaterEqual(total, 400)


if __name__ == "__main__":
    unittest.main()
