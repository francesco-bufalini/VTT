extends SceneTree

const CameraController = preload("res://camera_controller.gd")
const ElevationLevels = preload("res://vtt/top_down_elevation_levels.gd")
const ElevationOverlay = preload("res://vtt/top_down_elevation_overlay.gd")


class Board extends Node3D:
	var cell_size: float = 1.0


func _initialize() -> void:
	call_deferred("run")


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("Camera 2D floors: " + message)
		quit(1)
	return condition


func _hold_fixture_levels() -> Array[float]:
	return [0.0, 6.0, 12.0, 18.0]


func _add_floor(board: Node3D, y: float) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.position.y = y - 0.1
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(15.0, 0.2, 15.0)
	shape.shape = box
	body.add_child(shape)
	board.add_child(body)


func run() -> void:
	var board: Board = Board.new()
	root.add_child(board)
	_add_floor(board, 0.0)
	_add_floor(board, 6.0)

	var camera: Camera3D = CameraController.new()
	camera.name = "Camera3D"
	board.add_child(camera)
	camera.set_process(false)
	var original_transform := Transform3D(
		Basis.from_euler(Vector3(-0.3, 0.25, 0.0)),
		Vector3(4.0, 8.0, 12.0)
	)
	camera.global_transform = original_transform
	var initial_near: float = camera.near

	var probe: Node3D = ElevationLevels.new()
	board.add_child(probe)
	probe.call("setup", board)
	camera.call(
		"set_top_down_floor_levels_provider",
		Callable(probe, "get_solid_levels")
	)
	# Allow Godot's physics server to register the collision boxes.
	await physics_frame
	await physics_frame

	camera.call("enter_top_down_2d", Vector3.ZERO, 30.0, 0.0)
	var solid_levels: Array = probe.call("get_solid_levels")
	if not _check(
		solid_levels.size() == 2
		and absf(float(solid_levels[0])) < 0.01
		and absf(float(solid_levels[1]) - 6.0) < 0.01,
		"two stacked collidable floors must yield two discrete levels"
	):
		return

	var initial_position: Vector3 = camera.global_position
	var initial_size: float = camera.size
	var slice_near: float = camera.near
	camera.call("step_top_down_level", 1)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 6.0),
		"Space must step to the next higher solid surface"
	):
		return
	if not _check(
		camera.global_position.is_equal_approx(initial_position + Vector3.UP * 6.0),
		"moving up a floor must preserve camera clearance"
	):
		return
	if not _check(
		is_equal_approx(camera.size, initial_size)
		and is_equal_approx(camera.near, slice_near),
		"floor navigation must not alter orthographic zoom or slice distance"
	):
		return
	camera.call("step_top_down_level", 1)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 6.0),
		"no solid above must prevent further climbing"
	):
		return

	var lower_value: Variant = probe.call(
		"get_lower_square_surface", Vector3(0.1, 6.0, 0.1), 6.0
	)
	var lower_square: Dictionary = lower_value as Dictionary
	if not _check(
		not lower_square.is_empty()
		and absf(float(lower_square.get("level", -100.0))) < 0.01,
		"hovering over an upper square must identify the lower solid surface"
	):
		return

	camera.call("step_top_down_level", -1)
	if not _check(
		camera.global_position.is_equal_approx(initial_position),
		"Shift+Space must return to the lower level"
	):
		return

	camera.call("enter_top_down_2d", Vector3.ZERO, 30.0, 12.0)
	initial_position = camera.global_position
	camera.call("step_top_down_level", 1)
	if not _check(
		camera.global_position.is_equal_approx(initial_position + Vector3.UP * 6.0),
		"tilted forest view must preserve the target when changing floors"
	):
		return

	var overlay: Control = ElevationOverlay.new()
	board.add_child(overlay)
	# 1 square = 5 ft = 1.5 m by the VTT's tactical convention.
	# No centimeter conversions or fractional physical offsets should leak
	# into the on-screen height labels.
	if not _check(
		String(overlay.call("_format_difference", 1.0)) ==
		"+1.5 m · +5 ft · +1 quadretti",
		"one square must display as 1.5 m / 5 ft"
	):
		return
	if not _check(
		String(overlay.call("_format_difference", 2.0)) ==
		"+3 m · +10 ft · +2 quadretti",
		"two squares must display as 3 m, not 3.05 m"
	):
		return
	if not _check(
		String(overlay.call("_format_difference", -1.0)) ==
		"-1.5 m · -5 ft · -1 quadretti",
		"negative elevations must preserve sign in every unit"
	):
		return
	if not _check(
		String(overlay.call("_format_difference", 1.02)) ==
		"+1.5 m · +5 ft · +1 quadretti",
		"minor physics offsets must snap to whole grid squares"
	):
		return
	if not _check(
		int(overlay.call("_difference_cells", 0.02)) == 0,
		"sub-cell physics offsets must not generate zero-height badges"
	):
		return

	camera.call("exit_top_down_2d")
	if not _check(
		camera.global_transform.is_equal_approx(original_transform)
		and camera.projection == Camera3D.PROJECTION_PERSPECTIVE
		and is_equal_approx(camera.near, initial_near),
		"leaving 2D must restore 3D transform, projection and near clipping"
	):
		return

	# Continuous 2D floor navigation: one initial step, a short delay,
	# then repeat while Space is held, without skipping solid surfaces.
	camera.call("set_top_down_floor_levels_provider", Callable(self, "_hold_fixture_levels"))
	camera.call("enter_top_down_2d", Vector3.ZERO, 30.0, 0.0)
	var repeat_size: float = camera.size
	camera.call("_advance_top_down_level_hold", 1, 0.016)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 6.0),
		"holding Space must start with an immediate step"
	):
		return
	camera.call("_advance_top_down_level_hold", 1, 0.20)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 6.0),
		"the initial repeat delay must prevent accidental double steps"
	):
		return
	camera.call("_advance_top_down_level_hold", 1, 0.10)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 12.0),
		"holding Space beyond the delay must reach the next floor"
	):
		return
	camera.call("_advance_top_down_level_hold", 1, 0.12)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 18.0),
		"holding Space must keep repeating through all solid floors"
	):
		return
	camera.call("_advance_top_down_level_hold", 1, 0.5)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 18.0),
		"holding Space at the highest floor must not create phantom levels"
	):
		return

	camera.call("_advance_top_down_level_hold", 0, 0.016)
	camera.call("_advance_top_down_level_hold", -1, 0.016)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 12.0),
		"Shift+Space must start descending immediately"
	):
		return
	camera.call("_advance_top_down_level_hold", -1, 0.29)
	camera.call("_advance_top_down_level_hold", -1, 0.12)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 0.0),
		"holding Shift+Space must keep descending to the lowest floor"
	):
		return

	camera.call("_advance_top_down_level_hold", 1, 0.016)
	camera.call("_advance_top_down_level_hold", -1, 0.016)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 0.0),
		"toggling Shift while holding Space must reverse direction immediately"
	):
		return
	camera.call("_advance_top_down_level_hold", 0, 0.016)
	camera.call("_advance_top_down_level_hold", 1, 0.016)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 6.0)
		and is_equal_approx(camera.size, repeat_size),
		"releasing and pressing Space must rearm one step without changing zoom"
	):
		return
	camera.call("exit_top_down_2d")
	if not _check(
		camera.global_transform.is_equal_approx(original_transform),
		"held 2D movement must still restore the original 3D camera pose"
	):
		return

	board.queue_free()
	await process_frame
	print("PASS: 2D floors, elevation units, held Space/Shift+Space repeats and 3D restoration")
	quit()
