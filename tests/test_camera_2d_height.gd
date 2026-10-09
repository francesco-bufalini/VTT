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
	var expected_delta := Vector3(0.0, 6.0, 6.0 * tan(deg_to_rad(12.0)))
	if not _check(
		camera.global_position.is_equal_approx(initial_position + expected_delta),
		"tilted forest view must preserve the target when changing floors"
	):
		return

	var overlay: Control = ElevationOverlay.new()
	board.add_child(overlay)
	var metric: String = String(overlay.call("_format_difference", 1.0))
	if not _check(
		metric.contains("1.52") and metric.contains("5.0")
		and metric.contains("quadretti"),
		"relative elevations must be shown in meters, feet and squares"
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

	board.queue_free()
	await process_frame
	print("PASS: 2D floors are discrete, elevation units are consistent and 3D state restores")
	quit()
