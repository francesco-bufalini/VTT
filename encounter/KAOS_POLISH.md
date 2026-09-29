# Kaos visual corrections

## Edited sources
- hero_costume.gd: long hair fitted outside the head, temple locks, continuous chest-to-ankle drape, torso-only waist belt.
- sculpted_giant_visual.gd: removed obsolete male ornament rings.
- assets/makehuman/build_anatomy.py: broader upper body, articulated climbing leg, corrected eye object transforms.
- kaos_climb.gd: preserve vertical torso; conform contact limbs instead of flattening the whole body.
- assets/characters/source/build_chariot.py: slightly larger imported horse.
- encounter_ui.gd: compact controls; hide Kaos HP and regeneration text without changing combat calculations.
- ../dnd_base.gd: selected-token arrows take precedence over GUI navigation.
- tests/kaos_polish_test.gd: rendered front/head/side/climbing checks, focused GUI arrow routing, phase-two transition.

Regenerated anatomy, climbing and airborne GLB/Blender resources; climbing Airborne blend shape rebuilt with build_flight_shape.py. Regenerated pegasus_chariot.glb using the existing horse asset. No additional third-party resources downloaded.

## Verification
Godot import completed. Rendered test completed without runtime errors. Arrow input moved the selected vehicle while the damage field had focus, without modifying its value. Five advances completed the climb. Depleting the giant's 202 HP still spawned phase two with 200 HP and did not end the encounter.

Screenshots: C:/Users/fedeb/Documents/Codex/outputs/polish/

Hair and clothing remain procedural geometry, not simulated cloth or strand physics. Close-range sculpt quality remains below the illustration reference; these changes address fitting and silhouette rather than replacing the character with a fully authored production asset.
