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
9. Spell targeting lifecycle is coupled by design: preview hitboxes are geometry-driven (never a cached cumulative target list); cancel clears preview + red affected cells immediately; confirmed spell AoEs remain on the map with their geometry-driven red affected cells until the user left-clicks that specific area; leaving spell targeting returns mouse capture to the camera.

## Validation

### Mandatory mobile update gate (all chats and branches)

- Before committing, merging or pushing PWA changes, run `node scripts/check_pwa_assets.mjs` and the focused PWA tests. Do not bypass a failing asset check.
- Every new browser module and offline catalog must be served by `network/pwa_host.gd`, with the correct MIME type, and included in the offline shell in `pwa/sw.js`. Essential catalogs also belong in `REQUIRED_CATALOGS`. Verify transitive imports too.
- Enable the tracked Git hooks in each fresh clone: `git config core.hooksPath .githooks`. The pre-commit gate checks the staged snapshot, so unstaged fixes cannot hide broken commits. This clone is configured; linked worktrees share its Git configuration.
- The normal validation scripts also run this gate. For startup/cache/asset changes, run `node pwa/tests/offline_browser.mjs` as well.
- A running Godot PWA host retains its route table until restart. If routes changed, explicitly tell the user to restart the desktop VTT before retrying the phone; do not claim that the running host is fixed without checking it. Preserve phone IndexedDB and saved creatures.

Fast parse/import check:

    .\scripts\validate.ps1

or:

    bash scripts/validate.sh

Run the repository test scripts too:

    .\scripts\validate.ps1 -Tests

or:

    bash scripts/validate.sh --tests

A change is not considered verified merely because it parses. For gameplay changes, add or update a focused regression test where practical.

The fast suite includes `res://tests/test_spell_targeting_lifecycle.gd`, which protects spell cancel, camera-control restoration, held post-cast AoEs, and synchronized red-hitbox cleanup. Keep it lightweight and headless-safe.

## Large-file policy

The current hotspots are intentionally being reduced incrementally:

- vtt/spells/spell_system.gd
- measurement_tool.gd
- dnd_base.gd
- token.gd

Do not split these files mechanically. Extract a component only when it has a clear state owner, a narrow API, and can be validated independently.

## Blender / environment-art workflow

- Blender environment tooling lives under tools/blender_env/; editable project-specific source lives under blender/.
- Target Blender 5.2.x for reproducibility. Do not silently change the pinned major/minor version.
- Before modeling environment geometry from scratch, check the local VTT Asset Library and suitable approved providers. Prefer reuse/kitbash, then Geometry Nodes/extensions, then custom modeling.
- Treat distant unreachable scenery as visual environment art: optimize/merge/simplify it in Blender rather than reproducing it as many gameplay nodes in Godot.
- Keep gameplay collisions, triggers, tokens, spell logic and encounter state in Godot unless a task explicitly requires otherwise.
- Never commit .vtt_assets/, provider caches, credentials, paid asset libraries or bulk third-party downloads.
- Record source and license in a scene asset manifest when a direct-download external asset becomes a project dependency.
- Install Blender extensions only when they materially help the current task; prefer a small stable core and remove/disable unnecessary tools.
- Export game-ready GLB through tools/blender_env/blender_env.ps1 where practical. Keep editable Blender source separate from generated game exports.
