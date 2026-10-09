# VTT architecture

This document describes the current runtime boundaries and the direction for incremental cleanup. It is deliberately small so an agent can load it before touching gameplay code.

## Runtime flow

    UI / input
        |
        v
    dnd_base.gd  ------------------------------+
        |                                      |
        +--> token.gd                          |
        +--> interaction/token_drag.gd         |
        +--> measurement_tool.gd               |
        +--> vtt/spells/spell_system.gd        |
        +--> vtt/initiative_tracker.gd         |
        +--> vtt/token_list.gd                 |
        +--> network/board_sync.gd <-----------+

dnd_base.gd is currently the composition root. New reusable gameplay logic should not automatically be added there; use the subsystem that owns the state.

## Ownership

| Concern | Primary owner | Notes |
| --- | --- | --- |
| Board composition / cross-system wiring | dnd_base.gd | Keep orchestration here, move domain logic out over time. |
| Token appearance, size, conditions, reach, movement primitives | token.gd | Display name is not identity. |
| Drag interaction | interaction/token_drag.gd | Commits movement only after drag completion. |
| Measurement, AoE geometry, persistent AoEs | measurement_tool.gd | Geometry/rendering owner, not spell selection owner. |
| Spell selection and targeting workflow | vtt/spells/spell_system.gd | Consumes normalized spell metadata. |
| Spell catalog data | vtt/spells/spell_catalog*.gd | Generated 5etools output must not contain runtime UI logic. |
| Initiative | vtt/initiative_tracker.gd | Token links use stable IDs. |
| Synchronization / snapshots | network/board_sync.gd | Snapshot schema must preserve all gameplay state. |
| Campaign persistence | vtt/campaign_manager.gd | Campaign-level persistence, not live board interaction. |
| Encounter-specific mechanics | encounter/ | Must not leak into generic VTT code. |

## Important invariants

- Tokens remain horizontally grid-aligned even when not under gravity.
- Gravity is an explicit temporary action, not a permanent token mode.
- Undo/redo records completed user actions; token movement snapshots are committed after movement finishes.
- Initiative references tokens by stable ID, while displayed names may change.
- Network snapshots preserve token metadata, conditions, transformations, initiative and persistent board effects.
- Spell previews are transient. Persistent AoEs are serialized board state.
- Generated 5etools catalog files are data artifacts; runtime mechanics live outside generated output.

## Refactor direction

The long-term target is not more classes; it is clearer state ownership with less duplicated glue.

1. Shrink dnd_base.gd by moving self-contained domain behavior to existing subsystems.
2. Introduce a small explicit board/game-state model when tests can exercise it without rendering.
3. Make undo/redo operate on explicit commands or state deltas rather than arbitrary scene snapshots where practical.
4. Split spell_system.gd by targeting/mechanic only when each extracted unit has a narrow API.
5. Keep rendering/geometry in measurement_tool.gd; move spell-specific decisions out of it.
6. Centralize repeated token metadata access instead of duplicating dictionary/property fallbacks.

## Testing layers

Current tests under tests/ are headless Godot scripts. The validation scripts can run them one at a time.

Preferred future layers:

    pure state / serialization tests
            |
            v
    subsystem tests
            |
            v
    minimal board-scene integration tests
            |
            v
    full encounter smoke tests

A minimal test arena can be added once Godot execution is available in the agent sandbox. It should contain only geometry needed to reproduce generic VTT behavior, not campaign-specific content.

## Geometry-only helpers (2026-10-09)

- `vtt/aoe_snapshot_validator.gd` owns the pure validation rules for persistent AoE snapshots; `measurement_tool.gd.valid_aoes` remains the public API used by board synchronization and restores.
- `vtt/spells/spell_target_geometry.gd` owns fallback spell hit-testing, with cell size and upcast-adjusted sphere radius passed explicitly. SpellSystem retains its original private method as the calling adapter.
- `tests/test_geometry_refactor.gd` covers valid and invalid persistent AoEs, all six fallback shapes, empty directions, and expanded sphere radius.
- No snapshot version, serialized fields, scene paths, signals, or gameplay interaction APIs changed. The generated 5etools spell catalog remains untouched.

These are deliberately narrow extractions. Keep the board controller, spell-cast lifecycle, creature UI, and networking state machines together until they have reliable behavioral integration coverage.
