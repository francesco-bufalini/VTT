extends Node3D

const AOE_PICK_LAYER := 1 << 20
const AOE_COLORS: Array[Color] = [
	Color(1.00, 0.24, 0.10, 1.0),
	Color(1.00, 0.72, 0.08, 1.0),
	Color(0.45, 0.90, 0.18, 1.0),
	Color(0.10, 0.82, 0.52, 1.0),
	Color(0.08, 0.78, 0.92, 1.0),
	Color(0.18, 0.48, 1.00, 1.0),
	Color(0.48, 0.28, 1.00, 1.0),
	Color(0.78, 0.22, 0.92, 1.0),
	Color(1.00, 0.28, 0.62, 1.0),
	Color(0.95, 0.95, 0.95, 1.0),
]
const SpellVFX = preload("res://vtt/spells/spell_vfx.gd")
const WallGeometry = preload("res://vtt/spells/wall_geometry.gd")

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
var _aoe_color_index: int = 0
var _spell_preview: MeshInstance3D
var _spell_preview_start: Vector3 = Vector3.INF
var _spell_preview_end: Vector3 = Vector3.INF
var _spell_preview_shape: String = ""
var _spell_preview_style: String = ""
var _spell_range_preview: MeshInstance3D
var _spell_range_center: Vector3 = Vector3.INF
var _spell_range_radius: float = -1.0
var _suppress_undo_record: bool = false
var _wall_preview_root: Node3D
var _wall_preview_points: Array[Vector3] = []
var _wall_preview_height: float = -1.0
var _wall_preview_thickness: float = -1.0
var _wall_preview_style: String = ""
var _wall_preview_damage_side: int = 0
var _wall_globe_preview_center: Vector3 = Vector3.INF
var _wall_globe_preview_radius: float = -1.0
var _wall_globe_preview_style: String = ""
var _wall_globe_preview_hemisphere: bool = false

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


func _record_undo_state() -> void:
	if _suppress_undo_record:
		return
	var board: Node = get_parent()
	if board != null and board.has_method("push_undo_state"):
		board.call("push_undo_state")


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


func is_aoe_mode() -> bool:
	return aoe_mode


func adjust_aoe_color(step: int) -> void:
	if not _measurement_mode or not aoe_mode or not _dragging:
		return

	_aoe_color_index = posmod(
		_aoe_color_index + step,
		AOE_COLORS.size()
	)
	_update_visuals()


func _current_aoe_color() -> Color:
	return AOE_COLORS[_aoe_color_index]


