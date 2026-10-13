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
	var speed_grid := GridContainer.new()
	speed_grid.name = "PhysicsSpeedGrid"
	speed_grid.columns = 5
	speeds.add_child(speed_grid)
	for i: int in 5:
		var speed_cell := Control.new()
		speed_cell.custom_minimum_size.x = 110
		speed_grid.add_child(speed_cell)
	physics.size = Vector2(1400, 300)
	area._layout_physics_movement(physics, speeds, jumps)
	assert(speed_grid.columns == 5 and speeds.custom_minimum_size.x == 590 and jumps.custom_minimum_size.x == 476,
		"Wide Physics panels show five speeds and two jump captions horizontally")
	physics.size = Vector2(1000, 300)
	area._layout_physics_movement(physics, speeds, jumps)
	assert(speed_grid.columns == 3 and speeds.custom_minimum_size.x == 350 and jumps.custom_minimum_size.x == 476,
		"Mid-width panels use three speed columns and retain two horizontal jumps")
	physics.size = Vector2(480, 300)
	area._layout_physics_movement(physics, speeds, jumps)
	assert(speed_grid.columns == 2 and speeds.custom_minimum_size.x == 230
		and jumps.custom_minimum_size.x <= 460,
		"Narrow panels use two speed columns and allow jumps to wrap")
	print("PASS compact Physics fields and responsive speeds/jumps")
	quit()
