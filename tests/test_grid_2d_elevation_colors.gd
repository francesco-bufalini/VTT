extends SceneTree

const CameraController = preload("res://camera_controller.gd")
const VolumetricGrid = preload("res://volumetric_grid.gd")


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("2D elevation grid colors: " + message)
		quit(1)
	return condition


func _count_lower_tinted(grid: Node3D, mesh: MultiMesh, lower_color: Color) -> int:
	var count: int = 0
	var cells: Array = (grid.get("_active_occupied") as Dictionary).keys()
	var camera: Camera3D = grid.get("_camera") as Camera3D
	var in_2d: bool = bool(camera.call("is_top_down_2d"))
	var floor_y: float = float(camera.call("get_top_down_level"))
	for index: int in range(mesh.instance_count):
		# The headless dummy renderer returns black for all instance-color
		# readbacks. Check production tint math there; real renderers also
		# verify the actual per-instance color buffer.
		var tint: Color = (
			grid.call("_cell_instance_tint", cells[index], in_2d, floor_y)
			if DisplayServer.get_name() == "headless"
			else mesh.get_instance_color(index)
		)
		# Some Godot renderers pack per-instance colors to 8 bits.
		if (
			absf(tint.r - lower_color.r) < 0.02
			and absf(tint.g - lower_color.g) < 0.02
			and absf(tint.b - lower_color.b) < 0.02
			and absf(tint.a - lower_color.a) < 0.02
		):
			count += 1
	return count


func _run() -> void:
	var board: Node3D = Node3D.new()
	root.add_child(board)

	var camera: Camera3D = CameraController.new()
	camera.name = "Camera3D"
	board.add_child(camera)
	camera.set_process(false)

	var grid: Node3D = VolumetricGrid.new()
	board.add_child(grid)
	grid.call("set_camera", camera)
	grid.call("set_surface_overlay_bias_cells", 0.025)

	var material: StandardMaterial3D = grid.get("_grid_material") as StandardMaterial3D
	var mesh: MultiMesh = grid.get("_multimesh") as MultiMesh
	var original_albedo: Color = material.albedo_color
	if not _check(
		mesh.use_colors
		and material.vertex_color_use_as_albedo,
		"instances need their own vertex colors"
	):
		return
	if not _check(
		material.no_depth_test,
		"2D grid needs an overlay so lower cells remain visible over the terrain"
	):
		return

	grid.set("_active_occupied", {
		Vector3i(0, -2, 0): true,
		Vector3i(1, -1, 0): true,
		Vector3i(2, 0, 0): true,
		Vector3i(3, 2, 0): true,
	})
	camera.call("enter_top_down_2d", Vector3.ZERO, 30.0, 0.0)
	grid.call("_update_multimesh_instances")
	if not _check(
		mesh.instance_count == 4,
		"all occupied squares must remain drawn"
	):
		return
	if not _check(
		_count_lower_tinted(grid, mesh, VolumetricGrid.GRID_LOWER_INSTANCE_TINT) == 1,
		"only squares fully below floor 0 should turn muted slate"
	):
		return
	if not _check(
		grid.call("_cell_instance_tint", Vector3i(1, -1, 0), true, 0.0)
		== VolumetricGrid.GRID_NORMAL_INSTANCE_TINT,
		"the floor-level square keeps its parchment tint"
	):
		return

	camera.call("set_top_down_level", 2.0)
	grid.call("_update_multimesh_instances")
	if not _check(
		_count_lower_tinted(grid, mesh, VolumetricGrid.GRID_LOWER_INSTANCE_TINT) == 3
		and mesh.instance_count == 4,
		"changing levels must recolor existing instances without hiding them"
	):
		return

	camera.call("exit_top_down_2d")
	grid.call("set_surface_overlay_bias_cells", 0.0)
	grid.call("_update_multimesh_instances")
	if not _check(
		_count_lower_tinted(grid, mesh, VolumetricGrid.GRID_LOWER_INSTANCE_TINT) == 0,
		"3D mode must restore the single original grid color"
	):
		return
	if not _check(
		material.albedo_color.is_equal_approx(original_albedo)
		and not material.no_depth_test,
		"grid base tint and depth-testing must be unchanged in 3D"
	):
		return
	if not _check(
		VolumetricGrid.GRID_LOWER_INSTANCE_TINT.a >= 0.75
		and VolumetricGrid.GRID_LOWER_INSTANCE_TINT.r > 0.6,
		"lower squares must stay readable with a restrained color"
	):
		return

	board.queue_free()
	await process_frame
	print("PASS: 2D lower grid squares use restrained persistent tint; 3D grid restores original appearance")
	quit()
