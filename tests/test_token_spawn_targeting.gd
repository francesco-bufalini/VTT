extends SceneTree

const VolumetricGrid = preload("res://volumetric_grid.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var grid := VolumetricGrid.new()
	grid.cell_size = 1.0
	grid.display_offset_cells = Vector3.ZERO
	grid._active_occupied = {
		Vector3i(0, 0, 0): true,
		Vector3i(0, 0, 1): true,
	}

	# At this shallow angle the visible top of z=0 is crossed first, while the
	# underlying physical surface would only be reached in z=1. Token spawning
	# must follow the visible square the player is actually pointing at.
	var origin := Vector3(0.5, 3.0, -2.0)
	var physical_hit := Vector3(0.5, 0.0, 1.5)
	var direction := (physical_hit - origin).normalized()
	var pick: Dictionary = grid.pick_visible_top_cell_from_ray(
		origin,
		direction,
		origin.distance_to(physical_hit) + 1.5
	)

	assert(bool(pick.get("valid", false)))
	assert(pick.get("cell") == Vector3i(0, 0, 0))
	var top_center: Vector3 = pick.get("top_center", Vector3.ZERO)
	assert(top_center.is_equal_approx(Vector3(0.5, 1.0, 0.5)))

	# A medium token rests on the first visible top face.
	assert(is_equal_approx(
		grid.get_clear_spawn_floor_for_footprint(
			Vector3(0.5, 1.5, 0.5), 1.0, 1.0, 1.0
		),
		1.0
	))

	# A Large token is snapped to four adjacent squares; the first
	# pointed square is low but the statue rises two voxels in the next one.
	# All four footprint columns must clear the grid BEFORE spawning.
	grid._active_occupied[Vector3i(1, 1, 0)] = true
	grid._active_occupied[Vector3i(1, 2, 0)] = true
	var large_floor: float = grid.get_clear_spawn_floor_for_footprint(
		Vector3(1.0, 2.0, 1.0), 2.0, 1.0, 1.0
	)
	assert(is_equal_approx(large_floor, 3.0))

	# Tall models must also clear geometry above their original base.
	grid._active_occupied[Vector3i(0, 3, 0)] = true
	var tall_floor: float = grid.get_clear_spawn_floor_for_footprint(
		Vector3(0.5, 1.5, 0.5), 1.0, 3.0, 1.0
	)
	assert(is_equal_approx(tall_floor, 4.0))

	grid.free()
	print("PASS: token spawn follows visible grid and clears full body footprint")
	quit()
