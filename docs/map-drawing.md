# Desktop map drawing

Open the map context menu, then **Misura e aree → Disegno: parallelepipedo (4 vertici)**.

1. Click the first base corner on the map or visible volumetric grid.
2. Click the end of the first side to set length and orientation.
3. Click the adjacent base corner to set width. The point is projected perpendicular to the first side, keeping a rectangular base at the first corner’s elevation.
4. Move the mouse up/down to set height, then click to confirm the fourth vertex vertically above the first corner. The wheel adjusts height by one grid cell, including in the top-down view.

Positions and dimensions are free, without grid snapping. Before height selection the wheel changes colour; Ctrl + wheel changes colour at any stage. The current preview shows dimensions in feet, metres and cells. Right-click cancels the unfinished drawing; Esc or R leaves drawing mode and restores normal camera controls. After completion the tool is ready for another drawing.

Drawings reuse persistent AoEs: the area sidebar lists their dimensions and intersecting creatures, provides move/delete controls, and uses normal undo/redo, board snapshots, autosave and synchronization. The existing clear-all-AoEs action also clears drawings. These volumes do not add terrain collisions or automatic damage. Creating drawings is currently a desktop feature; native drawings are projected into shared map images.

The additive `parallelepiped` shape stores `box_points` as four serialized world-space vertices (origin, length, width, height), together with the existing `start`, `end` and `color` fields. The geometry helper rejects nonfinite, degenerate, nonrectangular and out-of-bounds data. Existing shape records are unchanged.

Focused regression: `tests/test_map_box_drawing.gd`, also included in `scripts/validate.ps1 -Tests`.
