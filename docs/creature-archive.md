# Creature persistence: one device archive

Characters and monsters share the same device-local JSON file:

`user://creatures/creatures.json`

Its `creatures` array contains records with a stable `id` and a `kind` of
`character` or `monster`. Both types are visible in the creature sheet
archive regardless of the selected campaign or scenario. No campaign identifier
is part of the storage path. The character/monster factories and normalizers
remain distinct because their D&D defaults and legacy schemas differ.

`CreatureArchive` is the public API for listing, creating, editing, deleting,
exporting and transferring sheets. `CreatureLocalStorage` is the single
read/write owner. The old character/monster store classes are adapters for
callers still using their existing methods, but they write the same JSON file.

## First-run migration and recovery

When the unified file does not exist, storage imports all `*.json` archives
found under `user://player_characters/` and `user://master_creatures/`,
including `default.json`, `campaign_*.json` and `scenario_*.json`.
It also reads `user://creatures/characters.json` and
`user://creatures/monsters.json` if left by the previous global-store
experiment. All scopes are merged; no campaign is favored.

Identical records with the same ID and kind are deduplicated. Distinct records
with the same ID survive with a deterministic migration suffix on the later
entry, including collisions between characters and monsters. References to colliding legacy IDs may require manual re-linking
to a board token. Records transferred to other owners are retained in storage,
but are not shown as locally owned.

The migration writes the new archive through a temporary file, and **never
deletes, rewrites or moves old archives**. If any legacy file is unreadable or
malformed, migration stops rather than silently creating a partial replacement.
The old files remain available for recovery. Once `creatures.json` exists,
those inputs are never merged again, including after a user deletes a sheet.
To recover from an archived backup, make a separate copy before changing
the unified file.

The unified archive also stores bounded `undo` and `redo` arrays of previous and next locally owned creature revisions. Repeated edits within 800 ms to the same sheet form one checkpoint. On desktop, Ctrl+Z and Ctrl+Y/Ctrl+Shift+Z restore these saved revisions in the creature editor; changes are written atomically with history. Deletion and ownership transfer invalidate prior revisions for that creature rather than restoring deleted or transferred sheets. PWA browser storage is a separate implementation.

Ownership and transfer revision protections remain in force for local saves,
deletes, exports/imports and ownership transfer. Private sheets never go into
automatic board snapshots.

## Scene-authored creatures

A scene creator can embed creature data directly in a `.tscn` (or its
referenced project resources) and opt into the archive's **read-only** scene
hook. On the scene root script:

```gdscript
@export var embedded_creatures: Array[Dictionary] = []

func get_embedded_creature_records() -> Array[Dictionary]:
    return embedded_creatures.duplicate(true)
```

The scene's own controller may call:

```gdscript
var records: Array[Dictionary] = creature_archive.scene_records_from(self)
```

Each record must have `kind: "monster"` or `kind: "character"`. The method
returns detached, normalized records marked `_storage_origin: "scene"`.
They are not saved to `user://`, not included in `list_owned()`, and
cannot accidentally be saved through `CreatureArchive.save()`. Updates to
these records belong to the scene author (scene/resource editing). No player
browse/display or remote distribution is implemented for scene-embedded
creatures. The scene may decide independently how to use the returned records.

## Tests

Use `tests/test_global_creature_archive.gd` for first-run migration,
duplicate IDs, deletion without re-import, campaign independence, ownership
revisions, corruption protection and the scene hook. Integration tests use
isolated `user://tests/...` paths to avoid mutating real user archives.
