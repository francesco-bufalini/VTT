extends Node3D

@export var cell_size: float = 1.0
@export_range(3, 21, 2) var cells_per_side: int = 5

var _camera: Camera3D = null
var _grid_mesh_instance: MeshInstance3D = null
var _last_snapped_center: Vector3 = Vector3.INF
var _half_extent_world: float = 2.5


func _ready() -> void:
	_rebuild()


func _process(_delta: float) -> void:
	if not visible:
		return
	if _camera == null or not is_instance_valid(_camera):
		return

	_update_position_around_camera()


func set_camera(new_camera: Camera3D) -> void:
	_camera = new_camera
	if is_inside_tree():
		_update_position_around_camera()


func get_half_extent_world() -> float:
	return _half_extent_world


func contains_world_point(point: Vector3) -> bool:
	var local_point: Vector3 = to_local(point)
	var epsilon := maxf(cell_size * 0.001, 0.0001)
	return (
		absf(local_point.x) <= _half_extent_world + epsilon
		and absf(local_point.y) <= _half_extent_world + epsilon
		and absf(local_point.z) <= _half_extent_world + epsilon
	)


func get_ray_exit_distance(origin: Vector3, direction: Vector3) -> float:
	# The camera normally sits inside the cube. Return the forward distance
	# at which its ray exits the currently displayed grid.
	var local_origin := to_local(origin)
	var local_direction := global_basis.inverse() * direction.normalized()
	var t_exit := INF

	for axis in range(3):
		var o: float = local_origin[axis]
		var d: float = local_direction[axis]
		if absf(d) < 0.000001:
			continue

		var t_a := (-_half_extent_world - o) / d
		var t_b := (_half_extent_world - o) / d
		var far_t := maxf(t_a, t_b)
		if far_t >= 0.0:
			t_exit = minf(t_exit, far_t)

	if is_inf(t_exit):
		return 0.0

	return maxf(0.0, t_exit)


func _update_position_around_camera() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return

	var camera_position: Vector3 = _camera.global_position
	var snapped_center := Vector3(
		_snap_axis_to_cell_center(camera_position.x),
		_snap_axis_to_cell_center(camera_position.y),
		_snap_axis_to_cell_center(camera_position.z)
	)

	if snapped_center != _last_snapped_center:
		global_position = snapped_center
		_last_snapped_center = snapped_center


func _snap_axis_to_cell_center(value: float) -> float:
	var safe_cell_size := maxf(cell_size, 0.001)
	return (
		floor(value / safe_cell_size) * safe_cell_size
		+ safe_cell_size * 0.5
	)


func _rebuild() -> void:
	if _grid_mesh_instance != null and is_instance_valid(_grid_mesh_instance):
		_grid_mesh_instance.queue_free()

	var safe_cell_size := maxf(cell_size, 0.001)
	cells_per_side = maxi(3, cells_per_side)
	if cells_per_side % 2 == 0:
		cells_per_side += 1

	_half_extent_world = float(cells_per_side) * safe_cell_size * 0.5

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.75, 1.0, 0.18)
	material.emission_enabled = true
	material.emission = Color(0.04, 0.22, 0.38, 1.0)
	material.emission_energy_multiplier = 0.40
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)

	var min_value := -_half_extent_world
	var max_value := _half_extent_world

	# Full lattice: with 5 cells there are only 6 grid coordinates per axis.
	for a in range(cells_per_side + 1):
		var coordinate_a := min_value + float(a) * safe_cell_size

		for b in range(cells_per_side + 1):
			var coordinate_b := min_value + float(b) * safe_cell_size

			mesh.surface_add_vertex(
				Vector3(min_value, coordinate_a, coordinate_b)
			)
			mesh.surface_add_vertex(
				Vector3(max_value, coordinate_a, coordinate_b)
			)

			mesh.surface_add_vertex(
				Vector3(coordinate_a, min_value, coordinate_b)
			)
			mesh.surface_add_vertex(
				Vector3(coordinate_a, max_value, coordinate_b)
			)

			mesh.surface_add_vertex(
				Vector3(coordinate_a, coordinate_b, min_value)
			)
			mesh.surface_add_vertex(
				Vector3(coordinate_a, coordinate_b, max_value)
			)

	mesh.surface_end()

	_grid_mesh_instance = MeshInstance3D.new()
	_grid_mesh_instance.name = "LocalGrid3DLines"
	_grid_mesh_instance.mesh = mesh
	add_child(_grid_mesh_instance)

	_last_snapped_center = Vector3.INF
	_update_position_around_camera()
