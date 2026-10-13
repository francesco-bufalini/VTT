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

	var physics := HFlowContainer.new()
	physics.add_theme_constant_override("h_separation", 26)
	physics.add_theme_constant_override("v_separation", 9)
	root.add_child(physics)
	var speeds := VBoxContainer.new()
	var jumps := VBoxContainer.new()
	physics.add_child(speeds)
	physics.add_child(jumps)
	var jump_caption := Label.new()
	jump_caption.custom_minimum_size = Vector2(228, 45)
	jumps.add_child(jump_caption)
	var speed_grid := GridContainer.new()
	speed_grid.name = "PhysicsSpeedGrid"
	speed_grid.columns = 5
	speeds.add_child(speed_grid)
	for i: int in 5:
		var speed_cell := Control.new()
		speed_cell.custom_minimum_size = Vector2(110, 45)
		speed_grid.add_child(speed_cell)
	physics.size = Vector2(1400, 300)
	area._layout_physics_movement(physics, speeds, jumps)
	assert(speed_grid.columns == 5 and speeds.custom_minimum_size.x == 590 and jumps.custom_minimum_size.x == 476,
		"Wide Physics panels show five speeds and two jump captions horizontally")
	await process_frame
	await process_frame
	assert(absf(speeds.position.y - jumps.position.y) < 1.0,
		"Wide panel must actually display speeds and jump section on the same visual row")
	physics.size = Vector2(1000, 300)
	area._layout_physics_movement(physics, speeds, jumps)
	assert(speed_grid.columns == 3 and speeds.custom_minimum_size.x == 350 and jumps.custom_minimum_size.x == 476,
		"Mid-width panels use three speed columns and retain two horizontal jumps")
	await process_frame
	await process_frame
	assert(absf(speeds.position.y - jumps.position.y) < 1.0,
		"Medium panel still lays out speeds beside the jumps")
	physics.size = Vector2(480, 300)
	area._layout_physics_movement(physics, speeds, jumps)
	assert(speed_grid.columns == 2 and speeds.custom_minimum_size.x == 230
		and jumps.custom_minimum_size.x <= 460,
		"Narrow panels use two speed columns and allow jumps to wrap")
	await process_frame
	await process_frame
	assert(jumps.position.y > speeds.position.y,
		"Narrow panel wraps the jumps instead of causing horizontal overflow")
	print("PASS compact Physics fields and responsive speeds/jumps")
	quit()
