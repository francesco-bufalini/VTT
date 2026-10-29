# Character miniature heights

The `characters` release uses a 1.50 m grid cell. Scale is calibrated to the
anatomical crown of the head, rather than the highest mesh point: hammers, staffs,
flames, halos, horns, crests and loose hair strands can extend above that point.
The model is scaled uniformly, retaining its pose, lowest-point grounding,
materials and textures. Tactical size and the one-cell footprint stay unchanged.

| Character | Head height | Head height in cells |
| --- | ---: | ---: |
| Ore | 1.55 m | 1.0333 |
| Gilliam | 1.70 m | 1.1333 |
| Kaos | 2.50 m | 1.6667 |
| Kryss | 1.60 m | 1.0667 |
| Phenax | 2.50 m | 1.6667 |
| Sariel | 1.65 m | 1.1000 |
| Valandir | 2.50 m | 1.6667 |
| Wilfred | 1.80 m | 1.2000 |
| Wyrda | 1.75 m | 1.1667 |
| Nazaryl | 1.85 m | 1.2333 |
| Tiabald | 1.80 m | 1.2000 |
| Harmakis | 1.40 m | 0.9333 |

Ore, Gilliam, Kaos, Phenax, Valandir and Tiabald use the heights supplied by the user.
The remaining heights are small chosen variations for the specified ancestries.
These are miniature presentation settings, not new creature rules.

`scripts/data/character_miniature_heights.json` owns the curated source head
landmarks, original pack and visual hashes, and target heights. The landmarks
were reviewed from 900 x 900 orthographic front/side/back renders centered on the
source bounds, with the camera heights recorded in the specification. A pixel's
source Y above the original minimum is `source_total_height_cells / 2 +
(450 - reference_head_pixel_y) * reference_camera_height_cells / 900`.
Because the landmark is visual, the anatomical selection is approximate; the
chosen scale then applies exactly and is verified at runtime. A `ruler_refinement` records a final fixed-grid render correction, using `(camera_center_y_cells + (450 - head_pixel_y) * camera_height_cells / 900) / applied_scale` for the source landmark.

Keep the original release packs and `token_catalog.json` in an ignored staging
folder before rebuilding. Recalibration accepts those original hashes only,
preventing compounded scaling. Run from the project root:

```powershell
$godot = 'C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --script res://tools/token_packs/calibrate_character_packs.gd -- --source-dir res://.token_pack_build/character_scale/original --output-dir res://.token_pack_build/character_scale/final
& $godot --headless --path . --script res://tools/token_packs/calibrate_character_packs.gd -- --source-dir res://.token_pack_build/character_scale/final --output-dir res://.token_pack_build/character_scale/verification --verify
python tools/token_packs/update_character_catalogs.py --pack-dir .token_pack_build/character_scale/final --source-catalog .token_pack_build/character_scale/original/token_catalog.json
```

The calibrator retains each original bundled visual byte for byte under
`_source_visual.res`. A tiny instanced wrapper with the calibrated transform
occupies the original `_visual.res` path. Both the ordinary board loader and
existing maps therefore retain the same visual path and receive the new scale.
The remote token scene records the complete accessory-inclusive height for the
existing collision and placement code. Pack paths and token IDs remain stable. Verification checks original visual hashes, imported scale, grounding,
complete mesh height, loading through the saved visual path, and tactical
footprint in the real token scene.

The catalog generator changes only these nine entries' hashes, byte counts and
versions in the unified catalog, and generates the matching release catalog.
Publish packs before catalogs so clients never receive checksums for unavailable
assets. Existing installations recognize changed checksums through the ordinary
token cache verification; a token already mounted in an open application needs
a fresh application session to mount the new pack.

Nazaryl (elf) and Tiabald (human) are additional user-provided GLB imports.
Their curated source identities, hashes, optimization budgets and scale factors
live in `scripts/data/character_miniature_imports.json`. Original files stay
unchanged; the reusable GLBs retain materials, with 2048 px maps and 249,999
triangles each instead of approximately 1.5 million. They were exported with
Blender 5.2.2 LTS, then visually checked and imported through Godot 4.7.2.
Tiabald's helmet spike is excluded from the head reference; the small sculpted
base remains part of his miniature. Nazaryl uses a chosen 1.85 m head reference.

Pass `--additions scripts/data/character_miniature_imports.json` to the catalog
generator when publishing their `nazaryl.pck` and `tiabald.pck` with the original
nine calibrated packs. Newly imported packs start at version 1, while the
recalibrated original packs retain version 2. Both use the established visual
paths, one-cell footprints and ordinary token pack loading.

Harmakis uses the user-requested 1.40 m head reference and `Small` size metadata.
The native footprint stays at one grid cell, matching the existing Small size
convention. Fur tips and ears remain above the curated crown reference; the
whole miniature still stays below the first 1.50 m grid line. The source GLB is
preserved, with the same 250k triangle / 2048 px texture budget as the other
new character imports.
