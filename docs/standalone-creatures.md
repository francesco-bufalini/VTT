# Standalone creature modularization (first slice)

This first stage is based on PR #85 (commit `a046a15763b7f7be66ec6b79c6e78fa4eb157e9d`).

## Available now

- `CreatureArea` and `Compendium` can be hosted by any Node with an explicitly supplied `CanvasLayer` rather than requiring `dnd_base.tscn`.
- `DiceRollerChat` accepts an explicit UI layer and an offline flag. With `enable_network=false` it does not start `DiceChatSync`, but retains local rolls and history.
- `vtt/standalone/creatures_standalone.tscn` is a non-3D proof-of-concept shell reusing the same creature editor, compendium and roller.
- The standalone shell permits creating creatures without choosing an installed 3D miniature.
- `CreaturePublicStatus` computes a redacted, token-ID-keyed tactical status separately from live token objects. The existing desktop health-bar exporter still requires a locally linked token.

## Compatibility

Existing desktop callers continue to use their unchanged one-argument `setup(self)` for creature sheet and compendium, and three-argument `setup(self, session_key, peer_provider)` for dice. All new arguments have defaults compatible with desktop.

## Next increments (not included)

1. Extract creature editor mutations into a reusable controller so a redesigned touch UI does not duplicate rules.
2. Replace direct calls to local token nodes with a desktop/mobile creature-to-token bridge.
3. Add an opt-in remote session using redacted status snapshots and revisioned commands; the current map V6 snapshot is **not** applied on mobile.
4. Define mobile app startup/autoload/resource export profiles; the standalone scene is currently a desktop-side verification shell, not an Android APK.
5. Adapt responsive layouts and add device-level Android testing.

## Checks

- Run `godot --headless --path . --script res://tests/test_standalone_creatures.gd`.
- Run the existing creature sheet, board sync, dice and PR #85 spell regression tests.
- Preview the standalone shell with `godot --path . res://vtt/standalone/creatures_standalone.tscn`.

No mobile networking or 3D map serialization is introduced in this slice.
