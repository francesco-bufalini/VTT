extends Node3D

@export var cell_size: float = 1.0
# Existing template convention: one square = five feet.
@export_range(0.001, 100.0) var meters_per_cell: float = 1.524
@export_flags_3d_physics var collision_mask: int = 1
@export var max_ray_distance: float = 500.0
@export var default_air_depth_cells: float = 8.0

var aoe_shape: String = "sphere"
var aoe_mode := false
var persistent_aoes: Array = []
var _aoe_nodes: Array[Node3D] = []
var _aoe_preview: MeshInstance3D

var _camera: Camera3D = null
var _volumetric_grid: Node3D = null
var _measurement_mode: bool = false
var _dragging: bool = false
var _start_center: Vector3 = Vector3.ZERO
var _end_center: Vector3 = Vector3.ZERO
var _air_depth_world: float = 8.0

var _line: MeshInstance3D
var _start_cube: MeshInstance3D
var _end_cube: MeshInstance3D
var _distance_label: Label3D


func meters_to_world(meters: float) -> float:
	return meters / meters_per_cell * cell_size


func world_to_meters(distance: float) -> float:
	return distance / cell_size * meters_per_cell


func _ready() -> void:
	_air_depth_world = default_air_depth_cells * cell_size
	_build_visuals()
	_hide_measurement()


func _process(_delta: float) -> void:
	if _measurement_mode and _dragging:
		_update_target_from_camera()


func set_camera(new_camera: Camera3D) -> void:
	_camera = new_camera


func set_volumetric_grid(grid: Node3D) -> void:
	_volumetric_grid = grid


func set_measurement_mode(enabled: bool) -> void:
	_measurement_mode = enabled

	if not enabled:
		cancel_measurement()


func toggle_measurement_mode() -> bool:
	set_measurement_mode(not _measurement_mode)
	return _measurement_mode


func is_measurement_mode() -> bool:
	return _measurement_mode


func begin_measurement() -> bool:
	if not _measurement_mode:
		return false

	var cell: Dictionary = _looked_cell()
	if not bool(cell.get("valid", false)):
		return false

	_start_center = cell.get("center", Vector3.ZERO)
	_end_center = _start_center

	if _camera != null and is_instance_valid(_camera):
		var start_distance: float = _camera.global_position.distance_to(
			_start_center
		)
		var maximum_depth: float = _maximum_air_depth()
		_air_depth_world = clampf(
			start_distance,
			cell_size,
			maximum_depth
		)

	_dragging = true
	_update_visuals()
	return true


func end_measurement() -> void:
	if _dragging and aoe_mode:
		add_aoe(_start_center, _end_center, aoe_shape)
	_dragging = false
	_hide_measurement()


func cancel_measurement() -> void:
	_dragging = false
	_hide_measurement()


func is_dragging() -> bool:
	return _dragging


func adjust_air_depth(step_cells: float) -> void:
	if not _measurement_mode:
		return

	_air_depth_world = clampf(
		_air_depth_world + step_cells * cell_size,
		cell_size,
		_maximum_air_depth()
	)

	if _dragging:
		_update_target_from_camera()


func _maximum_air_depth() -> float:
	if (
		_volumetric_grid != null
		and is_instance_valid(_volumetric_grid)
		and _volumetric_grid.has_method("get_half_extent_world")
	):
		var extent_value: Variant = _volumetric_grid.call(
            "get_half_extent_world"
		)

		if extent_value is float:
			return maxf(
				cell_size,
				float(extent_value) * 0.95
			)

	return maxf(cell_size, 15.0 * cell_size)


func _update_target_from_camera() -> void:
	var cell: Dictionary = _looked_cell()
	if not bool(cell.get("valid", false)):
		return

	_end_center = cell.get("center", Vector3.ZERO)
	_update_visuals()


