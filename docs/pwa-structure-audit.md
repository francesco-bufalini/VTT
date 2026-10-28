# PWA structure audit — 2026-10-28

The structural cleanup preserves portable record identities and the 2014 rules.
It keeps the current rule engine and UI owners rather than splitting `ui.js`
or introducing another manager.

## Changes

| Audit finding | Implementation |
| --- | --- |
| Two action generators | Removed the obsolete generator from `native_sheet.js`. Parity tests now exercise `action_economy.js`, with spells verified through its dedicated spell projection. |
| Two skill lists | `sheet_rules.js` owns `SKILLS`; the native sheet re-exports it and actions import it directly. |
| Two armor-model readers | UI selection calls `selectedTraitState()` in `trait_state_rules.js`, including legacy values, defaults and explicit deselection. |
| Class ability previews rebuild mechanics | `classFeatureDescriptors()` produces shared timing, cost, resource, source and state requirements. Actions filter available descriptors; Benefits retain unavailable owned operations. This also fixes preview timing/cost differences for revised Monk and Paladin abilities. |
| Flattened subrace speed fallback | The native generator emits 92 canonical subtype identities with their existing native speed. The PWA generator projects them onto independent subraces and removes duplicate flattened species from selection data. Calculation reads canonical subtype movement. |
| Specialized Barbarian action assembly | Thirty simple action/resource definitions now live in `feature_timing_recovery_rules.json` and use the generic contextual feature projector. Their IDs, labels, descriptions, costs and reset events are preserved. Conditional movement, animal choices, initiative and other specialized operations remain in `barbarian_2014.js`. |
| Repeated legacy conversion | `normalizeCreatureRecord()` handles proficiency choices and monster attack metadata at import/save/editor and public projection boundaries. Normalization is immutable and idempotent, including variants and shared proficiency-origin removals. |
| Tracked installed dependencies | Removed 1,829 `node_modules` files from Git tracking while keeping the local installation. Added `package-lock.json` for reproducible installation. |

## Compatibility

Legacy fields and unknown portable data remain in records. Normalization adds
canonical choices only under the previous migration conditions. An explicit
empty choice list with proficiency origins does not resurrect old grants.

Old saved flattened species retain their names and IDs. At the record boundary,
canonical subtype metadata supplies movement using the saved ID or the exact
source-qualified legacy alias. No trait/origin identifiers are renamed.

Untyped monster inputs still exist. Their narrow Multiattack converter remains
in the ingress normalizer; the feature/attack calculation consumes typed counts.
An explicit valid typed count wins, and ambiguous descriptions remain descriptive.
Removing this compatibility converter altogether would lose existing behavior.

Legacy general-benefit reads and spell-ID/progression conversion remain where
needed for native exports and old saves. D&D 2014 content is retained.

## Reproduction

Install development dependencies from the repository root:

```powershell
npm ci --prefix pwa
npm test --prefix pwa
npm run test:structure-browser --prefix pwa
npm run test:offline-browser --prefix pwa
```

The browser scripts launch an isolated, headless Chrome profile; they do not
open a player's archive. On Windows they default to the installed Chrome path
and accept `CHROME_PATH` for another installation.

Regenerate canonical subtype identities and only their browser projection:

```powershell
python scripts/generate_creature_references.py --offline --races-only
node pwa/tools/sync_native_catalogs.mjs --species-movement-only
```

`--races-only` preserves existing native races, classes and class features and
adds source-qualified canonical subtype metadata. It needs the ignored upstream
`races.json` cache; omit `--offline` to populate that cache. A regular full native
generation also produces canonical subraces. Generated catalogs are not edited
by hand. The browser generator fails explicitly if canonical native metadata
has not yet been generated.

The app-shell cache advances to v194 so runtime code and catalog changes are
installed together, while IndexedDB remains independent.

## Validation and limits

- The new unit regressions cover all 92 subtype identities and old/new movement,
  explicit proficiency removals, variants, imported Multiattack, shared class
  previews, all 30 contextual actions, stable IDs and disabled origins.
- Before removing the Barbarian action implementation, 120 old/new action and
  tracker comparisons passed, including disabled features and proficiency scaling.
- The dedicated real-browser test passes: old IndexedDB choice migration,
  cancellation without payment, confirmed payment, reopening with the same
  counter, disabled action removal and an inspectable disabled Benefits entry.
- The offline browser test passes installation, 502 fallback, airplane-mode
  editing and reconnection with saved edits intact.
- Full PWA unit run: **878 passed / 892**, with **14 failures in `ui.test.mjs`**
  that also failed before this refactor. The initial run had 15 failures;
  the obsolete core parity check was updated to the current HP dialog and
  production action/spell projections.
- Godot 4.7.2 lightweight validation, spell targeting lifecycle and native
  race/subrace selection pass. The requested `validate.ps1 -Tests` run stops at
  `test_activated_abilities.gd:60`, which expects a dedicated `Capacità` heading;
  the run subsequently times out. It does not establish a complete suite pass.
- Broader browser scripts are not fully green: `action_dashboard_browser.mjs`
  stops on its secondary-attack requirement assertion, and
  `artificer_armor_browser.mjs` completes model switching and Defensive Field
  payment before failing on the Flash of Genius `Usa`/`Usato` label assertion.

Changes are local; no commit or publication was performed.
