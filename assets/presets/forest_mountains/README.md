# Forest & Mountains preset asset

Runtime path expected by the campaign editor:

`res://assets/presets/forest_mountains/forest_mountains_preset.glb`

Source model: **landscape forest & mountains** by **dasy444** on Sketchfab.
License declared in the source GLB metadata: **CC BY 4.0**.

The VTT-prepared asset is intentionally optimized for the campaign editor:
- 1,167 tree billboards retained.
- Every tree normalized to a 2 x 2 grid-cell footprint.
- Every tree normalized to 8 grid cells in height.
- Terrain and mountain meshes retained.
- Grass-card swarms and the embedded sky sphere removed for runtime performance.
- Textures downscaled for a lightweight preset.

The campaign editor scales the preset root by the current VTT cell size, so
these dimensions remain grid-relative.