func begin_measurement() -> bool:
	if not _measurement_mode:
		return false

	var cell: Dictionary = _looked_cell()
	if not bool(cell.get("valid", false)):
		return false

	_start_cell_center = cell.get("center", Vector3.ZERO)
	_start_raw_point = cell.get("raw", _start_cell_center)
	_start_center = _start_cell_center

	if aoe_mode:
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
		add_aoe(
			_start_center,
			_end_center,
			aoe_shape,
			"",
			_current_aoe_color()
		)
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
		_start_center = _snap_point_to_grid_intersection(
			_start_raw_point
		)
		match aoe_shape:
			"sphere":
				_end_center = _snap_point_to_grid_intersection(
					target_raw
				)
			_:
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
			"point": _snap_point_to_grid_intersection(point),
			"in_air": false,
			"normal": normal
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
	var snapped_point: Vector3 = _snap_point_to_grid_intersection(point_in_air)
	if not _grid_contains(snapped_point):
		return {"valid": false}

	return {
		"valid": true,
		"point": snapped_point,
		"in_air": true,
		"normal": Vector3.ZERO
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
		_draw_aoe(
			_aoe_preview,
			_start_center,
			_end_center,
			aoe_shape,
			"",
			_current_aoe_color()
		)
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
	if shape not in ["sphere", "cube", "cone", "line", "flat_square", "cylinder"]:
		return

	cancel_measurement()
	aoe_mode = true
	aoe_shape = shape

func _spell_style_color(style: String) -> Color:
	match style:
		"darkness":
			return Color(0.03, 0.01, 0.07, 1.0)
		"fireball", "burning_hands", "fire_bolt":
			return Color(1.0, 0.24, 0.03, 1.0)
		"lightning_bolt", "witch_bolt", "shocking_grasp", "thunderclap", "thunderwave":
			return Color(0.25, 0.72, 1.0, 1.0)
		"acid_splash", "poison_spray", "ray_of_sickness":
			return Color(0.34, 0.9, 0.13, 1.0)
		"ray_of_frost", "ice_knife", "ice_knife_burst":
			return Color(0.46, 0.9, 1.0, 1.0)
		"mind_sliver", "sleep":
			return Color(0.68, 0.3, 1.0, 1.0)
		"color_spray", "sorcerous_burst", "chromatic_orb":
			return Color(0.86, 0.28, 1.0, 1.0)
		"magic_missile":
			return Color(0.88, 0.86, 1.0, 1.0)
		"fog_cloud":
			return Color(0.74, 0.78, 0.84, 1.0)
		"cloud_of_daggers":
			return Color(0.78, 0.82, 0.9, 1.0)
		"gust_of_wind", "sleet_storm", "ice_storm", "cone_of_cold", "otilukes_freezing_sphere":
			return Color(0.55, 0.9, 1.0, 1.0)
		"web":
			return Color(0.86, 0.86, 0.8, 1.0)
		"fear", "confusion", "hypnotic_pattern", "synaptic_static":
			return Color(0.62, 0.24, 0.9, 1.0)
		"stinking_cloud", "cloudkill":
			return Color(0.44, 0.72, 0.12, 1.0)
		"shatter":
			return Color(0.3, 0.7, 1.0, 1.0)
		"vitriolic_sphere":
			return Color(0.45, 1.0, 0.12, 1.0)
		"insect_plague":
			return Color(0.38, 0.3, 0.08, 1.0)
		"circle_of_death", "blight":
			return Color(0.24, 0.78, 0.34, 1.0)
		"globe_of_invulnerability":
			return Color(0.65, 0.78, 1.0, 1.0)
		"sunbeam":
			return Color(1.0, 0.94, 0.5, 1.0)
		"grease":
			return Color(0.64, 0.56, 0.18, 1.0)
		"cloud_of_daggers":
			return Color(0.82, 0.86, 0.92, 1.0)
		"mind_spike", "synaptic_static", "confusion", "fear", "slow":
			return Color(0.64, 0.26, 0.94, 1.0)
		"scorching_ray":
			return Color(1.0, 0.24, 0.02, 1.0)
		"shatter", "sunbeam", "globe_of_invulnerability":
			return Color(0.68, 0.86, 1.0, 1.0)
		"web":
			return Color(0.86, 0.88, 0.9, 1.0)
		"hypnotic_pattern":
			return Color(0.92, 0.32, 1.0, 1.0)
		"sleet_storm", "ice_storm", "cone_of_cold", "otilukes_freezing_sphere":
			return Color(0.52, 0.9, 1.0, 1.0)
		"stinking_cloud":
			return Color(0.52, 0.68, 0.12, 1.0)
		"blight", "circle_of_death":
			return Color(0.18, 0.05, 0.22, 1.0)
		"vitriolic_sphere":
			return Color(0.48, 0.92, 0.12, 1.0)
		"insect_plague":
			return Color(0.44, 0.34, 0.08, 1.0)
		"chain_lightning":
			return Color(0.42, 0.88, 1.0, 1.0)
		"disintegrate":
			return Color(0.18, 1.0, 0.34, 1.0)
		"wall_of_fire":
			return Color(1.0, 0.22, 0.02, 1.0)
		"wind_wall":
			return Color(0.72, 0.9, 1.0, 1.0)
		"blade_barrier":
			return Color(0.88, 0.92, 1.0, 1.0)
		"wall_of_force":
			return Color(0.48, 0.74, 1.0, 1.0)
		"wall_of_stone":
			return Color(0.42, 0.4, 0.36, 1.0)
		"wall_of_ice":
			return Color(0.56, 0.9, 1.0, 1.0)
		"wall_of_thorns":
			return Color(0.18, 0.58, 0.12, 1.0)
		"prismatic_wall":
			return Color(0.86, 0.3, 1.0, 1.0)
		_:
			return Color(1.0, 0.32, 0.04, 1.0)


func show_spell_preview(
	start: Vector3,
	end: Vector3,
	shape: String,
	style: String = ""
) -> void:
	if shape not in ["sphere", "cube", "cone", "line", "flat_square", "cylinder"]:
		hide_spell_preview()
		return

	if (
		is_instance_valid(_spell_preview)
		and _spell_preview_start.is_equal_approx(start)
		and _spell_preview_end.is_equal_approx(end)
		and _spell_preview_shape == shape
		and _spell_preview_style == style
	):
		_spell_preview.show()
		return

	if not is_instance_valid(_spell_preview):
		_spell_preview = MeshInstance3D.new()
		_spell_preview.name = "SpellAoEPreview"
		add_child(_spell_preview)

	_draw_aoe(_spell_preview, start, end, shape, style)

	var preview_material: StandardMaterial3D = StandardMaterial3D.new()
	preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	preview_material.emission_enabled = true

	var preview_color: Color = _spell_style_color(style)
	preview_color.a = 0.20 if style != "darkness" else 0.24
	preview_material.albedo_color = preview_color
	preview_material.emission = Color(
		preview_color.r,
		preview_color.g,
		preview_color.b,
		1.0
	)
	preview_material.emission_energy_multiplier = (
		0.48 if style in ["fog_cloud", "grease", "web", "stinking_cloud"] else 0.85
	)

	_spell_preview.material_override = preview_material
	_spell_preview_start = start
	_spell_preview_end = end
	_spell_preview_shape = shape
	_spell_preview_style = style
	_spell_preview.show()


func hide_spell_preview() -> void:
	if is_instance_valid(_spell_preview):
		_spell_preview.hide()


func show_spell_range_preview(
	center: Vector3,
	radius_world: float
) -> void:
	var safe_radius: float = maxf(radius_world, cell_size * 0.5)
	if (
		is_instance_valid(_spell_range_preview)
		and _spell_range_center.is_equal_approx(center)
		and is_equal_approx(_spell_range_radius, safe_radius)
	):
		_spell_range_preview.show()
		return

	if not is_instance_valid(_spell_range_preview):
		_spell_range_preview = MeshInstance3D.new()
		_spell_range_preview.name = "SpellRangePreview"
		add_child(_spell_range_preview)

	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = safe_radius
	sphere.height = safe_radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	_spell_range_preview.mesh = sphere
	_spell_range_preview.global_position = center

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.18, 0.58, 1.0, 0.055)
	material.emission_enabled = true
	material.emission = Color(0.08, 0.28, 0.72, 1.0)
	material.emission_energy_multiplier = 0.14
	_spell_range_preview.material_override = material

	_spell_range_center = center
	_spell_range_radius = safe_radius
	_spell_range_preview.show()


