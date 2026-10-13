extends SceneTree

# Lightweight layout invariants without starting the entire board.
const CreatureArea = preload("res://vtt/creature_area.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var area := CreatureArea.new()
	root.add_child(area)
	var fields := HFlowContainer.new()
	root.add_child(fields)
	var species_field: VBoxContainer = area._physics_field(fields, "Razza / Specie", 216)
	var species_value := OptionButton.new()
	species_field.add_child(species_value)
	assert(species_field.get_parent() == fields and species_field.get_child(0) is Label
		and species_field.get_child(1) == species_value and species_field.custom_minimum_size.x == 216,
		"Physics captions and controls stay together while wrapping")

	var physics := Control.new()
	root.add_child(physics)
	var speeds := VBoxContainer.new()
	var jumps := VBoxContainer.new()
	physics.add_child(speeds)
	physics.add_child(jumps)
	physics.size = Vector2(1400, 300)
	area._layout_physics_movement(physics, speeds, jumps)
	assert(speeds.custom_minimum_size.x == 590 and jumps.custom_minimum_size.x == 550,
		"Wide Physics panels put all five speeds beside jumps")
	physics.size = Vector2(1000, 300)
	area._layout_physics_movement(physics, speeds, jumps)
	assert(speeds.custom_minimum_size.x == 350 and jumps.custom_minimum_size.x == 550,
		"Mid-width panels narrow the speeds block to share the row")
	physics.size = Vector2(480, 300)
	area._layout_physics_movement(physics, speeds, jumps)
	assert(speeds.custom_minimum_size.x <= 460 and jumps.custom_minimum_size.x <= 460,
		"Narrow panels wrap both blocks without retaining desktop widths")
	print("PASS compact Physics fields and responsive speeds/jumps")
	quit()
