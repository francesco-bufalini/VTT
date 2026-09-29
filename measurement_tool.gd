extends Node3D

const AOE_PICK_LAYER := 1 << 20

@export var cell_size: float = 1.0
# Existing template convention: one square = five feet.
@export_range(0.001, 100.0) var meters_per_cell: float = 1.5
@export_flags_3d_physics var collision_mask: int = 1
@export var max_ray_distance: float = 500.0
@export var default_air_depth_cells: float = 2.0

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
var _start_cell_center: Vector3 = Vector3.ZERO
var _start_raw_point: Vector3 = Vector3.ZERO
var _end_center: Vector3 = Vector3.ZERO
var _air_depth_world: float = 8.0

var _line: MeshInstance3D
var _start_cube: MeshInstance3D
var _end_cube: MeshInstance3D
var _distance_canvas: CanvasLayer
var _distance_label: Label


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
		aoe_mode = false
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

	_start_cell_center = cell.get("center", Vector3.ZERO)
	_start_raw_point = cell.get("raw", _start_cell_center)
	_start_center = _start_cell_center

	if aoe_mode and aoe_shape == "sphere":
		_start_center = _snap_point_to_grid_intersection(
			_start_raw_point
		)

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
	if not _dragging:
		return

	if aoe_mode:
		add_aoe(_start_center, _end_center, aoe_shape)
		_dragging = false
		_hide_measurement()
		return

	# A completed ruler measurement remains visible while measurement mode
	# stays active. Starting another valid measurement reuses these visuals,
	# while leaving measurement mode calls cancel_measurement() and clears them.
	_dragging = false
	_update_visuals()


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
				float(extent_value) * sqrt(3.0)
			)

	return maxf(cell_size, 15.0 * cell_size)


func _update_target_from_camera() -> void:
	var cell: Dictionary = _looked_cell()
	if not bool(cell.get("valid", false)):
		return

	var target_center: Vector3 = cell.get("center", Vector3.ZERO)
	var target_raw: Vector3 = cell.get("raw", target_center)

	if aoe_mode:
		match aoe_shape:
			"sphere":
				_start_center = _snap_point_to_grid_intersection(
					_start_raw_point
				)
				_end_center = _snap_point_to_grid_intersection(
					target_raw
				)
			"cone":
				_end_center = target_center
				_start_center = _cone_start_for_target(
					target_center
				)
			_:
				_start_center = _start_cell_center
				_end_center = target_center
	else:
		_start_center = _start_cell_center
		_end_center = target_center

	_update_visuals()


func adjust_spell_target_depth(step_cells: float) -> void:
	_air_depth_world = clampf(
		_air_depth_world + step_cells * cell_size,
		cell_size,
		_maximum_air_depth()
	)


func get_spell_target_point(screen_position: Vector2) -> Dictionary:
	if _camera == null or not is_instance_valid(_camera):
		return {"valid": false}

	var origin: Vector3 = _camera.project_ray_origin(screen_position)
	var direction: Vector3 = _camera.project_ray_normal(screen_position)
	var ray_end: Vector3 = origin + direction * max_ray_distance

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
			"point": _snap_point_to_cell_center(point),
			"in_air": false
		}

	var grid_active: bool = (
		_volumetric_grid != null
		and is_instance_valid(_volumetric_grid)
		and _volumetric_grid.visible
	)
	if not grid_active:
		return {"valid": false}

	var effective_depth: float = _air_depth_world
	if _volumetric_grid.has_method("get_ray_exit_distance"):
		var exit_value: Variant = _volumetric_grid.call(
			"get_ray_exit_distance",
			origin,
			direction
		)
		if exit_value is float:
			var exit_distance: float = maxf(float(exit_value), 0.0)
			effective_depth = minf(
				effective_depth,
				maxf(
					cell_size * 0.5,
					exit_distance - maxf(cell_size * 0.001, 0.0001)
				)
			)

	var point_in_air: Vector3 = origin + direction * effective_depth
	var snapped_point: Vector3 = _snap_point_to_cell_center(point_in_air)
	if not _grid_contains(snapped_point):
		return {"valid": false}

	return {
		"valid": true,
		"point": snapped_point,
		"in_air": true
	}


