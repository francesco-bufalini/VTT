extends Node3D

const AoeSnapshotValidator = preload("res://vtt/aoe_snapshot_validator.gd")

const TopDownElevationLevels = preload("res://vtt/top_down_elevation_levels.gd")

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
const DamageAreaParticles = preload("res://vtt/spells/damage_area_particles.gd")
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
var _movable_aoe_drag_index: int = -1
var _movable_aoe_drag_root_origin: Vector3 = Vector3.ZERO
var _movable_aoe_drag_delta: Vector3 = Vector3.ZERO
var _movable_aoe_drag_was_captured: bool = false
var _spell_preview: MeshInstance3D
var _spell_preview_start: Vector3 = Vector3.INF
var _spell_preview_end: Vector3 = Vector3.INF
var _spell_preview_shape: String = ""
var _spell_preview_style: String = ""
var _spell_preview_line_width: float = -1.0
var _spell_fixed_previews: Array[MeshInstance3D] = []
var _transient_spell_aoes: Array[Dictionary] = []
var _held_spell_aoes: Array[Node3D] = []
var _spell_affected_override_active: bool = false
var _spell_affected_override: Array[Node3D] = []
var _spell_affected_geometry_override: Dictionary = {}
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
var _affected_tokens_signature: String = ""

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


func _token_occupied_cell_centers(token: Node3D) -> Array[Vector3]:
	var centers: Array[Vector3] = []
	if token == null or not is_instance_valid(token):
		return centers

	var footprint: float = (
		float(token.call("get_footprint_cells"))
		if token.has_method("get_footprint_cells")
		else 1.0
	)
	var height_cells: float = maxf(
		float(token.get("token_height_cells")),
		0.1
	)
	var horizontal_count: int = maxi(1, int(ceil(footprint)))
	var vertical_count: int = maxi(1, int(ceil(height_cells)))
	var horizontal_start: float = (
		-float(horizontal_count - 1) * cell_size * 0.5
	)
	var bottom_y: float = (
		token.global_position.y
		- height_cells * cell_size * 0.5
	)

	for y_index: int in range(vertical_count):
		var world_y: float = (
			bottom_y + (float(y_index) + 0.5) * cell_size
		)
		for z_index: int in range(horizontal_count):
			for x_index: int in range(horizontal_count):
				centers.append(
					Vector3(
						token.global_position.x
						+ horizontal_start
						+ float(x_index) * cell_size,
						world_y,
						token.global_position.z
						+ horizontal_start
						+ float(z_index) * cell_size
					)
				)
	return centers


func _distance_to_segment(
	point: Vector3,
	start: Vector3,
	end: Vector3
) -> float:
	var segment: Vector3 = end - start
	var length_squared: float = segment.length_squared()
	if length_squared < 0.000001:
		return point.distance_to(start)
	var t: float = clampf(
		(point - start).dot(segment) / length_squared,
		0.0,
		1.0
	)
	return point.distance_to(start + segment * t)


func _cell_intersects_aoe(
	point: Vector3,
	start: Vector3,
	end: Vector3,
	shape: String,
	style: String = "",
	line_width_world: float = -1.0
) -> bool:
	var geometry: Dictionary = _aoe_geometry(
		start,
		end,
		shape,
		style,
		line_width_world
	)
	var tolerance: float = cell_size * 0.52

	match shape:
		"sphere":
			return point.distance_to(start) <= (
				float(geometry.get("radius", cell_size * 0.5))
				+ tolerance
			)

		"cube":
			var size: Vector3 = geometry.get(
				"size",
				Vector3.ONE * cell_size
			)
			var delta: Vector3 = point - start
			return (
				absf(delta.x) <= size.x * 0.5 + tolerance
				and absf(delta.y) <= size.y * 0.5 + tolerance
				and absf(delta.z) <= size.z * 0.5 + tolerance
			)

		"flat_square":
			var square_size: Vector3 = geometry.get(
				"size",
				Vector3.ONE * cell_size
			)
			var square_delta: Vector3 = point - start
			return (
				absf(square_delta.x) <= square_size.x * 0.5 + tolerance
				and absf(square_delta.z) <= square_size.z * 0.5 + tolerance
				and absf(square_delta.y) <= tolerance
			)

		"cylinder":
			var radius: float = float(
				geometry.get("radius", cell_size * 0.5)
			)
			var height: float = float(
				geometry.get("height", cell_size)
			)
			var delta: Vector3 = point - start
			return (
				Vector2(delta.x, delta.z).length() <= radius + tolerance
				and delta.y >= -tolerance
				and delta.y <= height + tolerance
			)

		"line":
			var line_radius: float = float(
				geometry.get("radius", cell_size * 0.5)
			)
			return _distance_to_segment(point, start, end) <= (
				line_radius + tolerance
			)

		"cone":
			var axis: Vector3 = end - start
			var length: float = axis.length()
			if length < 0.0001:
				return false
			var direction: Vector3 = axis / length
			var delta: Vector3 = point - start
			var along: float = delta.dot(direction)
			if along < -tolerance or along > length + tolerance:
				return false
			var radial: float = (
				delta - direction * clampf(along, 0.0, length)
			).length()
			var end_radius: float = float(
				geometry.get("radius", length * 0.5)
			)
			var allowed_radius: float = (
				end_radius * clampf(along / length, 0.0, 1.0)
			)
			return radial <= allowed_radius + tolerance

	return false


