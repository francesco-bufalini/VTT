# Kaos and Klothis: anatomical visual revision

The bodies use MakeHuman's CC0 graphical base mesh and morph targets, downloaded
from the official makehumancommunity/makehuman repository. No MakeHuman program
code is included. The upstream license is preserved in ../makehuman/LICENSE.md.

Source: https://github.com/makehumancommunity/makehuman
License: https://github.com/makehumancommunity/makehuman/blob/master/LICENSE.md

Original morph data: Data Collection AB, Joel Palmius and Jonas Hauquier.
The build script ../makehuman/build_anatomy.py assembles and poses the body in
Blender, applies subdivision, and exports the two GLB files. Editable Blender
sources are in source/ (excluded from Godot import to avoid duplicate assets).
Each body contains approximately 428,000 triangles after subdivision.

Costume, hair geometry and accessories are original project geometry, assembled
by encounter/hero_costume.gd. Cloth uses the existing Poly Haven CC0 fabric maps.
No Dark Souls assets or photographed character surfaces were imported.

This is an intermediate anatomical model, not a finished production character.
Remaining specialist work: sculpted facial expressions, fitted garment topology,
authored hair cards and textures, hand-engraved armor normal maps, optimized LODs
and a final deformation rig. The gameplay root, collision, shoulder grid and seal
anchors remain independent of the replaceable visual meshes.

Changed existing files: encounter/sculpted_giant_visual.gd,
encounter/encounter_scenery.gd.
New runtime files: encounter/hero_costume.gd, encounter/silver_hair.gdshader,
the two anatomical GLBs and their import metadata.
New sources: assets/makehuman/*, assets/characters/source/*.
Visual capture: encounter/tests/capture_characters.gd.
