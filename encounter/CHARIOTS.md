# Party and flying chariots

The encounter starts with six party characters and three identical pegasus/chariot tokens.
Each vehicle has a 2 by 4 cell footprint: Large horse followed by a Large chariot.
Its 2 by 2 deck supports passengers using the existing tactical-platform system.
Select the vehicle to move/rotate it or apply the existing flying condition. Passengers
standing on its deck follow translation, rotation and flight. Flying passengers are independent.

## Assets

- Horse: https://opengameart.org/content/rigged-horse
  Original model Lyndon Daniels; rig Chad M; CC0 as stated on the asset page.
  Source preserved at assets/characters/source/riggedHorse.blend.
- Wings, chariot, harness and ornaments: original project geometry,
  assembled by assets/characters/source/build_chariot.py.
- Party anatomy uses the existing MakeHuman CC0 sources; additional feathered
  costume and accessories are original project geometry in source/build_party.py.

These are intermediate game models, not hand-sculpted production-quality characters.
Kaos has a walking pose with a raised forward foot and opposite arm swing, not a new
looping gait animation. His original round-based translation is unchanged.

## Changed files

- assets/makehuman/build_anatomy.py and generated kaos_anatomy.glb/source blend
- assets/characters/source/build_party.py and six generated party GLBs
- assets/characters/source/build_chariot.py and generated pegasus_chariot.glb
- hero_costume.gd, party_skins.gd, encounter_scenery.gd
- chariot_token.gd, hazard_controller.gd
- ../token.gd, ../interaction/token_drag.gd
- tests/capture_chariots.gd

## Focused verification

Run tests/capture_chariots.gd as a SceneTree script, passing an output directory after --.
It checks the nine starting tokens, landing on the deck, passenger translation,
rotation and flight, and exports screenshots of Kaos, the feathered woman and chariot.
