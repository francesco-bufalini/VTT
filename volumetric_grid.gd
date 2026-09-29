extends Node3D

@export var cell_size: float = 1.0
@export_range(1, 200) var radius_cells: int = 30
@export_range(1, 20) var vertical_offset_cells: int = 2

var _camera: Camera3D = null
var _upper_grid: MeshInstance3D = null
var _lower_grid: MeshInstance3D = null
var _last_follow_position: Vector3 = Vector3.INF
var _cells_per_side: int = 61
var _half_extent_world: float = 30.0


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
	# Manteniamo un volume logico per il targeting 3D anche se la
	# rappresentazione visiva ora usa soltanto due piani orizzontali.
	return _half_extent_world


func contains_world_point(point: Vector3) -> bool:
	# Compatibilità con MeasurementTool: la griglia visiva non deve limitare
	# il targeting soltanto ai due piani disegnati.
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

	# I piani restano allineati alla griglia sul piano X/Z, ma seguono
	# continuamente l'altezza della camera. In questo modo sono sempre
	# esattamente due celle sopra e due celle sotto la camera.
	var follow_position := Vector3(
		_snap_axis_to_cell_center(camera_position.x),
		camera_position.y,
		_snap_axis_to_cell_center(camera_position.z)
	)

	if follow_position != _last_follow_position:
		global_position = follow_position
		_last_follow_position = follow_position


func _snap_axis_to_cell_center(value: float) -> float:
	var safe_cell_size := maxf(cell_size, 0.001)
	return (
		floor(value / safe_cell_size) * safe_cell_size
		+ safe_cell_size * 0.5
	)


func _rebuild() -> void:
	if _upper_grid != null and is_instance_valid(_upper_grid):
		_upper_grid.queue_free()
	if _lower_grid != null and is_instance_valid(_lower_grid):
		_lower_grid.queue_free()

	var safe_cell_size := maxf(cell_size, 0.001)
	var safe_radius := maxi(radius_cells, 1)
	_cells_per_side = safe_radius * 2 + 1
	_half_extent_world = float(safe_radius) * safe_cell_size

	var visual_half_extent := (
		float(_cells_per_side) * safe_cell_size * 0.5
	)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.75, 1.0, 0.22)
	material.emission_enabled = true
	material.emission = Color(0.04, 0.22, 0.38, 1.0)
	material.emission_energy_multiplier = 0.42
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)

	var min_value := -visual_half_extent
	var max_value := visual_half_extent

	# 61 x 61 celle con radius_cells = 30:
	# 62 linee parallele a X e 62 parallele a Z.
	for index in range(_cells_per_side + 1):
		var coordinate := (
			min_value + float(index) * safe_cell_size
		)

		mesh.surface_add_vertex(Vector3(min_value, 0.0, coordinate))
		mesh.surface_add_vertex(Vector3(max_value, 0.0, coordinate))

		mesh.surface_add_vertex(Vector3(coordinate, 0.0, min_value))
		mesh.surface_add_vertex(Vector3(coordinate, 0.0, max_value))

	mesh.surface_end()

	var vertical_offset := (
		float(maxi(vertical_offset_cells, 1)) * safe_cell_size
	)

	_upper_grid = MeshInstance3D.new()
	_upper_grid.name = "UpperGridPlane"
	_upper_grid.mesh = mesh
	_upper_grid.position.y = vertical_offset
	add_child(_upper_grid)

	_lower_grid = MeshInstance3D.new()
	_lower_grid.name = "LowerGridPlane"
	_lower_grid.mesh = mesh
	_lower_grid.position.y = -vertical_offset
	add_child(_lower_grid)

	_last_follow_position = Vector3.INF
	_update_position_around_camera()
