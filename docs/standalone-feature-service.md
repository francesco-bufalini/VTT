# Shared creature features and offline catalog mode

The 5etools/homebrew feature collector now lives in
`res://vtt/creature_features.gd` (`RefCounted`, no Node3D or UI).

- Desktop `CreatureTraitsTab.collect_features` keeps its existing API and
  delegates to the same cached service.
- `StructuredResourceTrackers` uses the service directly instead of
  preloading a VBoxContainer. Automatic trait-origin IDs stay unchanged.
- Standalone startup passes `allow_remote_catalog=false` into the existing
  compendium and creature editor. The desktop defaults to true unchanged.
- Manual/local cache and homebrew search still works without requesting HTTP.

This stage does not export an APK or duplicate creature rules. Responsive
touch layout and the optional board session are subsequent steps.

## Domain/UI boundary (October 2026)

`creature_features.gd` is the canonical **read-only trait projection**.
Domain services for bonuses, proficiency origins, item-derived grants, and
spell/feature entitlements must call this service rather than importing
`creature_traits_tab.gd`. The tab is now a presentation-only consumer of
the same projection. The proficiency service uses a deferred script load to
avoid an eager GDScript preload cycle: feature projection itself needs the
structured starting-proficiency descriptions.

Item ownership and item *effect activation* remain separate: owning an item
keeps its trait visible, while `creature_item_rules.gd:origin_active` owns
the equipment, active and attunement conditions for mechanical effects.
Weapon-hand-specific attack bonuses and item identity/deduplication are still
resolved separately by the numeric bonus engine.

Future refactors should preserve stable `feature:` / `item:` origin IDs,
independent occurrence keys for repeated level-up traits, and the distinction
between selected/manual grants and automatically derived structured grants.

## Canonical benefit requirements (October 2026)

`vtt/benefit_requirements.gd` is the read-only eligibility resolver used by
the existing feature, numeric bonus, origin-spell, class-resource and infusion
systems. It declares `requirements: {scope: "character", min_level: 5}` or
`requirements: {scope: "class", class_name: "Druid", class_source: "PHB",
min_level: 2}`. The optional `max_level` is an explicit upper bound, not
an implied replacement. Class thresholds do not use total multiclass level.

Old 5etools `min_level`, numbered innate/known/prepared spell stages, class
resource `steps[].level` and infusion `upgrade_level` are still accepted
through adapters. Slot stages like `s1` are NOT character-level thresholds.
Per-benefit `requirements` also work for nested item traits, manual resource
trackers, manual formula bonuses and manual origin spells. Missing metadata
does not invent requirements; legacy saves are left intact.

Resource counters use unmodified IDs/spent-use keys. Automatic class counters
are matched to traits by explicit `origin_feature_key` when present, then
by a unique name match WITHIN their class/edition/subclass. Ambiguous matches
fall back to a stable `tracker:auto:` identity, never an unrelated trait.
The engines that consume/spend resources, evaluate numeric formulas, grant
spells, and activate items remain intentionally independent.