func _persistent_aoe_hits_token(
	data: Dictionary,
	token: Node3D
) -> bool:
	var start_data: Array = data.get("start", [])
	var end_data: Array = data.get("end", [])
	if start_data.size() != 3 or end_data.size() != 3:
		return false
	var start: Vector3 = Vector3(
		float(start_data[0]),
		float(start_data[1]),
		float(start_data[2])
	)
	var end: Vector3 = Vector3(
		float(end_data[0]),
		float(end_data[1]),
		float(end_data[2])
	)
	var shape: String = String(data.get("shape", "sphere"))
	var style: String = String(data.get("style", ""))
	var line_width_world: float = float(
		data.get("line_width_world", -1.0)
	)
	for center: Vector3 in _token_occupied_cell_centers(token):
		if _cell_intersects_aoe(
			center,
			start,
			end,
			shape,
			style,
			line_width_world
		):
			return true
	return false


func _spell_affected_override_signature() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for token: Node3D in _spell_affected_override:
		if token != null and is_instance_valid(token):
			parts.append(str(token.get_instance_id()))
	return ",".join(parts)


func _spell_affected_geometry_signature() -> String:
	if _spell_affected_geometry_override.is_empty():
		return ""
	return "%s|%s|%s|%s|%.4f" % [
		str(_spell_affected_geometry_override.get("start", Vector3.ZERO)),
		str(_spell_affected_geometry_override.get("end", Vector3.ZERO)),
		String(_spell_affected_geometry_override.get("shape", "")),
		String(_spell_affected_geometry_override.get("style", "")),
		float(_spell_affected_geometry_override.get("line_width_world", -1.0))
	]


func set_spell_affected_geometry(
	start: Vector3,
	end: Vector3,
	shape: String,
	style: String = "",
	line_width_world: float = -1.0,
	active: bool = true
) -> void:
	_spell_affected_override_active = active
	_spell_affected_override.clear()
	if active:
		_spell_affected_geometry_override = {
			"start": start,
			"end": end,
			"shape": shape,
			"style": style,
			"line_width_world": line_width_world
		}
	else:
		_spell_affected_geometry_override.clear()
	_affected_tokens_signature = ""
	_refresh_affected_token_highlight()


func set_spell_affected_token_highlight(
	tokens: Array,
	active: bool = true
) -> void:
	var resolved: Array[Node3D] = []
	for value: Variant in tokens:
		if not value is Node3D:
			continue
		var token: Node3D = value as Node3D
		if (
			token != null
			and is_instance_valid(token)
			and token.is_in_group("dnd_token")
			and not (token in resolved)
		):
			resolved.append(token)

	var same: bool = (
		_spell_affected_geometry_override.is_empty()
		and active == _spell_affected_override_active
		and resolved.size() == _spell_affected_override.size()
	)
	if same:
		for index: int in range(resolved.size()):
			if resolved[index] != _spell_affected_override[index]:
				same = false
				break
	if same:
		return

	_spell_affected_override_active = active
	_spell_affected_override = resolved
	_spell_affected_geometry_override.clear()
	_affected_tokens_signature = ""
	# Apply spell-target changes immediately. Waiting for _process() left the
	# previous red grid visible for one or more frames after Esc/cleanup.
	_refresh_affected_token_highlight()


func _cell_intersects_spell_geometry(
	center: Vector3,
	start: Vector3,
	end: Vector3,
	shape: String,
	style: String = "",
	line_width_world: float = -1.0
) -> bool:
	if shape == "sphere":
		var geometry: Dictionary = _aoe_geometry(
			start,
			end,
			shape,
			style,
			line_width_world
		)
		var radius: float = float(
			geometry.get("radius", cell_size * 0.5)
		)
		var half_cell: float = cell_size * 0.5
		var delta: Vector3 = Vector3(
			absf(center.x - start.x),
			absf(center.y - start.y),
			absf(center.z - start.z)
		)
		var closest_delta: Vector3 = Vector3(
			maxf(delta.x - half_cell, 0.0),
			maxf(delta.y - half_cell, 0.0),
			maxf(delta.z - half_cell, 0.0)
		)
		return closest_delta.length_squared() <= radius * radius

	return _cell_intersects_aoe(
		center,
		start,
		end,
		shape,
		style,
		line_width_world
	)


func spell_geometry_affected_tokens(
	start: Vector3,
	end: Vector3,
	shape: String,
	style: String = "",
	line_width_world: float = -1.0
) -> Array[Node3D]:
	var affected: Array[Node3D] = []
	if shape not in [
		"sphere", "cube", "cone", "line", "flat_square", "cylinder"
	]:
		return affected

	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if not node is Node3D:
			continue
		var token: Node3D = node as Node3D
		if token == null or not is_instance_valid(token):
			continue
		for center: Vector3 in _token_occupied_cell_centers(token):
			if _cell_intersects_spell_geometry(
				center,
				start,
				end,
				shape,
				style,
				line_width_world
			):
				affected.append(token)
				break
	return affected


func _token_touched_by_current_geometry(token: Node3D) -> bool:
	for data_value: Variant in persistent_aoes:
		if data_value is Dictionary:
			if _persistent_aoe_hits_token(
				data_value as Dictionary,
				token
			):
				return true

	for data_value: Variant in _transient_spell_aoes:
		if data_value is Dictionary:
			if _persistent_aoe_hits_token(
				data_value as Dictionary,
				token
			):
				return true

	if (
		is_instance_valid(_spell_preview)
		and _spell_preview.visible
		and _spell_preview_shape in [
			"sphere", "cube", "cone", "line", "flat_square", "cylinder"
		]
	):
		for center: Vector3 in _token_occupied_cell_centers(token):
			if _cell_intersects_aoe(
				center,
				_spell_preview_start,
				_spell_preview_end,
				_spell_preview_shape,
				_spell_preview_style,
				_spell_preview_line_width
			):
				return true

	if aoe_mode and _dragging:
		for center: Vector3 in _token_occupied_cell_centers(token):
			if _cell_intersects_aoe(
				center,
				_start_center,
				_end_center,
				aoe_shape,
				"",
				-1.0
			):
				return true

	if (
		_measurement_mode
		and not aoe_mode
		and is_instance_valid(_line)
		and _line.visible
	):
		for center: Vector3 in _token_occupied_cell_centers(token):
			if _distance_to_segment(
				center,
				_start_center,
				_end_center
			) <= cell_size * 0.55:
				return true

	return false


