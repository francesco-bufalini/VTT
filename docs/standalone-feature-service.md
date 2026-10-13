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