func hide_spell_range_preview() -> void:
	if is_instance_valid(_spell_range_preview):
		_spell_range_preview.hide()


func show_transient_aoe(
	start: Vector3,
	end: Vector3,
	shape: String,
	duration_seconds: float = 5.0,
	style: String = ""
) -> void:
	if shape not in ["sphere", "cube", "cone", "line", "flat_square", "cylinder"]:
		return

	var root: Node3D = Node3D.new()
	root.name = "TransientAoE"
	add_child(root)

	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Visual"
	root.add_child(mesh)
	_draw_aoe(mesh, start, end, shape, style)
	SpellVFX.attach(root, start, end, shape, style, cell_size)

	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(duration_seconds, 0.05)
	root.add_child(timer)
	timer.timeout.connect(root.queue_free)
	timer.start()


func show_spell_projectile(
	start: Vector3,
	end: Vector3,
	style: String,
	duration_seconds: float = 5.0
) -> void:
	var root: Node3D = Node3D.new()
	root.name = "TransientSpellProjectile"
	add_child(root)
	SpellVFX.attach_projectile(
		root,
		start,
		end,
		style,
		maxf(duration_seconds, 0.05),
		cell_size
	)


func show_spell_projectile_with_impact(
	start: Vector3,
	end: Vector3,
	projectile_style: String,
	travel_seconds: float,
	impact_shape: String,
	impact_radius_world: float,
	impact_style: String,
	impact_seconds: float = 5.0
) -> void:
	show_spell_projectile(
		start,
		end,
		projectile_style,
		travel_seconds
	)

	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(travel_seconds, 0.05)
	add_child(timer)
	timer.timeout.connect(
		func() -> void:
			show_transient_aoe(
				end,
				end + Vector3.RIGHT * impact_radius_world,
				impact_shape,
				impact_seconds,
				impact_style
			)
			timer.queue_free()
	)
	timer.start()


func show_wall_path_preview(
	points: Array[Vector3],
	height_world: float,
	thickness_world: float,
	style: String,
	damage_side: int = 0
) -> void:
	if points.size() < 2:
		hide_wall_preview()
		return

	if (
		is_instance_valid(_wall_preview_root)
		and _wall_points_equal(_wall_preview_points, points)
		and is_equal_approx(_wall_preview_height, height_world)
		and is_equal_approx(_wall_preview_thickness, thickness_world)
		and _wall_preview_style == style
		and _wall_preview_damage_side == damage_side
	):
		_wall_preview_root.show()
		return

	hide_wall_preview(true)
	_wall_preview_root = Node3D.new()
	_wall_preview_root.name = "SpellWallPreview"
	add_child(_wall_preview_root)
	_build_wall_path_root(
		_wall_preview_root,
		points,
		height_world,
		thickness_world,
		style,
		true,
		damage_side
	)
	_wall_preview_points = points.duplicate()
	_wall_preview_height = height_world
	_wall_preview_thickness = thickness_world
	_wall_preview_style = style
	_wall_preview_damage_side = damage_side


