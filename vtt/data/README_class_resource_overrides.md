# Class resource supplements (build-time only)

The runtime reads `vtt/data/class_mechanics_5etools.json` for 5etools class-table
progressions and complements it with `vtt/data/class_resource_overrides.json`.
The latter is a curated snapshot of *counter metadata* taken from the public
FightClub5eXML compendium files, plus a separately identified 2024 Bard entry.
The game never fetches Fight Club or other websites.

- `classes[].resources[].steps`: when a counter becomes available or changes
  its maximum/recharge. A later step **updates** the same resource, not a new
  tracker. Each optional `subclass` restricts it to that subclass.
- `value`: integer, arithmetic formula, or Fight Club placeholders such as
  `%6` for the CHA modifier; formulas are resolved against the character's
  effective ability modifiers using the existing numeric-bonus engine.
  `minimum` can enforce rules such as Bardic Inspiration's one-use minimum.
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