func _looked_cell() -> Dictionary:
	if _camera == null or not is_instance_valid(_camera):
		return {"valid": false}

	var screen_center: Vector2 = _camera.get_viewport().get_visible_rect().size * 0.5
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		screen_center = _camera.get_viewport().get_mouse_position()
	var origin: Vector3 = _camera.project_ray_origin(screen_center)
	var direction: Vector3 = _camera.project_ray_normal(screen_center)
	var ray_end: Vector3 = origin + direction * max_ray_distance

	# Le superfici reali hanno priorità.
	var query: PhysicsRayQueryParameters3D = (
		PhysicsRayQueryParameters3D.create(origin, ray_end)
	)
	query.collision_mask = collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hit: Dictionary = (
		_camera.get_world_3d().direct_space_state.intersect_ray(query)
	)

	if not hit.is_empty():
		var point: Vector3 = hit.get("position", Vector3.ZERO)
		var normal: Vector3 = hit.get("normal", Vector3.UP)
		point += (
			normal.normalized()
			* maxf(cell_size * 0.001, 0.0001)
		)

		return {
			"valid": true,
			"center": _snap_point_to_cell_center(point)
		}

	# Nel vuoto, se la griglia 3D è visibile, usiamo una profondità
	# lungo il raggio della camera. La rotellina la modifica durante il drag.
	if (
		_volumetric_grid != null
		and is_instance_valid(_volumetric_grid)
		and _volumetric_grid.visible
	):
		var point_in_air: Vector3 = (
			origin + direction * _air_depth_world
		)
		var snapped_point: Vector3 = _snap_point_to_cell_center(
			point_in_air
		)

		if _volumetric_grid.has_method("contains_world_point"):
			var contained: Variant = _volumetric_grid.call(
				"contains_world_point",
				snapped_point
			)

			if contained is bool and not bool(contained):
				return {"valid": false}

		return {
			"valid": true,
			"center": snapped_point
		}

	return {"valid": false}


func _snap_point_to_cell_center(point: Vector3) -> Vector3:
	return Vector3(
		_snap_axis_to_center(point.x),
		_snap_axis_to_center(point.y),
		_snap_axis_to_center(point.z)
	)


func _snap_axis_to_center(value: float) -> float:
	return (
		floor(value / cell_size) * cell_size
		+ cell_size * 0.5
	)


func _build_visuals() -> void:
	var line_material: StandardMaterial3D = StandardMaterial3D.new()
	line_material.albedo_color = Color(1.0, 0.63, 0.08, 1.0)
	line_material.emission_enabled = true
	line_material.emission = Color(1.0, 0.32, 0.02, 1.0)
	line_material.emission_energy_multiplier = 1.4
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var line_mesh: CylinderMesh = CylinderMesh.new()
	line_mesh.top_radius = 0.035 * cell_size
	line_mesh.bottom_radius = 0.035 * cell_size
	line_mesh.height = 1.0
	line_mesh.radial_segments = 12
	line_mesh.material = line_material

	_line = MeshInstance3D.new()
	_line.name = "MeasurementVector"
	_line.mesh = line_mesh
	add_child(_line)

	var cube_material: StandardMaterial3D = StandardMaterial3D.new()
	cube_material.albedo_color = Color(1.0, 0.55, 0.08, 0.22)
	cube_material.emission_enabled = true
	cube_material.emission = Color(1.0, 0.25, 0.01, 1.0)
	cube_material.emission_energy_multiplier = 0.45
	cube_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cube_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var cube_mesh: BoxMesh = BoxMesh.new()
	cube_mesh.size = Vector3.ONE * cell_size * 0.92
	cube_mesh.material = cube_material

	_start_cube = MeshInstance3D.new()
	_start_cube.name = "MeasurementStartCell"
	_start_cube.mesh = cube_mesh
	add_child(_start_cube)

	_end_cube = MeshInstance3D.new()
	_end_cube.name = "MeasurementEndCell"
	_end_cube.mesh = cube_mesh
	add_child(_end_cube)

	_distance_label = Label3D.new()
	_distance_label.name = "MeasurementDistance"
	_distance_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_distance_label.no_depth_test = true
	_distance_label.font_size = 38
	_distance_label.outline_size = 10
	_distance_label.modulate = Color(1.0, 0.82, 0.28, 1.0)
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_distance_label)


func _update_visuals() -> void:
	if aoe_mode:
		if not is_instance_valid(_aoe_preview):
			_aoe_preview = MeshInstance3D.new()
			add_child(_aoe_preview)
		_draw_aoe(_aoe_preview, _start_center, _end_center, aoe_shape)
		_aoe_preview.show()
	_start_cube.visible = true
	_end_cube.visible = true
	_distance_label.visible = true

	_start_cube.global_position = _start_center
	_end_cube.global_position = _end_center

	var delta: Vector3 = _end_center - _start_center
	var length_world: float = delta.length()
	var length_cells: float = (
		length_world / maxf(cell_size, 0.0001)
	)
	var dnd_cells: int = _dnd_grid_distance_cells(delta)
	var midpoint: Vector3 = (
		(_start_center + _end_center) * 0.5
	)

	if length_world > 0.0001:
		_line.visible = true
		_line.global_position = midpoint
		_line.global_basis = Basis(
			Quaternion(Vector3.UP, delta.normalized())
		)
		_line.scale = Vector3(1.0, length_world, 1.0)
	else:
		_line.visible = false

	_distance_label.global_position = (
		midpoint + Vector3.UP * (0.22 * cell_size)
	)
	_distance_label.text = (
        "D&D: %d %s\nEffettiva: %s"
		% [
			dnd_cells,
			"quadretto" if dnd_cells == 1 else "quadretti",
			_format_exact_distance(length_cells)
		]
	)