func _looked_cell() -> Dictionary:
	if _camera == null or not is_instance_valid(_camera):
		return {"valid": false}

	var screen_point: Vector2 = (
		_camera.get_viewport().get_visible_rect().size * 0.5
	)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		screen_point = _camera.get_viewport().get_mouse_position()

	var origin: Vector3 = _camera.project_ray_origin(screen_point)
	var direction: Vector3 = _camera.project_ray_normal(screen_point)
	var ray_end: Vector3 = origin + direction * max_ray_distance
	var grid_active := (
		_volumetric_grid != null
		and is_instance_valid(_volumetric_grid)
		and _volumetric_grid.visible
	)

	# Solid surfaces keep the same behavior as the 2D grid. When the 3D grid
	# is active, however, the snapped cell must also belong to the currently
	# displayed 5x5x5 volume.
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
		var snapped_surface := _snap_point_to_cell_center(point)

		if not grid_active or _grid_contains(snapped_surface):
			return {
				"valid": true,
				"center": snapped_surface,
				"raw": point
			}

	# In volumetric mode the only valid air targets are cells of the visible
	# cube. Depth still selects a layer along the camera ray, but it is clamped
	# to the current cube so an invisible external cell can never be selected.
	if grid_active:
		var effective_depth := _air_depth_world
		if _volumetric_grid.has_method("get_ray_exit_distance"):
			var exit_value: Variant = _volumetric_grid.call(
				"get_ray_exit_distance",
				origin,
				direction
			)
			if exit_value is float:
				var exit_distance := maxf(float(exit_value), 0.0)
				effective_depth = minf(
					effective_depth,
					maxf(
						cell_size * 0.5,
						exit_distance - maxf(cell_size * 0.001, 0.0001)
					)
				)

		var point_in_air := origin + direction * effective_depth
		var snapped_point := _snap_point_to_cell_center(point_in_air)

		if _grid_contains(snapped_point):
			return {
				"valid": true,
				"center": snapped_point,
				"raw": point_in_air
			}

	return {"valid": false}


func _grid_contains(point: Vector3) -> bool:
	if (
		_volumetric_grid == null
		or not is_instance_valid(_volumetric_grid)
		or not _volumetric_grid.has_method("contains_world_point")
	):
		return false

	var contained: Variant = _volumetric_grid.call(
		"contains_world_point",
		point
	)
	return contained is bool and bool(contained)


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


func _snap_point_to_grid_intersection(point: Vector3) -> Vector3:
	return Vector3(
		round(point.x / cell_size) * cell_size,
		round(point.y / cell_size) * cell_size,
		round(point.z / cell_size) * cell_size
	)


func _cone_start_for_target(target_center: Vector3) -> Vector3:
	var delta := target_center - _start_cell_center
	var dx := int(round(absf(delta.x) / maxf(cell_size, 0.0001)))
	var dz := int(round(absf(delta.z) / maxf(cell_size, 0.0001)))

	# Orthogonal cones retain the old centre-of-cell origin.
	if dx == 0 or dz == 0:
		return _start_cell_center

	# A diagonal cone originates from the grid vertex in the direction
	# of travel, matching tabletop placement from the corner of a square.
	return Vector3(
		_start_cell_center.x + signf(delta.x) * cell_size * 0.5,
		_start_cell_center.y,
		_start_cell_center.z + signf(delta.z) * cell_size * 0.5
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

	_distance_canvas = CanvasLayer.new()
	_distance_canvas.name = "MeasurementHUD"
	add_child(_distance_canvas)

	_distance_label = Label.new()
	_distance_label.name = "MeasurementDistance"
	_distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_distance_label.set_anchors_preset(Control.PRESET_CENTER)
	_distance_label.position = Vector2(-150.0, 34.0)
	_distance_label.size = Vector2(300.0, 110.0)
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_distance_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_distance_label.add_theme_font_size_override("font_size", 26)
	_distance_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.82, 0.28, 1.0)
	)
	_distance_label.add_theme_color_override(
		"font_outline_color",
		Color(0.0, 0.0, 0.0, 0.9)
	)
	_distance_label.add_theme_constant_override("outline_size", 6)
	_distance_canvas.add_child(_distance_label)


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
	var base_cells: int = _dnd_grid_distance_cells(delta)
	var display_cells := _display_measurement_cells(base_cells)
	var distance_meters := float(display_cells) * meters_per_cell
	var distance_feet := display_cells * 5
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

	_distance_label.text = (
		"%s: %d %s\n%s m\n%d ft"
		% [
			_measurement_title(),
			display_cells,
			"quadretto" if display_cells == 1 else "quadretti",
			_format_meters(distance_meters),
			distance_feet
		]
	)


