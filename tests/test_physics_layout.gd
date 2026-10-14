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
	physics.add_theme_constant_override("h_separation", 16)
	physics.add_theme_constant_override("v_separation", 6)
	root.add_child(physics)
	var speeds := VBoxContainer.new()
	var jumps := VBoxContainer.new()
	physics.add_child(speeds)
	physics.add_child(jumps)
	var jumps_heading := Label.new()
	jumps_heading.text = "SALTI · DISTANZE MASSIME"
	jumps.add_child(jumps_heading)
	var jump_flow := HFlowContainer.new()
	jump_flow.add_theme_constant_override("h_separation", 12)
	jumps.add_child(jump_flow)
	for i: int in 2:
		var jump_caption := Label.new()
		jump_caption.custom_minimum_size = Vector2(210, 45)
		jump_flow.add_child(jump_caption)
	var speed_grid := GridContainer.new()
	speed_grid.name = "PhysicsSpeedGrid"
	speed_grid.columns = 5
	speed_grid.add_theme_constant_override("h_separation", 8)
	speeds.add_child(speed_grid)
	for i: int in 5:
		var speed_cell := Control.new()
		speed_cell.custom_minimum_size = Vector2(73, 45)
		speed_grid.add_child(speed_cell)
	# Use an external sizing control (as in production, which measures the
	# parent Physics section). HFlowContainer itself can clamp its size to
	# children from the previous, wider layout before they are recomputed.
	var physics_measure := Control.new()
	root.add_child(physics_measure)
	for spec: Vector3i in [
		Vector3i(1400, 5, 1), Vector3i(1000, 5, 1),
		Vector3i(800, 3, 1), Vector3i(660, 2, 1),
		Vector3i(480, 5, 0), Vector3i(320, 3, 0)
	]:
		physics_measure.size.x = spec.x
		area._layout_physics_movement(physics_measure, speeds, jumps)
		physics.size = Vector2(spec.x, 300)
		var expected_speed_width: float = float(spec.y * 73 + (spec.y - 1) * 8)
		assert(speed_grid.columns == spec.y
			and absf(speeds.custom_minimum_size.x - expected_speed_width) < 1.0
			and absf(jumps.custom_minimum_size.x - minf(432.0, float(spec.x - 18))) < 1.0,
			"Speed columns and jump width adapt to a %d px panel" % spec.x)
		await process_frame
		await process_frame
		if spec.z == 1:
			assert(absf(speeds.position.y - jumps.position.y) < 1.0,
				"Speed and jump groups must share a row at %d px" % spec.x)
		else:
			assert(jumps.position.y > speeds.position.y,
				"Jump group must wrap below speeds at %d px" % spec.x)
	print("PASS compact Physics fields and responsive speeds/jumps")
	quit()
