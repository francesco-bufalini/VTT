# Shared creature-sheet controller

`vtt/creature_sheet_controller.gd` is the first UI-independent mutation boundary for mobile/desktop creature sheets. It has no Node, CanvasLayer, token or networking references.

## Contract

All static operations accept a **detached mutable Dictionary** and update it in place, preserving the established schema. UI layers remain responsible for:
- obtaining a copy via `CreatureArchive`;
- validating interaction/ownership, saving through the existing archive;
- refreshing the views and optionally updating the desktop's real token.

Currently migrated:
- conditions and concentration removal;
- layered HP damage (temporary HP, second form, base HP) and healing;
- tracker consumption, editor reconciliation and usage clamping;
- numeric/dice bonuses and derived mirrors;
- origin-granted spell/config edits.

No network client is enabled by the controller. `CreaturePublicStatus` is still the outbound privacy boundary; use only its projection for future mobile board messages.

## Not yet migrated

General form-to-record `_save()`, inventory, spells/cast targeting and passive sheet presentation still live in `CreatureArea`. Future mobile UI should call these shared controller methods instead of cloning their former implementations.

Tests: `tests/test_creature_sheet_controller.gd` plus existing creature/bonus/tracker/HP regressions.