func _display_measurement_cells(base_cells: int) -> int:
	if aoe_mode and aoe_shape == "cube":
		# The drag defines centre-to-face distance; D&D names a cube by
		# the length of one complete side.
		return base_cells * 2
	return base_cells


func _measurement_title() -> String:
	if not aoe_mode:
		return "D&D"

	match aoe_shape:
		"sphere":
			return "Raggio"
		"cube":
			return "Lato"
		"cone", "line":
			return "Lunghezza"
		_:
			return "D&D"


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


func _format_meters(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return "%d" % int(round(value))

	return "%.1f" % value


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
	if not _measurement_mode:
		return
	if shape not in ["sphere", "cube", "cone", "line"]:
		return

	cancel_measurement()
	aoe_mode = true
	aoe_shape = shape

func show_transient_aoe(
	start: Vector3,
	end: Vector3,
	shape: String,
	duration_seconds: float = 5.0
) -> void:
	if shape not in ["sphere", "cube", "cone", "line"]:
		return

	var root: Node3D = Node3D.new()
	root.name = "TransientAoE"
	add_child(root)

	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Visual"
	root.add_child(mesh)
	_draw_aoe(mesh, start, end, shape)

	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(duration_seconds, 0.05)
	root.add_child(timer)
	timer.timeout.connect(root.queue_free)
	timer.start()


func add_aoe(start: Vector3, end: Vector3, shape: String) -> void:
	if persistent_aoes.size() >= 256:
		return

	var data := {
		"start": [start.x, start.y, start.z],
		"end": [end.x, end.y, end.z],
		"shape": shape
	}
	persistent_aoes.append(data)

	var root := Node3D.new()
	root.name = "PersistentAoE"
	add_child(root)

	var mesh := MeshInstance3D.new()
	mesh.name = "Visual"
	root.add_child(mesh)
	_draw_aoe(mesh, start, end, shape)

	_add_aoe_pick_area(root, start, end, shape)
	_aoe_nodes.append(root)

func _draw_aoe(
	node: MeshInstance3D,
	start: Vector3,
	end: Vector3,
	shape: String
) -> void:
	var base_cells := _dnd_grid_distance_cells(end - start)
	var reach_world := maxf(
		cell_size * 0.5,
		float(base_cells) * cell_size
	)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 0.3, 0.05, 0.28)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.global_transform = Transform3D(Basis.IDENTITY, start)

	match shape:
		"cube":
			var mesh := BoxMesh.new()
			# The dragged distance is centre-to-face; the displayed D&D measure
			# is therefore the full side, twice this reach.
			mesh.size = Vector3.ONE * reach_world * 2.0
			node.mesh = mesh

		"cone":
			var mesh := CylinderMesh.new()
			mesh.top_radius = reach_world * 0.5
			mesh.bottom_radius = 0.0
			mesh.height = reach_world
			node.mesh = mesh
			var direction := (
				(end - start).normalized()
				if start != end
				else Vector3.FORWARD
			)
			node.global_basis = Basis(
				Quaternion(Vector3.UP, direction)
			)
			node.global_position = (
				start + direction * reach_world * 0.5
			)

		"line":
			var mesh := CylinderMesh.new()
			# Generic D&D line: one square / 5 ft wide.
			mesh.top_radius = cell_size * 0.5
			mesh.bottom_radius = cell_size * 0.5
			mesh.height = reach_world
			node.mesh = mesh
			var direction := (
				(end - start).normalized()
				if start != end
				else Vector3.FORWARD
			)
			node.global_basis = Basis(
				Quaternion(Vector3.UP, direction)
			)
			node.global_position = (
				start + direction * reach_world * 0.5
			)

		_:
			var mesh := SphereMesh.new()
			mesh.radius = reach_world
			mesh.height = reach_world * 2.0
			node.mesh = mesh

	node.material_override = material


