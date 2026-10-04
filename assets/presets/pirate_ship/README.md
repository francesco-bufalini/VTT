# The Siren's Light preset

Expected runtime asset:

`res://assets/presets/pirate_ship/sirens_light_pirate_ship_preset.glb`

The prepared GLB is uniformly normalized so the median cannon length is
approximately **2 VTT grid cells** when the preset root is scaled by the
current `cell_size`.

The campaign editor adds runtime collision only to the ship hull and deck
meshes. Water, sails and rigging remain visual-only to keep collision cost
reasonable.