func show_wall_globe_preview(
	center: Vector3,
	radius_world: float,
	style: String,
	hemisphere: bool = false
) -> void:
	var safe_radius: float = maxf(radius_world, cell_size * 0.25)
	if (
		is_instance_valid(_wall_preview_root)
		and _wall_globe_preview_center.is_equal_approx(center)
		and is_equal_approx(_wall_globe_preview_radius, safe_radius)
		and _wall_globe_preview_style == style
		and _wall_globe_preview_hemisphere == hemisphere
	):
		_wall_preview_root.show()
		return

	hide_wall_preview(true)
	_wall_preview_root = Node3D.new()
	_wall_preview_root.name = "SpellWallGlobePreview"
	add_child(_wall_preview_root)
	_build_wall_globe_root(
		_wall_preview_root,
		center,
		safe_radius,
		style,
		hemisphere,
		true
	)
	_wall_globe_preview_center = center
	_wall_globe_preview_radius = safe_radius
	_wall_globe_preview_style = style
	_wall_globe_preview_hemisphere = hemisphere


func hide_wall_preview(free_root: bool = false) -> void:
	if is_instance_valid(_wall_preview_root):
		if free_root:
			_wall_preview_root.queue_free()
			_wall_preview_root = null
		else:
			_wall_preview_root.hide()
	if free_root:
		_wall_preview_points.clear()
		_wall_preview_height = -1.0
		_wall_preview_thickness = -1.0
		_wall_preview_style = ""
		_wall_preview_damage_side = 0
		_wall_globe_preview_center = Vector3.INF
		_wall_globe_preview_radius = -1.0
		_wall_globe_preview_style = ""
		_wall_globe_preview_hemisphere = false


func add_wall_path(
	points: Array[Vector3],
	height_world: float,
	thickness_world: float,
	style: String,
	damage_side: int = 0,
	metadata: Dictionary = {}
) -> void:
	if persistent_aoes.size() >= 256 or points.size() < 2:
		return

	_record_undo_state()
	var data: Dictionary = {
		"shape": "wall_path",
		"points": WallGeometry.serialize_points(points),
		"wall_height": height_world,
		"wall_thickness": thickness_world,
		"style": style,
		"damage_side": damage_side,
		"wall_meta": metadata.duplicate(true)
	}
	persistent_aoes.append(data)

	var root: Node3D = Node3D.new()
	root.name = "PersistentWall"
	add_child(root)
	_build_wall_path_root(
		root,
		points,
		height_world,
		thickness_world,
		style,
		false,
		damage_side
	)
	_aoe_nodes.append(root)


func add_wall_globe(
	center: Vector3,
	radius_world: float,
	style: String,
	hemisphere: bool = false,
	metadata: Dictionary = {}
) -> void:
	if persistent_aoes.size() >= 256:
		return

	_record_undo_state()
	var safe_radius: float = maxf(radius_world, cell_size * 0.25)
	var data: Dictionary = {
		"shape": "wall_globe",
		"center": [center.x, center.y, center.z],
		"radius": safe_radius,
		"hemisphere": hemisphere,
		"style": style,
		"wall_meta": metadata.duplicate(true)
	}
	persistent_aoes.append(data)

	var root: Node3D = Node3D.new()
	root.name = "PersistentWallGlobe"
	add_child(root)
	_build_wall_globe_root(
		root,
		center,
		safe_radius,
		style,
		hemisphere,
		false
	)
	_aoe_nodes.append(root)


func _build_wall_path_root(
	root: Node3D,
	points: Array[Vector3],
	height_world: float,
	thickness_world: float,
	style: String,
	preview: bool,
	damage_side: int
) -> void:
	for index: int in range(1, points.size()):
		var start: Vector3 = points[index - 1]
		var finish: Vector3 = points[index]
		if start.distance_squared_to(finish) < 0.0001:
			continue
		_add_wall_segment(
			root,
			start,
			finish,
			height_world,
			thickness_world,
			style,
			preview
		)
		if not preview:
			_add_wall_segment_pick_area(
				root,
				start,
				finish,
				height_world,
				thickness_world
			)
			SpellVFX.attach_wall_segment(
				root,
				start,
				finish,
				height_world,
				thickness_world,
				style,
				cell_size
			)
		if style == "wall_of_fire" and damage_side != 0:
			_add_wall_damage_band(
				root,
				start,
				finish,
				thickness_world,
				damage_side,
				preview
			)


func _add_wall_segment(
	root: Node3D,
	start: Vector3,
	finish: Vector3,
	height_world: float,
	thickness_world: float,
	style: String,
	preview: bool
) -> void:
	var delta: Vector3 = finish - start
	delta.y = 0.0
	var length: float = delta.length()
	if length < 0.0001:
		return

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "WallSegment"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(
		maxf(thickness_world, cell_size * 0.025),
		maxf(height_world, cell_size * 0.1),
		length
	)
	mesh_instance.mesh = box
	mesh_instance.material_override = _wall_material(style, preview)
	root.add_child(mesh_instance)

	var direction: Vector3 = delta / length
	mesh_instance.global_basis = Basis(
		Quaternion(Vector3.FORWARD, direction)
	)
	mesh_instance.global_position = (
		(start + finish) * 0.5
		+ Vector3.UP * maxf(height_world, cell_size * 0.1) * 0.5
	)


