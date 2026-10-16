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