func _dnd_grid_distance_cells(delta: Vector3) -> int:
	# Regola 5-10-5:
	# una diagonale costa 1 quadretto, la successiva 2, poi 1, poi 2...
	#
	# In 3D ogni passo che cambia almeno due assi è un passo diagonale.
	# Il numero di passi diagonali è il secondo valore più grande tra
	# |dx|, |dy| e |dz|.
	var dx: int = int(
		round(absf(delta.x) / maxf(cell_size, 0.0001))
	)
	var dy: int = int(
		round(absf(delta.y) / maxf(cell_size, 0.0001))
	)
	var dz: int = int(
		round(absf(delta.z) / maxf(cell_size, 0.0001))
	)

	var largest: int = maxi(dx, maxi(dy, dz))
	var smallest: int = mini(dx, mini(dy, dz))
	var middle: int = dx + dy + dz - largest - smallest

	return largest + int(floor(float(middle) * 0.5))


func _format_exact_distance(value: float) -> String:
	var unit: String = (
        "quadretto"
		if is_equal_approx(value, 1.0)
		else "quadretti"
	)

	if is_equal_approx(value, round(value)):
		return "%d %s" % [int(round(value)), unit]

	return "%.2f %s" % [value, unit]


func _hide_measurement() -> void:
	if is_instance_valid(_aoe_preview):
		_aoe_preview.hide()
	if _line != null:
		_line.visible = false
	if _start_cube != null:
		_start_cube.visible = false
	if _end_cube != null:
		_end_cube.visible = false
	if _distance_label != null:
		_distance_label.visible = false


func set_aoe_mode(shape: String) -> void:
	cancel_measurement()
	aoe_mode = true
	aoe_shape = shape
	set_measurement_mode(true)

func add_aoe(start: Vector3, end: Vector3, shape: String) -> void:
	if persistent_aoes.size() >= 256:
		return
	var data := {"start": [start.x,start.y,start.z], "end": [end.x,end.y,end.z], "shape": shape}
	persistent_aoes.append(data)
	var mesh := MeshInstance3D.new()
	add_child(mesh)
	_draw_aoe(mesh, start, end, shape)
	_aoe_nodes.append(mesh)

func _draw_aoe(node: MeshInstance3D, start: Vector3, end: Vector3, shape: String) -> void:
	var radius := maxf(cell_size * 0.5, start.distance_to(end))
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 0.3, 0.05, 0.28)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.global_transform = Transform3D(Basis.IDENTITY, start)
	match shape:
		"cube":
			var mesh := BoxMesh.new()
			mesh.size = Vector3.ONE * radius * 2.0
			node.mesh = mesh
		"cone", "line":
			var mesh := CylinderMesh.new()
			mesh.top_radius = radius * 0.5 if shape == "cone" else cell_size * 0.15
			mesh.bottom_radius = 0.0 if shape == "cone" else cell_size * 0.15
			mesh.height = radius
			node.mesh = mesh
			var direction := (end - start).normalized() if start != end else Vector3.FORWARD
			node.global_basis = Basis(Quaternion(Vector3.UP, direction))
			node.global_position = start + direction * radius * 0.5
		_:
			var mesh := SphereMesh.new()
			mesh.radius = radius
			mesh.height = radius * 2.0
			node.mesh = mesh
	node.material_override = material

func clear_persistent_aoes() -> void:
	for node in _aoe_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_aoe_nodes.clear()
	persistent_aoes.clear()

func serialize_persistent_aoes() -> Array:
	return persistent_aoes.duplicate(true)

func valid_aoes(data: Variant) -> bool:
	if not data is Array or data.size() > 256:
		return false
	for item in data:
		if not item is Dictionary or item.get("shape", "") not in ["sphere", "cube", "cone", "line"]:
			return false
		for key in ["start", "end"]:
			var point: Variant = item.get(key)
			if not point is Array or point.size() != 3:
				return false
			for value in point:
				if not (value is float or value is int) or not is_finite(float(value)) or absf(float(value)) > 100000:
					return false
	return true

func apply_persistent_aoes(data: Array) -> void:
	if not valid_aoes(data):
		return
	clear_persistent_aoes()
	for item in data:
		add_aoe(Vector3(item.start[0],item.start[1],item.start[2]), Vector3(item.end[0],item.end[1],item.end[2]), item.shape)