func _add_wall_segment_pick_area(
	root: Node3D,
	start: Vector3,
	finish: Vector3,
	height_world: float,
	thickness_world: float
) -> void:
	var delta: Vector3 = finish - start
	delta.y = 0.0
	var length: float = delta.length()
	if length < 0.0001:
		return

	var area: Area3D = Area3D.new()
	area.name = "WallPickArea"
	area.collision_layer = AOE_PICK_LAYER
	area.collision_mask = 0
	area.set_meta("aoe_root", root)
	root.add_child(area)

	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(
		maxf(thickness_world, cell_size * 0.12),
		maxf(height_world, cell_size * 0.2),
		length
	)
	collision.shape = box
	area.add_child(collision)

	var direction: Vector3 = delta / length
	area.global_basis = Basis(
		Quaternion(Vector3.FORWARD, direction)
	)
	area.global_position = (
		(start + finish) * 0.5
		+ Vector3.UP * maxf(height_world, cell_size * 0.2) * 0.5
	)


func _add_wall_damage_band(
	root: Node3D,
	start: Vector3,
	finish: Vector3,
	thickness_world: float,
	damage_side: int,
	preview: bool
) -> void:
	var delta: Vector3 = finish - start
	delta.y = 0.0
	var length: float = delta.length()
	if length < 0.0001:
		return

	var direction: Vector3 = delta / length
	var normal: Vector3 = Vector3(
		-direction.z,
		0.0,
		direction.x
	) * (1.0 if damage_side >= 0 else -1.0)
	var band_width: float = cell_size * 2.0

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "WallDamageSide"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(
		band_width,
		maxf(cell_size * 0.025, 0.01),
		length
	)
	mesh_instance.mesh = box
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(
		1.0,
		0.18,
		0.02,
		0.10 if preview else 0.065
	)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.12, 0.01, 1.0)
	material.emission_energy_multiplier = 0.25
	mesh_instance.material_override = material
	root.add_child(mesh_instance)

	mesh_instance.global_basis = Basis(
		Quaternion(Vector3.FORWARD, direction)
	)
	mesh_instance.global_position = (
		(start + finish) * 0.5
		+ normal * (band_width * 0.5 + thickness_world * 0.5)
		+ Vector3.UP * maxf(cell_size * 0.012, 0.005)
	)


func _build_wall_globe_root(
	root: Node3D,
	center: Vector3,
	radius_world: float,
	style: String,
	hemisphere: bool,
	preview: bool
) -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "WallGlobe"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius_world
	sphere.height = radius_world if hemisphere else radius_world * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	sphere.is_hemisphere = hemisphere
	mesh_instance.mesh = sphere
	mesh_instance.material_override = _wall_material(style, preview)
	root.add_child(mesh_instance)
	mesh_instance.global_position = center

	if not preview:
		var area: Area3D = Area3D.new()
		area.name = "WallGlobePickArea"
		area.collision_layer = AOE_PICK_LAYER
		area.collision_mask = 0
		area.set_meta("aoe_root", root)
		root.add_child(area)
		var collision: CollisionShape3D = CollisionShape3D.new()
		var sphere_shape: SphereShape3D = SphereShape3D.new()
		sphere_shape.radius = radius_world
		collision.shape = sphere_shape
		area.add_child(collision)
		area.global_position = center
		SpellVFX.attach_wall_globe(
			root,
			center,
			radius_world,
			style,
			hemisphere,
			cell_size
		)


func _wall_material(
	style: String,
	preview: bool
) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var color: Color = _spell_style_color(style)

	var alpha: float = 0.42
	if preview:
		alpha = 0.20
	elif style == "wall_of_force":
		alpha = 0.07
	elif style == "wall_of_stone":
		alpha = 0.92
	elif style == "wind_wall":
		alpha = 0.16
	elif style == "wall_of_ice":
		alpha = 0.52
	elif style == "wall_of_thorns":
		alpha = 0.68
	elif style == "blade_barrier":
		alpha = 0.34
	elif style == "prismatic_wall":
		alpha = 0.48
	elif style == "wall_of_fire":
		alpha = 0.58

	color.a = alpha
	material.albedo_color = color
	if style != "wall_of_stone":
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b, 1.0)
		material.emission_energy_multiplier = 0.55 if preview else 0.9
	return material


