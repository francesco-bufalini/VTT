# Area dimensions and target sidebar — 2026-10-13

## Behavior

- Every 3D range wire sphere retains three radii: center to surface on X, Y and Z, using the same line primitive and material as the sphere.
- Sphere, cube, cone, cylinder, line and square AoE meshes retain dimensional center-to-surface segments.
- Cone lateral segments end at the actual surface at mid-height, rather than extending outside the cone.
- Ray colour, emission, shading and depth testing follow the parent figure.
- The existing spell-target HUD also displays manual areas and their creation preview.
- A collapsible, scrollable side panel lists each figure's colour, shape, dimensions and affected creature names.
- Lines list the creatures crossed by their volume, using the same cell-intersection rules as the red affected highlights.
- Lists update after movement, renaming, footprint changes and height changes.
- Fixed multi-point spell previews also have dimensional entries and separate instance colours.
- Repeated figures of one shape choose visibly separated colours where possible, then distinct RGB colours after the palette becomes crowded.
- Instance colours are serialized, restored unchanged and transferred with the existing AoE snapshot format. Legacy areas without explicit colours retain their original style when restored.
- Spell effect/VFX styles, geometry, damage, selection and ownership are unchanged.

## Verification

Godot 4.7.2 stable console executable:

- test_area_dimensions.gd — passed, including geometry endpoints, repeated shapes beyond the initial palette, data round-trip, manual creation, line intersections and fixed previews.
- test_spell_targeting_2d.gd — passed.
- test_spell_targeting_lifecycle.gd — passed.
- test_aoe_sync.gd — passed, including movable areas, large TCP snapshots and scene isolation.
- test_attack_range_geometry.gd — passed.
- test_feat_ability_choice_and_aoe_3d.gd — passed.
- Whole-project headless editor import — completed with exit code 0.
- Compatibility renderer capture — reviewed: 3D radii, contrasting sphere colours, dimensions and crossed-creature list are visible.

The new regression is included in scripts/validate.ps1. The general fast-suite attempt stopped at test_spellcasting_initial_resources.gd:45, on the assertion about the spell description scroll area. Creature-sheet files were being changed concurrently and were preserved; this AoE change does not claim a clean whole-suite run.

The colour allocation avoids generating the extended palette unless needed. 2D radii reuse point geometry without allocating a GPU mesh every frame. Sidebar rows are rebuilt only when geometry/token data changes, and target-list updates are suspended while it is collapsed.

The visual capture uses a lightweight test scene, not a live campaign.