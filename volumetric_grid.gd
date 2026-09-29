extends Node3D

@export var cell_size: float = 1.0
@export var cube_size_world: float = 30.0

var _camera: Camera3D = null
var _grid_mesh_instance: MeshInstance3D = null
var _last_snapped_center: Vector3 = Vector3.INF
var _cells_per_side: int = 30
var _half_extent_world: float = 15.0


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
	return (
		absf(local_point.x) <= _half_extent_world
		and absf(local_point.y) <= _half_extent_world
		and absf(local_point.z) <= _half_extent_world
	)


func _update_position_around_camera() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return

	var camera_position: Vector3 = _camera.global_position
	var snapped_center: Vector3 = Vector3(
		round(camera_position.x / cell_size) * cell_size,
		round(camera_position.y / cell_size) * cell_size,
		round(camera_position.z / cell_size) * cell_size
	)

	if snapped_center != _last_snapped_center:
		global_position = snapped_center
		_last_snapped_center = snapped_center


func _rebuild() -> void:
	if _grid_mesh_instance != null and is_instance_valid(_grid_mesh_instance):
		_grid_mesh_instance.queue_free()

	_cells_per_side = maxi(
		2,
		int(round(cube_size_world / maxf(cell_size, 0.001)))
	)

	# Un numero pari mantiene il centro del volume su un'intersezione
	# della griglia e la rende stabile mentre segue la camera.
	if _cells_per_side % 2 != 0:
		_cells_per_side += 1

	_half_extent_world = (
		float(_cells_per_side) * cell_size * 0.5
	)

	_grid_mesh_instance = MeshInstance3D.new()
	_grid_mesh_instance.name = "LocalGrid3DLines"
	add_child(_grid_mesh_instance)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.75, 1.0, 0.16)
	material.emission_enabled = true
	material.emission = Color(0.04, 0.22, 0.38, 1.0)
	material.emission_energy_multiplier = 0.38
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)

	var min_value: float = -_half_extent_world
	var max_value: float = _half_extent_world

	# Una sola mesh / un solo draw call: tre famiglie di rette ortogonali.
	# Non ricostruiamo la mesh mentre la camera si muove: spostiamo solo il nodo.
	for a: int in range(_cells_per_side + 1):
		var coordinate_a: float = min_value + float(a) * cell_size

		for b: int in range(_cells_per_side + 1):
			var coordinate_b: float = min_value + float(b) * cell_size

			# Linee parallele a X, per ogni combinazione Y/Z.
			mesh.surface_add_vertex(
				Vector3(min_value, coordinate_a, coordinate_b)
			)
			mesh.surface_add_vertex(
				Vector3(max_value, coordinate_a, coordinate_b)
			)

			# Linee parallele a Y, per ogni combinazione X/Z.
			mesh.surface_add_vertex(
				Vector3(coordinate_a, min_value, coordinate_b)
			)
			mesh.surface_add_vertex(
				Vector3(coordinate_a, max_value, coordinate_b)
			)

			# Linee parallele a Z, per ogni combinazione X/Y.
			mesh.surface_add_vertex(
				Vector3(coordinate_a, coordinate_b, min_value)
			)
			mesh.surface_add_vertex(
				Vector3(coordinate_a, coordinate_b, max_value)
			)

	mesh.surface_end()
	_grid_mesh_instance.mesh = mesh
