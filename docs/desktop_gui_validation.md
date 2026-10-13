# Desktop GUI validation — 2026-10-13

The desktop changes are committed on main, based on origin/main at 56ea308.
Existing uncommitted mobile menu improvements were preserved, included and tested.

## Delivered behavior

- Creature options are divided into content/catalogues, creature/sharing and deletion.
- Options and creature context actions explain what they do in hover text.
- Map measurement commands distinguish distances and areas of effect.
- Token commands explain map deletion, creation, repositioning and temporary gravity.
- Camera settings explain movement speed and mouse rotation sensitivity.
- Menu audio settings explain that device preferences save immediately.
- Expanded traits provide navigation to origins, proficiencies, bonuses, resources and origin spells.
- New sheet captions and explanations support Italian and English.
- Attack empty-state text no longer becomes an unintended inner scrollable control.

## Verified

Godot 4.7.2 stable console executable was used.

- Whole-project headless editor import completed with exit code 0.
- Desktop navigation regression passed: trait buttons open their intended editor; option tooltips are populated.
- Sheet layout passed at 1200x720 and 800x600, including nested scroll isolation.
- Creature GUI localization passed.
- Existing responsive main menu regression passed at phone and desktop dimensions.
- Local compatibility audit passed: 48 JSON archive files and 99 records loaded with current normalizers.
- Archive schemas are character version 3 and creature version 2. Identity fields were preserved, and the audit did not rewrite archive files.
- Git fetch confirmed no remote commits missing from local main and no merge conflicts.

The 53 fast tests were checked in stages as inherited failures interrupted the standard fail-fast runner. After focused corrections and reruns, 49 passed and four remain failing. This is not a clean full-suite result. The exhaustive -FullTests suite was not run.

## Remaining validation failures

- tests/test_camera_2d_height.gd:467 — camera does not ascend past floating tokens when higher colliders exist.
- tests/test_creature_sheets.gd:150 — expected monster attack bonus differs from the computed result.
- tests/test_creature_reference_completion.gd:73-83 — bestiary completion HP base/bonus and explicit edits do not meet test expectations.
- tests/test_compendium_descriptions.gd:49 — test casts structured trait entries directly to String.

Camera gameplay and numeric rule computation were not changed in this GUI task. These failures require follow-up investigation before declaring the application fully validated.

Local archive schema compatibility does not establish that all gameplay calculations or all saved numeric values are correct. No live visual inspection of the full desktop application was performed.