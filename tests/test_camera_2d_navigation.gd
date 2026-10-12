extends SceneTree

const CameraController = preload("res://camera_controller.gd")


func _initialize() -> void:
	call_deferred("run")


func _check(ok: bool, description: String) -> bool:
	if not ok:
		push_error("Camera 2D navigation: " + description)
		quit(1)
	return ok


func run() -> void:
	var board := Node3D.new()
	root.add_child(board)
	var camera: Camera3D = CameraController.new()
	board.add_child(camera)
	camera.set_process(false)
	camera.call("enter_top_down_2d", Vector3.ZERO, 40.0)
	var original: Vector3 = camera.global_position

	# The map follows a two-finger swipe; the camera moves oppositely
	# in X and Z while keeping its height and zoom.
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(2.0, -3.0)
	if not _check(
		bool(camera.call("handle_top_down_navigation_input", pan)),
		"two-finger pan must be handled"
	):
		return
	if not _check(
		camera.global_position.x < original.x
		and camera.global_position.z > original.z
		and is_equal_approx(camera.global_position.y, original.y)
		and is_equal_approx(camera.size, 40.0),
		"two-finger pan changes only map position"
	):
		return

	# Shift+pan zooms without changing the camera center.
	var before_zoom: Vector3 = camera.global_position
	pan.shift_pressed = true
	pan.delta = Vector2(0.0, -2.0)
	camera.call("handle_top_down_navigation_input", pan)
	if not _check(
		camera.size < 40.0 and camera.global_position.is_equal_approx(before_zoom),
		"Shift+two-finger scroll zooms instead of panning"
	):
		return

	var size_before_pinch: float = camera.size
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 1.25
	camera.call("handle_top_down_navigation_input", pinch)
	if not _check(
		camera.size < size_before_pinch,
		"pinching outward zooms in"
	):
		return

	# On some operating systems touchpad scrolling arrives as wheel input.
	var scroll := InputEventMouseButton.new()
	scroll.button_index = MOUSE_BUTTON_WHEEL_DOWN
	scroll.factor = 1.0
	scroll.pressed = true
	var wheel_start: Vector3 = camera.global_position
	var wheel_size: float = camera.size
	camera.call("handle_top_down_navigation_input", scroll)
	if not _check(
		camera.global_position.z < wheel_start.z
		and is_equal_approx(camera.size, wheel_size),
		"wheel fallback pans rather than zooming"
	):
		return
	scroll.shift_pressed = true
	camera.call("handle_top_down_navigation_input", scroll)
	if not _check(
		camera.size > wheel_size,
		"Shift+mouse wheel zooms on platforms using wheel events"
	):
		return

	# Mouse middle-button drag pans without selecting a token.
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_MIDDLE
	down.pressed = true
	camera.call("handle_top_down_navigation_input", down)
	var move := InputEventMouseMotion.new()
	move.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	move.relative = Vector2(20.0, 0.0)
	var drag_start: Vector3 = camera.global_position
	camera.call("handle_top_down_navigation_input", move)
	if not _check(
		camera.global_position.x < drag_start.x,
		"middle-mouse drag must pan"
	):
		return

	# Bounds apply to gesture zoom just like keyboard zoom.
	pinch.factor = 1000.0
	camera.call("handle_top_down_navigation_input", pinch)
	if not _check(
		is_equal_approx(camera.size, float(camera.get("top_down_min_size"))),
		"gesture zoom must respect the minimum orthographic size"
	):
		return

	camera.call("exit_top_down_2d")
	if not _check(
		not bool(camera.call("handle_top_down_navigation_input", pan)),
		"navigation gestures must not affect the 3D camera"
	):
		return
	board.queue_free()
	print("Camera 2D touchpad and mouse navigation: OK")
	quit()