func _wall_points_equal(
	a: Array[Vector3],
	b: Array[Vector3]
) -> bool:
	if a.size() != b.size():
		return false
	for index: int in range(a.size()):
		if not a[index].is_equal_approx(b[index]):
			return false
	return true


func add_aoe(
	start: Vector3,
	end: Vector3,
	shape: String,
	style: String = "",
	color: Color = Color(0.0, 0.0, 0.0, -1.0)
) -> void:
	if persistent_aoes.size() >= 256:
		return

	_record_undo_state()
	var selected_color: Color = color
	if style.is_empty() and selected_color.a < 0.0:
		selected_color = _current_aoe_color()

	var data: Dictionary = {
		"start": [start.x, start.y, start.z],
		"end": [end.x, end.y, end.z],
		"shape": shape
	}
	if not style.is_empty():
		data["style"] = style
	elif selected_color.a >= 0.0:
		data["color"] = _serialize_aoe_color(selected_color)
	persistent_aoes.append(data)

	var root := Node3D.new()
	root.name = "PersistentAoE"
	add_child(root)

	var mesh := MeshInstance3D.new()
	mesh.name = "Visual"
	root.add_child(mesh)
	_draw_aoe(mesh, start, end, shape, style, selected_color)
	SpellVFX.attach(root, start, end, shape, style, cell_size)

	_add_aoe_pick_area(root, start, end, shape, style)
	_aoe_nodes.append(root)


func _aoe_line_radius(style: String) -> float:
	# Manual line templates represent a normal 5-ft-wide D&D line. Spell
	# projectiles keep their deliberately thin preview, while true line AoEs
	# retain the width encoded by their spell style.
	if style.is_empty():
		return cell_size * 0.5
	if style == "gust_of_wind":
		return cell_size
	if style in ["lightning_bolt", "sunbeam"]:
		return cell_size * 0.5
	return cell_size * 0.06


func _aoe_geometry(
	start: Vector3,
	end: Vector3,
	shape: String,
	style: String = ""
) -> Dictionary:
	var base_cells: int = _dnd_grid_distance_cells(end - start)
	var reach_world: float = maxf(
		cell_size * 0.5,
		start.distance_to(end)
		if not style.is_empty()
		else float(base_cells) * cell_size
	)
	var direction: Vector3 = (
		(end - start).normalized()
		if not start.is_equal_approx(end)
		else Vector3.FORWARD
	)
	var geometry: Dictionary = {
		"shape": shape,
		"reach": reach_world,
		"position": start,
		"basis": Basis.IDENTITY
	}

	match shape:
		"cube":
			geometry["size"] = Vector3.ONE * reach_world * 2.0

		"cone":
			geometry["radius"] = reach_world * 0.5
			geometry["height"] = reach_world
			geometry["basis"] = Basis(
				Quaternion(Vector3.UP, direction)
			)
			geometry["position"] = (
				start + direction * reach_world * 0.5
			)

		"cylinder":
			var delta: Vector3 = end - start
			var radius: float = maxf(
				absf(delta.x),
				cell_size * 0.5
			)
			var height: float = maxf(
				absf(delta.y),
				cell_size * 0.5
			)
			geometry["radius"] = radius
			geometry["height"] = height
			geometry["position"] = (
				start + Vector3.UP * height * 0.5
			)

		"flat_square":
			var thickness: float = maxf(
				cell_size * 0.035,
				0.01
			)
			geometry["size"] = Vector3(
				reach_world * 2.0,
				thickness,
				reach_world * 2.0
			)
			geometry["position"] = (
				start + Vector3.UP * thickness * 0.5
			)

		"line":
			geometry["radius"] = _aoe_line_radius(style)
			geometry["height"] = reach_world
			geometry["basis"] = Basis(
				Quaternion(Vector3.UP, direction)
			)
			geometry["position"] = (
				start + direction * reach_world * 0.5
			)

		_:
			geometry["radius"] = reach_world

	return geometry