func _refresh_affected_token_highlight() -> void:
	var board: Node = get_parent()
	if board == null or not board.has_method(
		"set_affected_token_highlight"
	):
		return

	var tokens: Array[Node] = get_tree().get_nodes_in_group("dnd_token")
	var signature_parts: PackedStringArray = PackedStringArray()
	signature_parts.append(JSON.stringify(persistent_aoes))
	signature_parts.append(JSON.stringify(_transient_spell_aoes))
	signature_parts.append(
		"%s|%s|%s" % [
			str(_spell_affected_override_active),
			_spell_affected_override_signature(),
			_spell_affected_geometry_signature()
		]
	)
	signature_parts.append(
		"%s|%s|%s|%s|%s|%s|%s" % [
		str(_measurement_mode),
		str(aoe_mode),
		str(_dragging),
		str(_start_center),
		str(_end_center),
		aoe_shape,
		str(
			is_instance_valid(_line)
			and _line.visible
		)
		]
	)
	signature_parts.append(
		"%s|%s|%s|%s|%s|%.4f" % [
		str(
			is_instance_valid(_spell_preview)
			and _spell_preview.visible
		),
		str(_spell_preview_start),
		str(_spell_preview_end),
		_spell_preview_shape,
		_spell_preview_style,
		_spell_preview_line_width
		]
	)
	for node: Node in tokens:
		if not node is Node3D:
			continue
		var token: Node3D = node as Node3D
		signature_parts.append(
			"%s|%s|%.3f|%.3f" % [
				str(token.get_instance_id()),
				str(token.global_position),
				float(
					token.call("get_footprint_cells")
					if token.has_method("get_footprint_cells")
					else 1.0
				),
				maxf(float(token.get("token_height_cells")), 0.1)
			]
		)

	var signature: String = ";".join(signature_parts)
	if signature == _affected_tokens_signature:
		return
	_affected_tokens_signature = signature

	var affected: Array = []
	if _spell_affected_override_active:
		if not _spell_affected_geometry_override.is_empty():
			var geometry_targets: Array[Node3D] = spell_geometry_affected_tokens(
				_spell_affected_geometry_override.get("start", Vector3.ZERO),
				_spell_affected_geometry_override.get("end", Vector3.ZERO),
				String(_spell_affected_geometry_override.get("shape", "sphere")),
				String(_spell_affected_geometry_override.get("style", "")),
				float(_spell_affected_geometry_override.get("line_width_world", -1.0))
			)
			for token: Node3D in geometry_targets:
				affected.append(token)
		else:
			for token: Node3D in _spell_affected_override:
				if token != null and is_instance_valid(token):
					affected.append(token)
	else:
		for node: Node in tokens:
			if not node is Node3D:
				continue
			var token: Node3D = node as Node3D
			if _token_touched_by_current_geometry(token):
				affected.append(token)
	board.call("set_affected_token_highlight", affected)


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
	_update_following_aoes()
	_refresh_affected_token_highlight()


func _update_following_aoes() -> void:
	var count: int = mini(persistent_aoes.size(), _aoe_nodes.size())
	for index: int in range(count):
		var root: Node3D = _aoe_nodes[index]
		if root == null or not is_instance_valid(root):
			continue

		if not root.has_meta("follow_target"):
			continue
		var follow_value: Variant = root.get_meta("follow_target")
		if not follow_value is Node3D:
			continue
		var follow_target: Node3D = follow_value as Node3D
		if not is_instance_valid(follow_target):
			root.remove_meta("follow_target")
			root.remove_meta("follow_last_position")
			continue

		var current_position: Vector3 = follow_target.global_position
		var previous_value: Variant = root.get_meta(
			"follow_last_position",
			current_position
		)
		if not previous_value is Vector3:
			root.set_meta("follow_last_position", current_position)
			continue

		var previous_position: Vector3 = previous_value
		var movement_delta: Vector3 = current_position - previous_position
		if movement_delta.length_squared() <= 0.000001:
			continue

		# The rendered mesh, particles and pick collision are all children of
		# the persistent AoE root, so moving the root keeps the whole aura
		# visually attached to its caster.
		root.global_position += movement_delta

		# Persistent hit-testing and serialization use the stored world-space
		# start/end points, so move those by the same delta as the visual root.
		var data_value: Variant = persistent_aoes[index]
		if data_value is Dictionary:
			var data: Dictionary = data_value as Dictionary
			for point_key: String in ["start", "end"]:
				var point_value: Variant = data.get(point_key, [])
				if not point_value is Array:
					continue
				var coordinates: Array = point_value as Array
				if coordinates.size() != 3:
					continue
				var shifted_point := Vector3(
					float(coordinates[0]),
					float(coordinates[1]),
					float(coordinates[2])
				) + movement_delta
				data[point_key] = [
					shifted_point.x,
					shifted_point.y,
					shifted_point.z
				]
			persistent_aoes[index] = data

		root.set_meta("follow_last_position", current_position)


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

	# Resolve the release position as well: when a token is under the mouse,
	# the final endpoint must use its real elevation, even if the last input
	# arrived after the previous _process() update.
	_update_target_from_camera()
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


