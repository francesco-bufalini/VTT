# Automatically granted spells and feature actions

## Provenance and precedence

- **5etools** is authoritative for spells. The checked-in `additional_spells_5etools.json`
  is a verbatim-structure subset of `additionalSpells` extracted at build time
  from `data/feats.json`, `data/races.json` (race/subrace),
  `data/backgrounds.json`, and `data/optionalfeatures.json` in
  [5etools-src](https://github.com/5etools-mirror-3/5etools-src).
  The bundle currently contains 235 granting-source records (86 feats, 30 races,
  50 subraces, 15 backgrounds and 54 optional features).
- **Fight Club 5e** supplies supplemental *structured counters* through
  `class_resource_overrides.json`. This provides recharge/max details,
  not guaranteed spell IDs, valid targets, or effect types.
- Neither upstream source is accessed at runtime. Regenerate 5etools data with
  `python scripts/generate_additional_spells_5etools.py /path/to/5etools-src`;
  regenerate Fight Club counters using `generate_fightclub_resources.py`.
- Native character origins and VTT spell catalog identities are retained;
  external `%N` placeholders must be converted before runtime.

## Safe automatic interpretation

- Fixed `innate` spells may be used without regular spell slots; structured
  `daily` and `rest` counters become stable, separately saved resource trackers.
  A plain `innate` array is at will according to its structured declaration.
- Fixed `known` cantrips are available without a spell slot.
- `prepared` spell entries with explicitly limited `daily` or `rest`
  usages are also offered through their separate trackers.
- Plain non-cantrip `known`/`prepared` lists and `expanded` lists are not
  *free spell casting grants*. They remain the province of the ordinary spellbook.
- A structured `choose` entry generates a user-visible pending selection
  with a filter, optional use counter, and capacity; the VTT never picks a
  random spell or broadens an unknown filter silently.
- An item, feature, feat, race or subrace is never granted because its name
  merely appears in a spell's English description.

## Other active features

- Built-in homebrew ability templates (currently Bardic Inspiration and Wild
  Shape) declare their class, required structured feature, minimum level and
  tracker in spell-catalog metadata. The generic entitlement resolver matches
  this metadata against actual 5etools features and resource trackers.
- Fight Club counters and 5etools resource columns which *lack a typed spell
  or action-effect reference* are surfaced in Spellcasting as unlinked resources
  which the user can bind to a homebrew or catalog spell with a tracker.
  **No automatic spell or target/effect semantics are invented from a counter.**
- Choosing to bind an untyped active feature is explicit authoring, not a
  claim that Fight Club declared a spell or condition effect.

## Open coverage limitations

The upstream `additionalSpells` field does not describe every class ability,
technique, racial power or item's per-spell charge cost. Features such as
Channel Divinity options and martial maneuvers need separate typed effect
metadata or explicit homebrew authoring. Some complex 5etools `choose` filter
operators are deliberately not implemented; these choices remain visible but
must not broaden to unrestricted catalogs. Validate both PHB and XPHB rules
and source-level scaling in Godot before merging.