func _draw_aoe(
	node: MeshInstance3D,
	start: Vector3,
	end: Vector3,
	shape: String,
	style: String = "",
	color: Color = Color(0.0, 0.0, 0.0, -1.0)
) -> void:
	var geometry: Dictionary = _aoe_geometry(
		start,
		end,
		shape,
		style
	)

	var geometry_basis: Basis = geometry.get(
		"basis",
		Basis.IDENTITY
	)
	var geometry_position: Vector3 = geometry.get(
		"position",
		start
	)
	node.global_transform = Transform3D(
		geometry_basis,
		geometry_position
	)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	if not style.is_empty():
		var style_color: Color = _spell_style_color(style)
		style_color.a = 0.72 if style == "darkness" else 0.24
		material.albedo_color = style_color
		material.emission_enabled = true
		material.emission = Color(
			style_color.r,
			style_color.g,
			style_color.b,
			1.0
		)
		material.emission_energy_multiplier = (
			0.18 if style in ["fog_cloud", "grease", "web", "stinking_cloud"] else 0.8
		)
	elif color.a >= 0.0:
		var display_color: Color = color
		display_color.a = 0.28
		material.albedo_color = display_color
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b, 1.0)
		material.emission_energy_multiplier = 0.18
	else:
		material.albedo_color = Color(1, 0.3, 0.05, 0.28)

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	match shape:
		"cube", "flat_square":
			var box_mesh: BoxMesh = BoxMesh.new()
			box_mesh.size = geometry.get(
				"size",
				Vector3.ONE * cell_size
			)
			node.mesh = box_mesh

		"cone":
			var cone_mesh: CylinderMesh = CylinderMesh.new()
			cone_mesh.top_radius = float(
				geometry.get("radius", cell_size * 0.5)
			)
			cone_mesh.bottom_radius = 0.0
			cone_mesh.height = float(
				geometry.get("height", cell_size)
			)
			node.mesh = cone_mesh

		"cylinder", "line":
			var cylinder_mesh: CylinderMesh = CylinderMesh.new()
			var radius: float = float(
				geometry.get("radius", cell_size * 0.5)
			)
			cylinder_mesh.top_radius = radius
			cylinder_mesh.bottom_radius = radius
			cylinder_mesh.height = float(
				geometry.get("height", cell_size)
			)
			node.mesh = cylinder_mesh

		_:
			var sphere_mesh: SphereMesh = SphereMesh.new()
			var radius: float = float(
				geometry.get("radius", cell_size * 0.5)
			)
			sphere_mesh.radius = radius
			sphere_mesh.height = radius * 2.0
			node.mesh = sphere_mesh

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

	_record_undo_state()
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
	shape_name: String,
	style: String = ""
) -> void:
	var geometry: Dictionary = _aoe_geometry(
		start,
		end,
		shape_name,
		style
	)

	var area: Area3D = Area3D.new()
	area.name = "PickArea"
	area.collision_layer = AOE_PICK_LAYER
	area.collision_mask = 0
	area.set_meta("aoe_root", root)
	root.add_child(area)
	var geometry_basis: Basis = geometry.get(
		"basis",
		Basis.IDENTITY
	)
	var geometry_position: Vector3 = geometry.get(
		"position",
		start
	)
	area.global_transform = Transform3D(
		geometry_basis,
		geometry_position
	)

	var collision: CollisionShape3D = CollisionShape3D.new()
	area.add_child(collision)

	match shape_name:
		"sphere":
			var sphere: SphereShape3D = SphereShape3D.new()
			sphere.radius = float(
				geometry.get("radius", cell_size * 0.5)
			)
			collision.shape = sphere

		"cube", "flat_square":
			var box: BoxShape3D = BoxShape3D.new()
			box.size = geometry.get(
				"size",
				Vector3.ONE * cell_size
			)
			collision.shape = box

		"cone":
			var radius: float = float(
				geometry.get("radius", cell_size * 0.5)
			)
			var height: float = float(
				geometry.get("height", cell_size)
			)
			var cone: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
			var points: PackedVector3Array = PackedVector3Array()
			points.append(Vector3(0.0, -height * 0.5, 0.0))
			for index: int in range(20):
				var angle: float = TAU * float(index) / 20.0
				points.append(
					Vector3(
						cos(angle) * radius,
						height * 0.5,
						sin(angle) * radius
					)
				)
			cone.points = points
			collision.shape = cone

		"cylinder", "line":
			var cylinder: CylinderShape3D = CylinderShape3D.new()
			cylinder.radius = float(
				geometry.get("radius", cell_size * 0.5)
			)
			cylinder.height = float(
				geometry.get("height", cell_size)
			)
			collision.shape = cylinder

		_:
			var sphere: SphereShape3D = SphereShape3D.new()
			sphere.radius = float(
				geometry.get("radius", cell_size * 0.5)
			)
			collision.shape = sphere


func clear_persistent_aoes() -> void:
	if not persistent_aoes.is_empty():
		_record_undo_state()
	for node in _aoe_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_aoe_nodes.clear()
	persistent_aoes.clear()

func serialize_persistent_aoes() -> Array:
	return persistent_aoes.duplicate(true)


func _serialize_aoe_color(color: Color) -> Dictionary:
	return {
		"r": color.r,
		"g": color.g,
		"b": color.b,
		"a": color.a
	}


func _deserialize_aoe_color(value: Variant) -> Color:
	if value is Dictionary:
		var data: Dictionary = value
		return Color(
			float(data.get("r", 1.0)),
			float(data.get("g", 0.24)),
			float(data.get("b", 0.10)),
			float(data.get("a", 1.0))
		)

	return Color(0.0, 0.0, 0.0, -1.0)


