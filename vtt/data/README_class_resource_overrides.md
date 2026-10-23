# Class resource supplements (build-time only)

The runtime reads `vtt/data/class_mechanics_5etools.json` for 5etools class-table
progressions and complements it with `vtt/data/class_resource_overrides.json`.
The latter is a curated snapshot of *counter metadata* taken from the public
FightClub5eXML compendium files, plus separately identified 2024 Bard,
Fighter, Paladin, Sorcerer and Wizard entries from the source-qualified
5etools class features.
The game never fetches Fight Club or other websites.

- `classes[].resources[].steps`: when a counter becomes available or changes
  its maximum/recharge. A later step **updates** the same resource, not a new
  tracker. Each optional `subclass` restricts it to that subclass.
- `value`: integer or **native VTT** arithmetic expression, for example
  `cha_mod`, `wis_mod` or `1 + cha_mod`. Maximum formulas are resolved
  through the same numeric-bonus engine already used elsewhere in the app.
  `minimum` can enforce rules such as Bardic Inspiration's one-use minimum.
  Fight Club placeholders are **not accepted at runtime**.
- `reset`: `manual`, `turn`, `short_rest`, or `long_rest`. The recovery
  helper restores resources at short/long rest and ignores manual ones; partial
  short-rest recovery (some 2024 features) needs richer metadata in the future.
- `column`: optional alias for a 5etools class-table label (e.g. Rage -> Rages).
  Native 5etools limits take precedence; supplement rest type fills the gap.
  Unlimited source progressions are never replaced by a finite fallback.
- IDs remain `class:<class>:<source>:<column>` so previously spent uses survive
  importing this supplement and class-level changes.

## Source / rebuild

Repository: https://github.com/vidalvanbergen/fightclub5exml

2014 source path in that repo:
`Sources/DND_5e/WizardsOfTheCoast/01_Core/01_Players_Handbook/`

To regenerate approved entries, use an **already downloaded, local** checkout:

```sh
python scripts/generate_fightclub_resources.py /path/to/fightclub5exml
```

The checked-in JSON is the allowlist. Inspect the output before committing.
The script does not fetch content or infer a resource from descriptive prose.
The 2024 Fighter entries (Action Surge and Indomitable), Paladin Lay on Hands,
Sorcerer Innate Sorcery and Wizard Arcane Recovery are reviewed against
`creature_references_5etools.json` and stay in this allowlist when the 2014
Fight Club generator runs. Lay on Hands has explicit class-level steps to
preserve its five-points-per-Paladin-level pool for multiclass characters.
The 2024 Second Wind class-table progression is already supplied by
`class_mechanics_5etools.json` and is not duplicated here.
Fight Club values (e.g. its `%6` token for CHA modifier) are translated to
VTT-native formulas (e.g. `cha_mod`) **by this Python script only**. An unknown
source placeholder causes an error instead of being stored. No source-specific
expression syntax is ever persisted in the app's supplemental data.
Spell slots, spells known, invocation capacities and Mystic Arcanum are excluded
because the VTT handles spellcasting and selections elsewhere. Questionable
entries are excluded or corrected (e.g. Indomitable's 2014 long-rest reset).
Subclasses are gated explicitly, including Natural Recovery (Land Druid).

For **future** structured Fight Club data about individual traits, the existing
`vtt/content_enrichment.gd` and `vtt/enrichment/package.schema.json` system
already supports `class_features`/ `subclass_features` overlays by catalog ID.
Keep that mechanism for trait-local additional fields. Ordered class-level
counter progression uses this dedicated index because it does not describe
one static catalog entry.