func get_aoe_index_at_screen(screen_position: Vector2) -> int:
	if _camera == null or not is_instance_valid(_camera):
		return -1

	var origin: Vector3 = _camera.project_ray_origin(screen_position)
	var direction: Vector3 = _camera.project_ray_normal(screen_position)
	var query: PhysicsRayQueryParameters3D = (
		PhysicsRayQueryParameters3D.create(
			origin,
			origin + direction * max_ray_distance
		)
	)
	query.collision_mask = AOE_PICK_LAYER
	query.collide_with_bodies = false
	query.collide_with_areas = true

	var hit: Dictionary = (
		_camera.get_world_3d().direct_space_state.intersect_ray(query)
	)
	if hit.is_empty():
		return -1

	var area: Area3D = hit.get("collider") as Area3D
	if area == null or not area.has_meta("aoe_root"):
		return -1

	var root_value: Variant = area.get_meta("aoe_root")
	if not is_instance_valid(root_value):
		return -1

	return _aoe_nodes.find(root_value)


func dissolve_aoe(index: int) -> bool:
	if index < 0 or index >= _aoe_nodes.size():
		return false
	if index >= persistent_aoes.size():
		return false

	var root: Node3D = _aoe_nodes[index]
	_aoe_nodes.remove_at(index)
	persistent_aoes.remove_at(index)
	if is_instance_valid(root):
		root.queue_free()
	return true


func remove_aoe_at_screen(screen_position: Vector2) -> bool:
	var index: int = get_aoe_index_at_screen(screen_position)
	return dissolve_aoe(index)


func _add_aoe_pick_area(
	root: Node3D,
	start: Vector3,
	end: Vector3,
	shape_name: String
) -> void:
	var base_cells := _dnd_grid_distance_cells(end - start)
	var reach_world := maxf(
		cell_size * 0.5,
		float(base_cells) * cell_size
	)
	var direction := (
		(end - start).normalized()
		if start != end
		else Vector3.FORWARD
	)

	var area := Area3D.new()
	area.name = "PickArea"
	area.collision_layer = AOE_PICK_LAYER
	area.collision_mask = 0
	area.set_meta("aoe_root", root)
	root.add_child(area)

	var collision := CollisionShape3D.new()
	area.add_child(collision)

	match shape_name:
		"sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = reach_world
			collision.shape = sphere
			area.global_position = start

		"cube":
			var box := BoxShape3D.new()
			box.size = Vector3.ONE * reach_world * 2.0
			collision.shape = box
			area.global_position = start

		"cone":
			var cone := ConvexPolygonShape3D.new()
			var points := PackedVector3Array()
			points.append(Vector3(0.0, -reach_world * 0.5, 0.0))
			for index in range(20):
				var angle := TAU * float(index) / 20.0
				points.append(
					Vector3(
						cos(angle) * reach_world * 0.5,
						reach_world * 0.5,
						sin(angle) * reach_world * 0.5
					)
				)
			cone.points = points
			collision.shape = cone
			area.global_basis = Basis(
				Quaternion(Vector3.UP, direction)
			)
			area.global_position = (
				start + direction * reach_world * 0.5
			)

		"line":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = cell_size * 0.5
			cylinder.height = reach_world
			collision.shape = cylinder
			area.global_basis = Basis(
				Quaternion(Vector3.UP, direction)
			)
			area.global_position = (
				start + direction * reach_world * 0.5
			)


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
