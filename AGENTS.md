# VTT agent guide

This file is the operational contract for automated changes in this repository.

## Before editing

- Never assume the target branch. Verify it first. Current campaign work normally lives on feature/campaign-hub.
- Read the smallest relevant files before editing; avoid broad rewrites of large scripts.
- Preserve user assets and encounter scenes unless the task explicitly asks to change them.
- Prefer behavior-preserving refactors before introducing new abstractions.

## Project baseline

- Engine: Godot 4.7.2 stable.
- Main scene: res://vtt/menu/main_menu.tscn.
- Runtime board scene: res://dnd_base.tscn.
- Core board orchestration: dnd_base.gd.
- Token behavior: token.gd.
- Measurement/AoE geometry: measurement_tool.gd.
- Spell workflow: vtt/spells/spell_system.gd.
- Initiative: vtt/initiative_tracker.gd.
- Board synchronization: network/board_sync.gd.
- Token dragging: interaction/token_drag.gd.

See docs/architecture.md for boundaries and refactor direction.

## Generated data

Do not hand-edit generated catalog output when a generator exists.

- vtt/spells/spell_catalog_5etools.gd is generated from 5etools data.
- Area parsing/generation lives in vtt/spells/parse_5etools_areas.py and vtt/spells/generate_5etools_catalog.py.
- outputs/spell_area_parser_report.json is generated output.

Change the generator or normalization layer, then regenerate.

## Change rules

1. Keep gameplay behavior unchanged unless the request explicitly changes it.
2. Prefer extracting/deduplicating existing behavior over adding parallel code paths.
3. Keep state identifiers stable. Token/initiative/network references must not depend on display names.
4. Keep serialization backward-compatible unless a migration is included.
5. Avoid dynamic property access when a typed method already exists.
6. Do not introduce a new manager/service when an existing subsystem already owns the responsibility.
7. Do not mix spell data ingestion with runtime spell mechanics.
8. Keep encounter-specific code under encounter/; reusable VTT behavior belongs outside it.

## Validation

Fast parse/import check:

    .\scripts\validate.ps1

or:

    bash scripts/validate.sh

Run the repository test scripts too:

    .\scripts\validate.ps1 -Tests

or:

    bash scripts/validate.sh --tests

A change is not considered verified merely because it parses. For gameplay changes, add or update a focused regression test where practical.

## Large-file policy

The current hotspots are intentionally being reduced incrementally:

- vtt/spells/spell_system.gd
- measurement_tool.gd
- dnd_base.gd
- token.gd

Do not split these files mechanically. Extract a component only when it has a clear state owner, a narrow API, and can be validated independently.
