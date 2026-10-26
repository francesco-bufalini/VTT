# Base-value override coverage (PWA)

The typed supplements in `vtt/data/base_value_overrides.json` are authoritative and projected to `pwa/catalog/ability_grants.json` through `pwa/tools/sync_native_catalogs.mjs`. These rules do **not** add ordinary bonus numbers: they select alternative formulas or replace the base damage die. Effects are source-qualified, reversible, and re-evaluated whenever equipment/level/origin changes.

## Implemented

| Source | Rule | Condition |
| --- | --- | --- |
| Barbarian PHB/XPHB — Unarmored Defense | AC `10 + dex_mod + con_mod` | No worn armor; shields allowed |
| Monk PHB/XPHB — Unarmored Defense | AC `10 + dex_mod + wis_mod` | No armor or shield |
| Bard XPHB (College of Dance) — Dazzling Footwork | AC `10 + dex_mod + cha_mod` | No armor or shield, subclass feature acquired |
| Sorcerer PHB/XPHB — Draconic Resilience | AC `13 + dex_mod` or `10 + dex_mod + cha_mod` | No armor |
| Lizardfolk VGM/MPMM | AC `13 + dex_mod` | May use over inferior worn armor |
| Loxodon GGR | AC `12 + con_mod` | May use over inferior worn armor |
| Locathah LR | AC `12 + dex_mod` | May use over inferior worn armor |
| Autognome AAG, Thri-kreen AAG | AC `13 + dex_mod` | No armor |
| Goblin PSZ | AC `11 + dex_mod` | No armor |
| Tortle TTP/MPMM | Base AC `17` | Worn armor provides no benefit; shield applies normally |
| Dragon Hide XGE | AC `13 + dex_mod` | No armor; shields allowed |
| Monk PHB — Martial Arts | Unarmed `1d4/1d6/1d8/1d10` at Monk levels 1/5/11/17 | No armor or shield |
| Monk XPHB — Martial Arts | Unarmed `1d6/1d8/1d10/1d12` at Monk levels 1/5/11/17 | No armor or shield |
| Unarmed Fighting TCE/XPHB | Unarmed `1d6`, or `1d8` without weapon or shield | Explicitly chosen style only |
| Tavern Brawler PHB | Unarmed `1d4` | Owned feat |
| Gauntlets/Belt/Amulet/Headband DMG | Minimum STR/CON/INT value | Active, attuned equipment |

All alternative unarmed dice are non-additive. Alternatives choose the highest mean base die where applicable; ordinary attack modifiers and additive bonuses remain separate.

The source **Lizardfolk DMG** says `+3 bonus to Armor Class`, not an alternative formula, and must not be silently mapped to a replacement.

## Unmodelled requirements or special states

- **Monk weapons:** Martial Arts also lets a Monk substitute the Martial Arts die for *eligible Monk weapons* and choose Dexterity for certain attacks. Applying this to item-based attacks requires a separate typed weapon eligibility and ability-choice mechanic; this change only models unarmed base damage.
- **Dazzling Footwork:** Dance Bard's alternate damage using the Bardic Inspiration die, and Dexterity-based unarmed attack ability, need a dice-scaling/ability-choice input linked to the tracker.
- **Circle of the Moon XPHB — Circle Forms:** Wild Shape's AC of `13 + wis_mod` if better than the Beast AC requires linking the formula to the *active creature form* rather than the base character's armor. Do not apply continuously.
- **Spells** such as Mage Armor and Barkskin require spell/state duration and concentration gating; no always-on bonus is applied.
- **Dragon Hide:** This pass adds the AC option; the retractable-claws alternate natural attack needs an attack choice with its own damage type.
- **Monk weapon eligibility:** The engine currently checks armor and shields for the unarmed Martial Arts die; weapon loadouts requiring the definition of Monk weapons (particularly customized monk weapons) remain a separate guardrail.

The tests cover disabled origins, equipped armor and shield interactions, source versions, and level breakpoints. Do not replace general source gating with hardcoded class-name checks in the main AC calculator.
