extends SceneTree

const CameraController = preload("res://camera_controller.gd")


func _initialize() -> void:
	call_deferred("run")


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("Camera 2D height: " + message)
		quit(1)
	return condition


func run() -> void:
	var camera: Camera3D = CameraController.new()
	root.add_child(camera)
	camera.set_process(false)

	var original_transform := Transform3D(
		Basis.from_euler(Vector3(-0.3, 0.25, 0.0)),
		Vector3(4.0, 8.0, 12.0)
	)
	camera.global_transform = original_transform

	camera.call("enter_top_down_2d", Vector3(3.0, 2.0, -4.0), 30.0, 0.0)
	var initial_position: Vector3 = camera.global_position
	var initial_size: float = camera.size
	camera.call("adjust_top_down_height", 6.0)
	if not _check(
		camera.global_position.is_equal_approx(initial_position + Vector3.UP * 6.0),
		"raising a zenithal camera must change only its height"
	):
		return
	if not _check(
		is_equal_approx(camera.size, initial_size),
		"camera height must not change orthographic zoom"
	):
		return
	camera.call("adjust_top_down_height", -6.0)
	if not _check(
		camera.global_position.is_equal_approx(initial_position),
		"descending must undo ascending movement"
	):
		return

	# The forest preset uses a 12 degree tilt: changing height must keep
	# the same map point under the center of the screen.
	camera.call("enter_top_down_2d", Vector3(3.0, 2.0, -4.0), 30.0, 12.0)
	initial_position = camera.global_position
	var initial_rotation: Vector3 = camera.global_rotation
	camera.call("adjust_top_down_height", 6.0)
	var expected_delta := Vector3(0.0, 6.0, 6.0 * tan(deg_to_rad(12.0)))
	if not _check(
		camera.global_position.is_equal_approx(initial_position + expected_delta),
		"tilted camera must preserve its target as height changes"
	):
		return
	if not _check(
		camera.global_rotation.is_equal_approx(initial_rotation),
		"height adjustment must not rotate camera"
	):
		return

	# A floor-level limit keeps the camera from dropping through the map.
	camera.call("adjust_top_down_height", -10000.0)
	if not _check(
		is_equal_approx(camera.global_position.y, 2.5),
		"camera must stay above its target plane"
	):
		return

	camera.call("exit_top_down_2d")
	if not _check(
		camera.global_transform.is_equal_approx(original_transform),
		"leaving 2D must restore the original 3D camera transform"
	):
		return
	if not _check(
		camera.projection == Camera3D.PROJECTION_PERSPECTIVE,
		"leaving 2D must restore the perspective projection"
	):
		return

	camera.queue_free()
	await process_frame
	print("PASS: 2D camera elevation preserves zoom, tilt target and 3D state")
	quit()
