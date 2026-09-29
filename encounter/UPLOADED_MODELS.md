# Uploaded models, Phenax and flight pose

## Scope and asset provenance

- Hanoverian_Horse_Jumping_V1: user-supplied OBJ, now used directly in all four winged-horse chariots. Original mesh retained under assets/characters/source/uploaded; game mesh decimated to 55 percent. Wings, harness and chariot are original project geometry.
- Greek_God_v1: user-supplied statue, with pedestal, integral robe, beard and a raised arm. This is NOT a neutral rigged body. Its exposed half-torso is sampled and mirrored to fit the existing male anatomy, with a smoothed bounded displacement field. Kaos giant, his Large avatar, the four male party skins and Phenax use this derived physique. Faces, legs, UVs and animation topology remain the existing MakeHuman-based anatomy. The full Greek God mesh has NOT replaced these characters one-for-one.
- Neither uploaded ZIP contains a usable texture or license document. Both JPG/MTL entries were empty. Replacement neutral MTL files only repair source import warnings. Verify the provider's distribution license before publishing these assets; they are not labelled CC0.
- Existing MakeHuman sources retain their previous CC0 attribution. Existing Poly Haven leather normal texture is reused for Phenax's cloth; no additional download was necessary. Source: https://polyhaven.com/a/leather_red_02 . The Poly Haven textiles library was checked during this update: https://polyhaven.com/textures/textiles-leather .
- Phenax mask, wing-shaped ornaments, cloth, arm metalwork and cosmic shader are project-authored, guided by the user-supplied illustration. This remains an intermediate game model, not a reproduction of the illustration's rendering quality.

## Runtime

- Six existing party tokens plus Phenax Large (2x2 footprint, three cells tall), on a dedicated fourth flying chariot. Its deck starts at the same 150 m altitude. Existing selection, movement, support and gravity APIs are reused.
- Existing three vehicles keep their two passengers. Chariot passengers follow deck translation and rotation, including repeated Shift+Up/Down. Walking off the deck detaches normally.
- Jump: one second charge, launch, upright airborne pose (arms/legs down, head tilted up), two-hand landing, one-hand settling. Flight uses a Blender-authored skeletal pose exported as a topology-matched morph, not a region-based arm deformation.
- Giant meshes are prepared during scene loading, avoiding first-use mesh preparation during the jump. HP, slowing, seals and round logic are unchanged.

## Principal files

Modified: kaos_climb.gd, kaos_controller.gd, encounter_scenery.gd, assets/makehuman/build_anatomy.py, assets/characters/source/build_party.py, source/build_chariot.py. The ongoing transport correction is in token.gd and encounter/chariot_token.gd.

Added: phenax_skin.gd, phenax_cosmic.gdshader, assets/makehuman/greek_physique.py, source/build_phenax.py, source/build_flight_shape.py, source/inspect_uploads.py, uploaded OBJ/MTL sources, tests/uploaded_models_test.gd, tests/grip_transport_test.gd.

Regenerated GLBs: kaos_anatomy, kaos_climbing, kaos_airborne, party_horned, party_ranger, party_sun_elf, party_hoplite, pegasus_chariot; new phenax.glb. Authoring .blend files are in the ignored source folder.

## Rebuild / focused checks

From the project directory, using Blender 5.0:

1. Run assets/makehuman/build_anatomy.py with -- --sex male; repeat with --climbing and --airborne.
2. Run assets/characters/source/build_flight_shape.py after BOTH pose builds. This preserves identical topology in the flight morph.
3. Run source/build_party.py with -- --male-only, source/build_phenax.py and source/build_chariot.py.
4. Reimport Godot resources, then open encounter/kaos_klothis.tscn and press F6.
5. Select a vehicle, Shift+Up/Down: passengers stay on its deck. Select Phenax to inspect the Large footprint.
6. Advance five undamaged rounds: check the full jump and the final separated faces. Apply 202 damage to the giant: the Large Kaos appears with 200 HP and the encounter continues.

Automated focused scripts: res://encounter/tests/uploaded_models_test.gd and res://encounter/tests/grip_transport_test.gd (the latter expects a screenshot output directory after --). Screenshots are real Godot viewport captures, not generated concept art.