func _valid_serialized_point(value: Variant) -> bool:
	if not value is Array:
		return false
	var point: Array = value
	if point.size() != 3:
		return false
	for coordinate: Variant in point:
		if (
			not (coordinate is float or coordinate is int)
			or not is_finite(float(coordinate))
			or absf(float(coordinate)) > 100000.0
		):
			return false
	return true


func valid_aoes(data: Variant) -> bool:
	if not data is Array or data.size() > 256:
		return false

	for item_value: Variant in data:
		if not item_value is Dictionary:
			return false
		var item: Dictionary = item_value
		var shape: String = String(item.get("shape", ""))

		if shape == "wall_path":
			var points_value: Variant = item.get("points", [])
			if not points_value is Array:
				return false
			var points: Array = points_value
			if points.size() < 2 or points.size() > 128:
				return false
			for point_value: Variant in points:
				if not _valid_serialized_point(point_value):
					return false

			for numeric_key: String in ["wall_height", "wall_thickness"]:
				var number_value: Variant = item.get(numeric_key)
				if not (number_value is float or number_value is int):
					return false
				var number: float = float(number_value)
				if not is_finite(number) or number <= 0.0 or number > 10000.0:
					return false

			if item.has("damage_side"):
				var side_value: Variant = item.get("damage_side")
				if not (side_value is int or side_value is float):
					return false
				if absi(int(side_value)) > 1:
					return false

		elif shape == "wall_globe":
			if not _valid_serialized_point(item.get("center", [])):
				return false
			var radius_value: Variant = item.get("radius")
			if not (radius_value is float or radius_value is int):
				return false
			var radius: float = float(radius_value)
			if not is_finite(radius) or radius <= 0.0 or radius > 10000.0:
				return false
			if item.has("hemisphere") and not item.get("hemisphere") is bool:
				return false

		elif shape in [
			"sphere",
			"cube",
			"cone",
			"line",
			"flat_square",
			"cylinder"
		]:
			for key: String in ["start", "end"]:
				if not _valid_serialized_point(item.get(key, [])):
					return false
		else:
			return false

		if item.has("style") and not item.get("style") is String:
			return false

		if item.has("wall_meta") and not item.get("wall_meta") is Dictionary:
			return false

		if item.has("color"):
			var color_value: Variant = item.get("color")
			if not color_value is Dictionary:
				return false
			var color_data: Dictionary = color_value
			for channel: String in ["r", "g", "b", "a"]:
				var channel_value: Variant = color_data.get(channel)
				if (
					not (channel_value is float or channel_value is int)
					or not is_finite(float(channel_value))
					or float(channel_value) < 0.0
					or float(channel_value) > 1.0
				):
					return false

	return true


func apply_persistent_aoes(data: Array) -> void:
	if not valid_aoes(data):
		return

	_suppress_undo_record = true
	clear_persistent_aoes()

	for item_value: Variant in data:
		var item_data: Dictionary = item_value
		var shape: String = String(item_data.get("shape", "sphere"))
		var style: String = String(item_data.get("style", ""))

		if shape == "wall_path":
			var wall_points: Array[Vector3] = WallGeometry.deserialize_points(
				item_data.get("points", [])
			)
			var wall_meta_value: Variant = item_data.get("wall_meta", {})
			var wall_meta: Dictionary = (
				wall_meta_value
				if wall_meta_value is Dictionary
				else {}
			)
			add_wall_path(
				wall_points,
				float(item_data.get("wall_height", cell_size)),
				float(item_data.get("wall_thickness", cell_size * 0.1)),
				style,
				int(item_data.get("damage_side", 0)),
				wall_meta
			)
			continue

		if shape == "wall_globe":
			var center_data: Array = item_data.get("center", [])
			var globe_meta_value: Variant = item_data.get("wall_meta", {})
			var globe_meta: Dictionary = (
				globe_meta_value
				if globe_meta_value is Dictionary
				else {}
			)
			add_wall_globe(
				Vector3(
					float(center_data[0]),
					float(center_data[1]),
					float(center_data[2])
				),
				float(item_data.get("radius", cell_size)),
				style,
				bool(item_data.get("hemisphere", false)),
				globe_meta
			)
			continue

		var start_data: Array = item_data.get("start", [])
		var end_data: Array = item_data.get("end", [])
		var color: Color = _deserialize_aoe_color(
			item_data.get("color", {})
		)
		add_aoe(
			Vector3(
				float(start_data[0]),
				float(start_data[1]),
				float(start_data[2])
			),
			Vector3(
				float(end_data[0]),
				float(end_data[1]),
				float(end_data[2])
			),
			shape,
			style,
			color
		)

	_suppress_undo_record = false