func _clamp_depth_to_grid_exit(
	origin: Vector3,
	direction: Vector3,
	requested_depth: float
) -> float:
	if (
		_volumetric_grid == null
		or not is_instance_valid(_volumetric_grid)
		or not _volumetric_grid.has_method("get_ray_exit_distance")
	):
		return requested_depth

	var exit_value: Variant = _volumetric_grid.call(
		"get_ray_exit_distance",
		origin,
		direction
	)
	if not exit_value is float:
		return requested_depth

	var exit_distance: float = maxf(float(exit_value), 0.0)
	return minf(
		requested_depth,
		maxf(
			cell_size * 0.5,
			exit_distance - maxf(cell_size * 0.001, 0.0001)
		)
	)


func get_spell_target_point(
	screen_position: Vector2,
	preferred_air_distance_world: float = -1.0,
	force_grid_target: bool = false
) -> Dictionary:
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
	var grid_active: bool = (
		_volumetric_grid != null
		and is_instance_valid(_volumetric_grid)
		and _volumetric_grid.visible
	)

	# Shift mantiene il comportamento manuale della griglia: una superficie
	# reale viene sempre preferita; in aria si usa la profondita' regolabile
	# con la rotellina e, se visibile, il volume della griglia 3D.
	if force_grid_target:
		if not hit.is_empty():
			return _spell_surface_target(hit)

		if not grid_active:
			return {"valid": false}

		var grid_depth: float = _clamp_depth_to_grid_exit(
			origin,
			direction,
			_air_depth_world
		)

		var grid_point: Vector3 = _snap_point_to_grid_intersection(
			origin + direction * grid_depth
		)
		if not _grid_contains(grid_point):
			return {"valid": false}
		return {
			"valid": true,
			"point": grid_point,
			"in_air": true,
			"normal": Vector3.ZERO
		}

	# Per le AoE puntuali la distanza automatica viene scelta dallo spell
	# system (per una sfera: due volte il raggio). Una superficie solida
	# intercettata PRIMA di quella distanza continua ad avere priorita'.
	if preferred_air_distance_world > 0.0:
		var automatic_depth: float = clampf(
			preferred_air_distance_world,
			cell_size,
			max_ray_distance
		)
		if not hit.is_empty():
			var hit_position: Vector3 = hit.get(
				"position",
				Vector3.ZERO
			)
			var hit_distance: float = origin.distance_to(hit_position)
			if hit_distance <= automatic_depth + cell_size * 0.01:
				return _spell_surface_target(hit)

		var automatic_point: Vector3 = _snap_point_to_grid_intersection(
			origin + direction * automatic_depth
		)
		return {
			"valid": true,
			"point": automatic_point,
			"in_air": true,
			"normal": Vector3.ZERO
		}

	# Tutti gli altri sistemi (summon, teleport, muri, ecc.) mantengono il
	# comportamento precedente.
	if not hit.is_empty():
		return _spell_surface_target(hit)

	if not grid_active:
		return {"valid": false}

	var effective_depth: float = _clamp_depth_to_grid_exit(
		origin,
		direction,
		_air_depth_world
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


func _spell_surface_target(hit: Dictionary) -> Dictionary:
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


# Measure from the free square directly beneath the token's feet;
# the lowest *occupied* square is part of the creature, not its support.
# Keep X/Z at the creature's footprint center (important for Large+).
func _ruler_token_anchor(token: Node3D) -> Vector3:
	var support_y: float = TopDownElevationLevels.token_support_air_level(
		token, cell_size
	)
	return Vector3(
		token.global_position.x,
		support_y,
		token.global_position.z
	)


func _ruler_token_under_mouse(
	screen_point: Vector2,
	surface_hit: Dictionary,
	ray_origin: Vector3
) -> Dictionary:
	# The board has a shared picker which raycasts hitboxes in 3D and uses
	# the visible token badges in 2D (including flying tokens).
	var board: Node = get_parent()
	if board == null or not board.has_method("_raycast_token_from_screen"):
		return {}
	var hit_value: Variant = board.call(
		"_raycast_token_from_screen", screen_point, true
	)
	if not hit_value is Dictionary:
		return {}
	var hit: Dictionary = hit_value as Dictionary
	var token: Node3D = hit.get("collider") as Node3D
	if token == null or not token.is_in_group("dnd_token"):
		return {}
	# In 3D do not measure a token through a wall or other closer surface.
	# In 2D the token badge is itself the pickable surface, independent of
	# the terrain at that screen coordinate.
	var is_2d: bool = (
		_camera.has_method("is_top_down_2d")
		and bool(_camera.call("is_top_down_2d"))
	)
	if not is_2d and not surface_hit.is_empty():
		var foreground: Vector3 = surface_hit.get("position", Vector3.ZERO)
		var token_hit: Vector3 = hit.get("position", token.global_position)
		if ray_origin.distance_to(foreground) + cell_size * 0.08 < ray_origin.distance_to(token_hit):
			return {}
	var anchor: Vector3 = _ruler_token_anchor(token)
	return {
		"valid": true,
		"center": anchor,
		"raw": anchor,
		"token": token
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

	if not aoe_mode:
		var token_target: Dictionary = _ruler_token_under_mouse(
			screen_point, hit, origin
		)
		if not token_target.is_empty():
			return token_target

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
		var effective_depth: float = _clamp_depth_to_grid_exit(
			origin,
			direction,
			_air_depth_world
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
		"fire", "fireball", "burning_hands", "fire_bolt", "scorching_ray", "wall_of_fire":
			return Color(1.0, 0.24, 0.03, 1.0)
		"cold", "ray_of_frost", "ice_knife", "ice_knife_burst", "gust_of_wind", "sleet_storm", "ice_storm", "cone_of_cold", "otilukes_freezing_sphere", "wall_of_ice":
			return Color(0.5, 0.9, 1.0, 1.0)
		"lightning", "lightning_bolt", "witch_bolt", "shocking_grasp", "thunderclap", "thunderwave", "chain_lightning":
			return Color(0.3, 0.8, 1.0, 1.0)
		"acid", "acid_splash", "vitriolic_sphere":
			return Color(0.48, 0.96, 0.12, 1.0)
		"poison", "poison_spray", "ray_of_sickness", "stinking_cloud", "cloudkill":
			return Color(0.38, 0.78, 0.12, 1.0)
		"necrotic", "blight", "circle_of_death":
			return Color(0.22, 0.06, 0.28, 1.0)
		"radiant", "sunbeam":
			return Color(1.0, 0.94, 0.56, 1.0)
		"force", "magic_missile", "globe_of_invulnerability", "shatter":
			return Color(0.7, 0.82, 1.0, 1.0)
		"psychic", "enchantment", "fear", "mind_sliver", "mind_spike", "sleep", "slow", "confusion", "synaptic_static", "hypnotic_pattern":
			return Color(0.68, 0.3, 1.0, 1.0)
		"thunder":
			return Color(0.48, 0.78, 1.0, 1.0)
		"bludgeoning":
			return Color(0.7, 0.72, 0.76, 1.0)
		"piercing", "slashing":
			return Color(0.88, 0.9, 0.94, 1.0)
		"arcane", "color_spray", "sorcerous_burst", "chromatic_orb":
			return Color(0.82, 0.3, 1.0, 1.0)
		"prismatic":
			return Color(0.9, 0.42, 1.0, 1.0)
		"silver_mist":
			return Color(0.86, 0.9, 0.98, 1.0)
		"mist":
			return Color(0.72, 0.78, 0.86, 1.0)
		"water":
			return Color(0.18, 0.66, 1.0, 1.0)
		"wind":
			return Color(0.78, 0.92, 1.0, 1.0)
		"earth":
			return Color(0.52, 0.4, 0.25, 1.0)
		"nature":
			return Color(0.28, 0.72, 0.18, 1.0)
		"darkness":
			return Color(0.03, 0.01, 0.07, 1.0)
		"fog_cloud":
			return Color(0.74, 0.78, 0.84, 1.0)
		"cloud_of_daggers":
			return Color(0.82, 0.86, 0.92, 1.0)
		"web":
			return Color(0.86, 0.88, 0.9, 1.0)
		"insect_plague":
			return Color(0.44, 0.34, 0.08, 1.0)
		"grease":
			return Color(0.64, 0.56, 0.18, 1.0)
		"disintegrate":
			return Color(0.18, 1.0, 0.34, 1.0)
		"wind_wall":
			return Color(0.72, 0.9, 1.0, 1.0)
		"blade_barrier":
			return Color(0.88, 0.92, 1.0, 1.0)
		"wall_of_force":
			return Color(0.48, 0.74, 1.0, 1.0)
		"wall_of_stone":
			return Color(0.42, 0.4, 0.36, 1.0)
		"wall_of_thorns":
			return Color(0.18, 0.58, 0.12, 1.0)
		"wall_of_sand":
			return Color(0.72, 0.58, 0.28, 1.0)
		"wall_of_water":
			return Color(0.22, 0.62, 0.94, 1.0)
		"prismatic_wall":
			return Color(0.86, 0.3, 1.0, 1.0)
		_:
			return Color(0.72, 0.34, 1.0, 1.0)


func show_spell_preview(
	start: Vector3,
	end: Vector3,
	shape: String,
	style: String = "",
	line_width_world: float = -1.0
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
		and is_equal_approx(
			_spell_preview_line_width,
			line_width_world
		)
	):
		_spell_preview.show()
		return

	if not is_instance_valid(_spell_preview):
		_spell_preview = MeshInstance3D.new()
		_spell_preview.name = "SpellAoEPreview"
		add_child(_spell_preview)

	_draw_aoe(
		_spell_preview,
		start,
		end,
		shape,
		style,
		Color(0.0, 0.0, 0.0, -1.0),
		line_width_world
	)

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
	_spell_preview_line_width = line_width_world
	_spell_preview.show()


func hide_spell_preview() -> void:
	if is_instance_valid(_spell_preview):
		_spell_preview.hide()


func show_spell_fixed_previews(
	starts: Array[Vector3],
	ends: Array[Vector3],
	shape: String,
	style: String = "",
	line_width_world: float = -1.0
) -> void:
	clear_spell_fixed_previews()
	if starts.size() != ends.size():
		return
	if shape not in ["sphere", "cube", "cone", "line", "flat_square", "cylinder"]:
		return

	for index: int in range(starts.size()):
		var preview: MeshInstance3D = MeshInstance3D.new()
		preview.name = "SpellFixedPreview%d" % index
		add_child(preview)
		_draw_aoe(
			preview,
			starts[index],
			ends[index],
			shape,
			style,
			Color(0.0, 0.0, 0.0, -1.0),
			line_width_world
		)
		_spell_fixed_previews.append(preview)


func clear_spell_fixed_previews() -> void:
	for preview: MeshInstance3D in _spell_fixed_previews:
		if preview != null and is_instance_valid(preview):
			preview.queue_free()
	_spell_fixed_previews.clear()


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



func show_held_spell_aoe(
	start: Vector3,
	end: Vector3,
	shape: String,
	style: String = "",
	line_width_world: float = -1.0
) -> void:
	if shape not in ["sphere", "cube", "cone", "line", "flat_square", "cylinder"]:
		return

	var root: Node3D = Node3D.new()
	root.name = "HeldSpellAoE"
	add_child(root)

	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Visual"
	root.add_child(mesh)
	_draw_aoe(
		mesh,
		start,
		end,
		shape,
		style,
		Color(0.0, 0.0, 0.0, -1.0),
		line_width_world
	)
	DamageAreaParticles.attach_area(
		root, start, end, shape, style, cell_size
	)
	_add_aoe_pick_area(
		root,
		start,
		end,
		shape,
		style,
		line_width_world
	)
	_held_spell_aoes.append(root)


func clear_held_spell_aoes() -> void:
	for root: Node3D in _held_spell_aoes:
		if root != null and is_instance_valid(root):
			root.hide()
			root.queue_free()
	_held_spell_aoes.clear()


func clear_post_cast_spell_visuals() -> void:
	clear_held_spell_aoes()
	clear_transient_spell_aoes()


func has_post_cast_spell_visuals() -> bool:
	for root: Node3D in _held_spell_aoes:
		if root != null and is_instance_valid(root):
			return true
	for child: Node in get_children():
		if (
			child is Node3D
			and String(child.name).begins_with("TransientAoE")
		):
			return true
	for data_value: Variant in persistent_aoes:
		if (
			data_value is Dictionary
			and bool(
				(data_value as Dictionary).get(
					"spell_click_to_remove",
					false
				)
			)
		):
			return true
	return false


func _remove_post_cast_spell_root(root: Node3D) -> bool:
	if root == null or not is_instance_valid(root):
		return false

	var held_index: int = _held_spell_aoes.find(root)
	if held_index >= 0:
		_held_spell_aoes.remove_at(held_index)
		root.hide()
		root.queue_free()
		_affected_tokens_signature = ""
		_refresh_affected_token_highlight()
		return true

	var persistent_index: int = _aoe_nodes.find(root)
	if (
		persistent_index >= 0
		and persistent_index < persistent_aoes.size()
	):
		var persistent_data_value: Variant = persistent_aoes[
			persistent_index
		]
		if (
			persistent_data_value is Dictionary
			and bool(
				(persistent_data_value as Dictionary).get(
					"spell_click_to_remove",
					false
				)
			)
		):
			return dissolve_aoe(persistent_index)

	var root_id: int = root.get_instance_id()
	for index: int in range(_transient_spell_aoes.size() - 1, -1, -1):
		if int(_transient_spell_aoes[index].get("id", -1)) != root_id:
			continue
		_transient_spell_aoes.remove_at(index)
		root.hide()
		root.queue_free()
		_affected_tokens_signature = ""
		_refresh_affected_token_highlight()
		return true

	return false


func remove_post_cast_spell_visual_at_screen(
	screen_position: Vector2
) -> bool:
	if _camera == null or not is_instance_valid(_camera):
		return false

	var origin: Vector3 = _camera.project_ray_origin(screen_position)
	var direction: Vector3 = _camera.project_ray_normal(screen_position)
	var excluded: Array[RID] = []

	# Post-cast spell areas share the normal AoE pick layer. Skip any manual
	# persistent AoE in front of the ray instead of deleting it by accident.
	for _attempt: int in range(16):
		var query := PhysicsRayQueryParameters3D.create(
			origin,
			origin + direction * max_ray_distance
		)
		query.collision_mask = AOE_PICK_LAYER
		query.collide_with_bodies = false
		query.collide_with_areas = true
		query.exclude = excluded

		var hit: Dictionary = (
			_camera.get_world_3d().direct_space_state.intersect_ray(query)
		)
		if hit.is_empty():
			return false

		var area: Area3D = hit.get("collider") as Area3D
		if area == null:
			return false

		if area.has_meta("aoe_root"):
			var root_value: Variant = area.get_meta("aoe_root")
			if root_value is Node3D:
				var root := root_value as Node3D
				if _remove_post_cast_spell_root(root):
					return true

		excluded.append(area.get_rid())

	return false


func show_transient_aoe(
	start: Vector3,
	end: Vector3,
	shape: String,
	duration_seconds: float = 5.0,
	style: String = "",
	line_width_world: float = -1.0,
	auto_expire: bool = false
) -> void:
	if shape not in ["sphere", "cube", "cone", "line", "flat_square", "cylinder"]:
		return

	var root: Node3D = Node3D.new()
	root.name = "TransientAoE"
	add_child(root)

	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Visual"
	root.add_child(mesh)
	_draw_aoe(
		mesh,
		start,
		end,
		shape,
		style,
		Color(0.0, 0.0, 0.0, -1.0),
		line_width_world
	)
	DamageAreaParticles.attach_area(
		root, start, end, shape, style, cell_size
	)
	_add_aoe_pick_area(
		root,
		start,
		end,
		shape,
		style,
		line_width_world
	)

	var transient_id: int = root.get_instance_id()
	_transient_spell_aoes.append({
		"id": transient_id,
		"start": [start.x, start.y, start.z],
		"end": [end.x, end.y, end.z],
		"shape": shape,
		"style": style,
		"line_width_world": line_width_world
	})
	_affected_tokens_signature = ""

	# Confirmed spell areas may be held until the user's next click so the
	# final AoE and its red affected-cell highlight share one lifecycle.
	if not auto_expire:
		return

	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(duration_seconds, 0.05)
	root.add_child(timer)
	timer.timeout.connect(
		func() -> void:
			for index: int in range(
				_transient_spell_aoes.size() - 1,
				-1,
				-1
			):
				if int(
					_transient_spell_aoes[index].get("id", -1)
				) == transient_id:
					_transient_spell_aoes.remove_at(index)
					break
			_affected_tokens_signature = ""
			if is_instance_valid(root):
				root.queue_free()
	)
	timer.start()


func clear_transient_spell_aoes() -> void:
	for child: Node in get_children():
		if (
			child is Node3D
			and String(child.name).begins_with("TransientAoE")
		):
			(child as Node3D).hide()
			child.queue_free()
	_transient_spell_aoes.clear()
	_affected_tokens_signature = ""
	_refresh_affected_token_highlight()


func show_teleport_cloud(
	world_point: Vector3,
	style: String = "arcane",
	duration_seconds: float = 0.55
) -> void:
	var root: Node3D = Node3D.new()
	root.name = "TransientTeleportCloud"
	add_child(root)
	SpellVFX.attach_teleport_cloud(
		root,
		world_point,
		style,
		maxf(duration_seconds, 0.2),
		cell_size
	)

	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(duration_seconds, 0.2) + 0.15
	root.add_child(timer)
	timer.timeout.connect(root.queue_free)
	timer.start()


func show_spell_projectile(
	start: Vector3,
	end: Vector3,
	style: String,
	duration_seconds: float = 0.65
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


func add_spell_wall_path(
	points: Array[Vector3],
	height_world: float,
	thickness_world: float,
	style: String,
	damage_side: int = 0,
	metadata: Dictionary = {}
) -> void:
	var previous_count: int = persistent_aoes.size()
	add_wall_path(
		points,
		height_world,
		thickness_world,
		style,
		damage_side,
		metadata
	)
	if persistent_aoes.size() > previous_count:
		_mark_persistent_aoe_as_spell(persistent_aoes.size() - 1)


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


func add_spell_wall_globe(
	center: Vector3,
	radius_world: float,
	style: String,
	hemisphere: bool = false,
	metadata: Dictionary = {}
) -> void:
	var previous_count: int = persistent_aoes.size()
	add_wall_globe(
		center,
		radius_world,
		style,
		hemisphere,
		metadata
	)
	if persistent_aoes.size() > previous_count:
		_mark_persistent_aoe_as_spell(persistent_aoes.size() - 1)


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
			DamageAreaParticles.attach_wall_segment(
				root,
				start,
				finish,
				height_world,
				thickness_world,
				style,
				cell_size
			)
		if style in ["wall_of_fire", "fire"] and damage_side != 0:
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
		DamageAreaParticles.attach_wall_globe(
			root,
			center,
			radius_world,
			style,
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
	color: Color = Color(0.0, 0.0, 0.0, -1.0),
	line_width_world: float = -1.0,
	movable_aoe_feet: float = 0.0,
	movable_aoe_mode: String = "free",
	caster_origin: Vector3 = Vector3(INF, INF, INF),
	follow_target: Node3D = null
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
	if line_width_world > 0.0:
		data["line_width_world"] = line_width_world
	if movable_aoe_feet > 0.0:
		data["movable_aoe_feet"] = movable_aoe_feet
		data["movable_aoe_mode"] = movable_aoe_mode
		if (
			is_finite(caster_origin.x)
			and is_finite(caster_origin.y)
			and is_finite(caster_origin.z)
		):
			data["caster_origin"] = [
				caster_origin.x,
				caster_origin.y,
				caster_origin.z
			]
	persistent_aoes.append(data)

	var root := Node3D.new()
	root.name = "PersistentAoE"
	add_child(root)
	if follow_target != null and is_instance_valid(follow_target):
		root.set_meta("follow_target", follow_target)
		root.set_meta("follow_last_position", follow_target.global_position)

	var mesh := MeshInstance3D.new()
	mesh.name = "Visual"
	root.add_child(mesh)
	_draw_aoe(
		mesh,
		start,
		end,
		shape,
		style,
		selected_color,
		line_width_world
	)
	DamageAreaParticles.attach_area(
		root, start, end, shape, style, cell_size
	)

	_add_aoe_pick_area(
		root,
		start,
		end,
		shape,
		style,
		line_width_world
	)
	_aoe_nodes.append(root)


func _mark_persistent_aoe_as_spell(index: int) -> void:
	if (
		index < 0
		or index >= persistent_aoes.size()
		or index >= _aoe_nodes.size()
	):
		return
	var data_value: Variant = persistent_aoes[index]
	if not data_value is Dictionary:
		return
	var data: Dictionary = data_value as Dictionary
	data["spell_click_to_remove"] = true
	persistent_aoes[index] = data
	var root: Node3D = _aoe_nodes[index]
	if root != null and is_instance_valid(root):
		root.set_meta("post_cast_spell_area", true)


func add_spell_aoe(
	start: Vector3,
	end: Vector3,
	shape: String,
	style: String = "",
	color: Color = Color(0.0, 0.0, 0.0, -1.0),
	line_width_world: float = -1.0,
	movable_aoe_feet: float = 0.0,
	movable_aoe_mode: String = "free",
	caster_origin: Vector3 = Vector3(INF, INF, INF),
	follow_target: Node3D = null
) -> void:
	var previous_count: int = persistent_aoes.size()
	add_aoe(
		start,
		end,
		shape,
		style,
		color,
		line_width_world,
		movable_aoe_feet,
		movable_aoe_mode,
		caster_origin,
		follow_target
	)
	if persistent_aoes.size() > previous_count:
		_mark_persistent_aoe_as_spell(persistent_aoes.size() - 1)


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
	style: String = "",
	line_width_world: float = -1.0
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
			geometry["radius"] = (
				line_width_world * 0.5
				if line_width_world > 0.0
				else _aoe_line_radius(style)
			)
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
	color: Color = Color(0.0, 0.0, 0.0, -1.0),
	line_width_world: float = -1.0
) -> void:
	var geometry: Dictionary = _aoe_geometry(
		start,
		end,
		shape,
		style,
		line_width_world
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



func is_movable_aoe(index: int) -> bool:
	if index < 0 or index >= persistent_aoes.size():
		return false
	var data_value: Variant = persistent_aoes[index]
	if not data_value is Dictionary:
		return false
	return float((data_value as Dictionary).get("movable_aoe_feet", 0.0)) > 0.0


func is_movable_aoe_dragging() -> bool:
	return _movable_aoe_drag_index >= 0


func begin_movable_aoe_drag(index: int) -> bool:
	if not is_movable_aoe(index):
		return false
	if index >= _aoe_nodes.size():
		return false
	var root: Node3D = _aoe_nodes[index]
	if root == null or not is_instance_valid(root):
		return false

	_movable_aoe_drag_index = index
	_movable_aoe_drag_root_origin = root.global_position
	_movable_aoe_drag_delta = Vector3.ZERO
	_movable_aoe_drag_was_captured = (
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true


func _movable_aoe_drag_target(screen_position: Vector2) -> Dictionary:
	if _movable_aoe_drag_index < 0:
		return {"valid": false}
	if _movable_aoe_drag_index >= persistent_aoes.size():
		return {"valid": false}

	var point_data: Dictionary = get_spell_target_point(screen_position)
	if not bool(point_data.get("valid", false)):
		return {"valid": false}

	var data: Dictionary = persistent_aoes[_movable_aoe_drag_index]
	var start_data: Array = data.get("start", [])
	if start_data.size() != 3:
		return {"valid": false}
	var start: Vector3 = Vector3(
		float(start_data[0]),
		float(start_data[1]),
		float(start_data[2])
	)
	var target: Vector3 = point_data.get("point", start)
	var desired_delta: Vector3 = target - start

	var max_feet: float = float(data.get("movable_aoe_feet", 0.0))
	var max_world: float = max_feet / 5.0 * cell_size
	var mode: String = String(data.get("movable_aoe_mode", "free"))

	if mode == "away_from_caster":
		var caster_data: Array = data.get("caster_origin", [])
		if caster_data.size() != 3:
			return {"valid": false}
		var caster_origin: Vector3 = Vector3(
			float(caster_data[0]),
			float(caster_data[1]),
			float(caster_data[2])
		)
		var away: Vector3 = start - caster_origin
		away.y = 0.0
		if away.length_squared() < 0.0001:
			return {"valid": false}
		desired_delta = away.normalized() * max_world
	elif mode == "free_exact":
		desired_delta.y = 0.0
		if desired_delta.length_squared() < 0.0001:
			return {"valid": false}
		desired_delta = desired_delta.normalized() * max_world
	else:
		if desired_delta.length() > max_world:
			desired_delta = desired_delta.normalized() * max_world

	return {
		"valid": true,
		"delta": desired_delta
	}


func update_movable_aoe_drag(screen_position: Vector2) -> bool:
	if not is_movable_aoe_dragging():
		return false
	if _movable_aoe_drag_index >= _aoe_nodes.size():
		return false

	var target_data: Dictionary = _movable_aoe_drag_target(
		screen_position
	)
	if not bool(target_data.get("valid", false)):
		return false

	var root: Node3D = _aoe_nodes[_movable_aoe_drag_index]
	if root == null or not is_instance_valid(root):
		return false

	_movable_aoe_drag_delta = target_data.get(
		"delta",
		Vector3.ZERO
	)
	root.global_position = (
		_movable_aoe_drag_root_origin
		+ _movable_aoe_drag_delta
	)
	return true


func finish_movable_aoe_drag(commit: bool) -> bool:
	if not is_movable_aoe_dragging():
		return false

	var index: int = _movable_aoe_drag_index
	var changed: bool = _movable_aoe_drag_delta.length_squared() > 0.000001
	if index >= 0 and index < _aoe_nodes.size():
		var root: Node3D = _aoe_nodes[index]
		if root != null and is_instance_valid(root):
			if not commit:
				root.global_position = _movable_aoe_drag_root_origin

	if (
		commit
		and changed
		and index >= 0
		and index < persistent_aoes.size()
	):
		_record_undo_state()
		var data: Dictionary = persistent_aoes[index]
		for key: String in ["start", "end"]:
			var point_data: Array = data.get(key, [])
			if point_data.size() == 3:
				var point: Vector3 = Vector3(
					float(point_data[0]),
					float(point_data[1]),
					float(point_data[2])
				) + _movable_aoe_drag_delta
				data[key] = [point.x, point.y, point.z]
		persistent_aoes[index] = data

	_movable_aoe_drag_index = -1
	_movable_aoe_drag_delta = Vector3.ZERO
	if _movable_aoe_drag_was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_movable_aoe_drag_was_captured = false
	return commit and changed


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
	style: String = "",
	line_width_world: float = -1.0
) -> void:
	var geometry: Dictionary = _aoe_geometry(
		start,
		end,
		shape_name,
		style,
		line_width_world
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
	if is_movable_aoe_dragging():
		finish_movable_aoe_drag(false)
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


func valid_aoes(data: Variant) -> bool:
	return AoeSnapshotValidator.valid_aoes(data)


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
			if bool(item_data.get("spell_click_to_remove", false)):
				_mark_persistent_aoe_as_spell(_aoe_nodes.size() - 1)
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
			if bool(item_data.get("spell_click_to_remove", false)):
				_mark_persistent_aoe_as_spell(_aoe_nodes.size() - 1)
			continue

		var start_data: Array = item_data.get("start", [])
		var end_data: Array = item_data.get("end", [])
		var color: Color = _deserialize_aoe_color(
			item_data.get("color", {})
		)
		var caster_origin_data: Array = item_data.get(
			"caster_origin",
			[]
		)
		var caster_origin: Vector3 = Vector3(INF, INF, INF)
		if caster_origin_data.size() == 3:
			caster_origin = Vector3(
				float(caster_origin_data[0]),
				float(caster_origin_data[1]),
				float(caster_origin_data[2])
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
			color,
			float(item_data.get("line_width_world", -1.0)),
			float(item_data.get("movable_aoe_feet", 0.0)),
			String(item_data.get("movable_aoe_mode", "free")),
			caster_origin
		)
		if bool(item_data.get("spell_click_to_remove", false)):
			_mark_persistent_aoe_as_spell(_aoe_nodes.size() - 1)

	_suppress_undo_record = false
