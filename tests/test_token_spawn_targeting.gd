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

	grid.free()
	print("PASS: token spawn targeting follows the pointed visible grid cell")
	quit()
