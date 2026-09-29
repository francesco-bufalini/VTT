extends Node3D

const GRID_3D_EXCLUDED_GROUP := "grid_3d_excluded"
const GRID_2D_EXCLUDED_GROUP := "grid_2d_excluded"
const TOKEN_GROUP := "dnd_token"
const DYNAMIC_GRID_GROUPS: Array[String] = [
	"dnd_token",
	"tactical_platform",
	"encounter_obstacle",
]
const INVALID_CELL := Vector3i(2147483647, 2147483647, 2147483647)

@export var cell_size: float = 1.0
# Logical/range volume. Rendering cost depends on screen samples, not N^3.
@export_range(8, 120, 1) var cells_per_side: int = 70
@export_flags_3d_physics var collision_mask: int = 1
# Tokens live on layer 2 in the base VTT and are deliberately included in
# the visible collision grid.
@export_flags_3d_physics var token_collision_mask: int = 2
@export var include_tokens: bool = true

# Screen-space sampling. A complete sweep is spread over multiple physics
# frames, but unlike the old implementation it stops completely once the
# camera and relevant geometry become stationary.
@export_range(8, 64, 1) var ray_spacing_pixels: int = 20
@export_range(1000, 12000, 250) var target_screen_samples: int = 3000
@export_range(32, 2048, 1) var max_ray_tests_per_physics_frame: int = 128
@export_range(0.01, 0.25, 0.01) var surface_inset_fraction: float = 0.06
@export_range(256, 30000, 256) var max_active_cells: int = 12288

# Event thresholds. Small camera jitter does not restart a sweep.
@export_range(0.01, 2.0, 0.01) var camera_move_threshold_cells: float = 0.18
@export_range(0.1, 15.0, 0.1) var camera_rotation_threshold_degrees: float = 1.0
@export_range(0.02, 1.0, 0.02) var dynamic_change_check_interval: float = 0.12

# Legacy exported properties kept so inherited scenes made before the
# event-driven grid continue to load without missing-property warnings.
@export_range(0.15, 2.0, 0.05) var cell_retention_seconds: float = 0.65
@export_range(0.02, 0.5, 0.01) var visual_update_interval: float = 0.08
@export_range(0.1, 2.0, 0.1) var exclusion_refresh_interval: float = 0.5

var _camera: Camera3D = null
var _grid_mesh_instance: MultiMeshInstance3D = null
var _multimesh: MultiMesh = null
var _grid_material: StandardMaterial3D = null

var _center_cell: Vector3i = INVALID_CELL
var _lower_extent_cells: int = 35
var _upper_extent_cells: int = 34
var _half_extent_world: float = 35.0

# The currently displayed cells are replaced atomically when a sweep finishes.
# This avoids flicker while a new camera view is being sampled.
var _visible_cells: Dictionary = {}
var _sweep_cells: Dictionary = {}
var _sample_points: Array[Vector2] = []
var _sample_index: int = 0
var _sample_viewport_size: Vector2i = Vector2i.ZERO

var _ray_query: PhysicsRayQueryParameters3D = null
var _excluded_rids: Array[RID] = []
var _sweep_active: bool = false
var _resweep_requested: bool = true
var _was_visible: bool = false
var _visual_dirty: bool = true
var _interaction_strength: float = 0.55

var _camera_anchor_transform: Transform3D = Transform3D.IDENTITY
var _camera_anchor_fov: float = -1.0
var _dynamic_elapsed: float = 999.0
var _dynamic_signature: int = 0


func _ready() -> void:
	_configure_grid()
	_build_multimesh()

	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collide_with_bodies = true
	_ray_query.collide_with_areas = false
	_ray_query.collision_mask = _effective_collision_mask()

	get_tree().node_added.connect(_on_tree_node_added)
	get_tree().node_removed.connect(_on_tree_node_removed)


func _physics_process(delta: float) -> void:
	if not visible:
		_was_visible = false
		return
	if _camera == null or not is_instance_valid(_camera):
		return

	var next_center: Vector3i = _world_to_cell(_camera.global_position)
	if next_center != _center_cell:
		_center_cell = next_center
		_request_sweep()

	var viewport_size := Vector2i(
		_camera.get_viewport().get_visible_rect().size
	)
	if viewport_size != _sample_viewport_size or _sample_points.is_empty():
		_rebuild_sample_pattern(viewport_size)
		_request_sweep(true)

	if not _was_visible:
		_was_visible = true
		_capture_camera_anchor()
		_refresh_exclusions()
		_dynamic_signature = _compute_dynamic_signature()
		_request_sweep(true)
	elif _camera_changed_enough():
		_capture_camera_anchor()
		_request_sweep()

	_dynamic_elapsed += delta
	if _dynamic_elapsed >= dynamic_change_check_interval:
		_dynamic_elapsed = 0.0
		var signature: int = _compute_dynamic_signature()
		if signature != _dynamic_signature:
			_dynamic_signature = signature
			_refresh_exclusions()
			_request_sweep()

	if _resweep_requested and not _sweep_active:
		_start_sweep()

	if _sweep_active:
		_sample_visible_surfaces()


func set_camera(new_camera: Camera3D) -> void:
	_camera = new_camera
	_center_cell = INVALID_CELL
	_sample_points.clear()
	_sample_index = 0
	_capture_camera_anchor()
	_request_sweep(true)


func mark_map_dirty() -> void:
	# Static geometry changes should call this. The currently rendered grid is
	# kept until the new sweep finishes, so edits do not cause visible flicker.
	_refresh_exclusions()
	_request_sweep()


func refresh() -> void:
	mark_map_dirty()


func set_interaction_strength(value: float) -> void:
	_interaction_strength = clampf(value, 0.0, 1.0)
	_apply_material_strength()


func get_half_extent_world() -> float:
	return _half_extent_world


func contains_world_point(point: Vector3) -> bool:
	if _center_cell == INVALID_CELL:
		return false

	var min_cell := _volume_min_cell(_center_cell)
	var max_cell := _volume_max_cell(_center_cell)
	var epsilon := maxf(cell_size * 0.001, 0.0001)

	var min_point := Vector3(
		float(min_cell.x) * cell_size,
		float(min_cell.y) * cell_size,
		float(min_cell.z) * cell_size
	)
	var max_point := Vector3(
		float(max_cell.x + 1) * cell_size,
		float(max_cell.y + 1) * cell_size,
		float(max_cell.z + 1) * cell_size
	)

	return (
		point.x >= min_point.x - epsilon
		and point.x <= max_point.x + epsilon
		and point.y >= min_point.y - epsilon
		and point.y <= max_point.y + epsilon
		and point.z >= min_point.z - epsilon
		and point.z <= max_point.z + epsilon
	)


func get_ray_exit_distance(origin: Vector3, direction: Vector3) -> float:
	if _center_cell == INVALID_CELL:
		return 0.0

	var normalized_direction := direction.normalized()
	if normalized_direction.length_squared() < 0.000001:
		return 0.0

	var min_cell := _volume_min_cell(_center_cell)
	var max_cell := _volume_max_cell(_center_cell)
	var min_point := Vector3(
		float(min_cell.x) * cell_size,
		float(min_cell.y) * cell_size,
		float(min_cell.z) * cell_size
	)
	var max_point := Vector3(
		float(max_cell.x + 1) * cell_size,
		float(max_cell.y + 1) * cell_size,
		float(max_cell.z + 1) * cell_size
	)

	var t_min := -INF
	var t_max := INF

	for axis in range(3):
		var o: float = origin[axis]
		var d: float = normalized_direction[axis]
		var min_axis: float = min_point[axis]
		var max_axis: float = max_point[axis]

		if absf(d) < 0.000001:
			if o < min_axis or o > max_axis:
				return 0.0
			continue

		var t_a := (min_axis - o) / d
		var t_b := (max_axis - o) / d
		if t_a > t_b:
			var swap := t_a
			t_a = t_b
			t_b = swap

		t_min = maxf(t_min, t_a)
		t_max = minf(t_max, t_b)
		if t_min > t_max:
			return 0.0

	if t_max < 0.0:
		return 0.0
	return maxf(0.0, t_max)


func _configure_grid() -> void:
	cell_size = maxf(cell_size, 0.001)
	cells_per_side = maxi(8, cells_per_side)
	_lower_extent_cells = int(floor(float(cells_per_side) * 0.5))
	_upper_extent_cells = cells_per_side - _lower_extent_cells - 1
	_half_extent_world = float(cells_per_side) * cell_size * 0.5


func _effective_collision_mask() -> int:
	var result: int = collision_mask
	if include_tokens:
		result |= token_collision_mask
	return result


func _build_multimesh() -> void:
	if (
		_grid_mesh_instance != null
		and is_instance_valid(_grid_mesh_instance)
	):
		_grid_mesh_instance.queue_free()

	_grid_material = StandardMaterial3D.new()
	_grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Grid lines are a tactical overlay. They must stay legible inside effects
	# such as Darkness/Fog and on token bodies. Cells are still generated only
	# from the first collision hit by each camera ray, so this does not turn
	# hidden geometry into a global x-ray grid.
	_grid_material.no_depth_test = true
	_grid_material.render_priority = 127

	var wire_cube := ImmediateMesh.new()
	wire_cube.surface_begin(Mesh.PRIMITIVE_LINES, _grid_material)

	var half := cell_size * 0.503
	var corners: Array[Vector3] = [
		Vector3(-half, -half, -half),
		Vector3(half, -half, -half),
		Vector3(half, half, -half),
		Vector3(-half, half, -half),
		Vector3(-half, -half, half),
		Vector3(half, -half, half),
		Vector3(half, half, half),
		Vector3(-half, half, half),
	]
	var edges: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 2),
		Vector2i(2, 3), Vector2i(3, 0),
		Vector2i(4, 5), Vector2i(5, 6),
		Vector2i(6, 7), Vector2i(7, 4),
		Vector2i(0, 4), Vector2i(1, 5),
		Vector2i(2, 6), Vector2i(3, 7),
	]

	for edge in edges:
		wire_cube.surface_add_vertex(corners[edge.x])
		wire_cube.surface_add_vertex(corners[edge.y])
	wire_cube.surface_end()

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = wire_cube
	_multimesh.instance_count = maxi(256, max_active_cells)
	_multimesh.visible_instance_count = 0

	_grid_mesh_instance = MultiMeshInstance3D.new()
	_grid_mesh_instance.name = "VisibleCollisionGrid3D"
	_grid_mesh_instance.multimesh = _multimesh
	_grid_mesh_instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	add_child(_grid_mesh_instance)
	_apply_material_strength()


func _apply_material_strength() -> void:
	if _grid_material == null:
		return

	var alpha := lerpf(0.16, 0.62, _interaction_strength)
	_grid_material.albedo_color = Color(0.42, 0.75, 1.0, alpha)
	_grid_material.emission_enabled = true
	_grid_material.emission = Color(0.04, 0.22, 0.38, 1.0)
	_grid_material.emission_energy_multiplier = (
		lerpf(0.20, 0.75, _interaction_strength)
	)


func _capture_camera_anchor() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	_camera_anchor_transform = _camera.global_transform
	_camera_anchor_fov = _camera.fov


func _camera_changed_enough() -> bool:
	if _camera == null or not is_instance_valid(_camera):
		return false

	if absf(_camera.fov - _camera_anchor_fov) > 0.05:
		return true

	var movement_threshold: float = (
		maxf(camera_move_threshold_cells, 0.01)
		* cell_size
	)
	if (
		_camera.global_position.distance_to(
			_camera_anchor_transform.origin
		) >= movement_threshold
	):
		return true

	var old_forward: Vector3 = (
		-_camera_anchor_transform.basis.z
	).normalized()
	var new_forward: Vector3 = (
		-_camera.global_transform.basis.z
	).normalized()
	var dot_value: float = clampf(
		old_forward.dot(new_forward),
		-1.0,
		1.0
	)
	var angle_degrees: float = rad_to_deg(acos(dot_value))
	return angle_degrees >= camera_rotation_threshold_degrees


func _request_sweep(restart: bool = false) -> void:
	_resweep_requested = true
	if restart and _sweep_active:
		_sweep_active = false
		_sweep_cells.clear()
		_sample_index = 0


func _start_sweep() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	if _sample_points.is_empty():
		return

	_resweep_requested = false
	_sweep_active = true
	_sweep_cells.clear()
	_sample_index = 0
	_ray_query.collision_mask = _effective_collision_mask()
	_ray_query.exclude = _excluded_rids


func _rebuild_sample_pattern(viewport_size: Vector2i) -> void:
	_sample_points.clear()
	_sample_index = 0
	_sample_viewport_size = viewport_size

	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return

	var area_pixels := maxf(
		1.0,
		float(viewport_size.x) * float(viewport_size.y)
	)
	var adaptive_spacing := int(ceil(sqrt(
		area_pixels / float(maxi(1000, target_screen_samples))
	)))
	var spacing := maxi(8, maxi(ray_spacing_pixels, adaptive_spacing))
	var half_spacing := int(floor(float(spacing) * 0.5))
	var center := Vector2(viewport_size) * 0.5
	var points_with_distance: Array[Dictionary] = []

	for y in range(half_spacing, viewport_size.y, spacing):
		for x in range(half_spacing, viewport_size.x, spacing):
			var point := Vector2(float(x), float(y))
			points_with_distance.append({
				"point": point,
				"distance": point.distance_squared_to(center)
			})

	points_with_distance.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["distance"]) < float(b["distance"])
	)

	for item in points_with_distance:
		_sample_points.append(item["point"])


func _sample_visible_surfaces() -> void:
	if _sample_points.is_empty() or _ray_query == null:
		_finish_sweep()
		return

	var remaining: int = _sample_points.size() - _sample_index
	var tests: int = mini(
		maxi(1, max_ray_tests_per_physics_frame),
		remaining
	)
	var ray_length := minf(
		_camera.far,
		maxf(cell_size, _half_extent_world * sqrt(3.0) * 1.08)
	)

	for _test in range(tests):
		var screen_point: Vector2 = _sample_points[_sample_index]
		_sample_index += 1

		var origin: Vector3 = _camera.project_ray_origin(screen_point)
		var direction: Vector3 = _camera.project_ray_normal(screen_point)
		_ray_query.from = origin
		_ray_query.to = origin + direction * ray_length

		var hit: Dictionary = (
			get_world_3d().direct_space_state.intersect_ray(
				_ray_query
			)
		)
		if hit.is_empty():
			continue

		var collider: Variant = hit.get("collider")
		if not _is_grid_collider(collider):
			continue

		var point: Vector3 = hit.get("position", Vector3.ZERO)
		var normal: Vector3 = hit.get("normal", Vector3.UP)
		if normal.length_squared() > 0.000001:
			point -= (
				normal.normalized()
				* cell_size
				* surface_inset_fraction
			)

		var cell: Vector3i = _world_to_cell(point)
		if not _cell_inside_current_volume(cell):
			continue
		if (
			not _sweep_cells.has(cell)
			and _sweep_cells.size() >= max_active_cells
		):
			continue

		_sweep_cells[cell] = true

	if _sample_index >= _sample_points.size():
		_finish_sweep()


func _finish_sweep() -> void:
	if not _sweep_active:
		return

	_visible_cells = _sweep_cells.duplicate()
	_sweep_cells.clear()
	_sweep_active = false
	_visual_dirty = true
	_update_multimesh_instances()
	_visual_dirty = false


func _refresh_exclusions() -> void:
	_excluded_rids.clear()

	for group_name in [
		GRID_3D_EXCLUDED_GROUP,
		GRID_2D_EXCLUDED_GROUP
	]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is CollisionObject3D:
				var rid: RID = (node as CollisionObject3D).get_rid()
				if not _excluded_rids.has(rid):
					_excluded_rids.append(rid)

	if _ray_query != null:
		_ray_query.exclude = _excluded_rids


func _is_grid_collider(collider: Variant) -> bool:
	if collider == null or not is_instance_valid(collider):
		return false
	if not collider is PhysicsBody3D:
		return false

	var body := collider as PhysicsBody3D
	var is_token: bool = _node_or_ancestor_in_group(
		body,
		TOKEN_GROUP
	)

	if body is CharacterBody3D and not is_token:
		return false

	if is_token:
		if not include_tokens:
			return false
		if (body.collision_layer & token_collision_mask) == 0:
			return false
	else:
		if (body.collision_layer & collision_mask) == 0:
			return false

	if (
		_node_or_ancestor_in_group(body, GRID_3D_EXCLUDED_GROUP)
		or _node_or_ancestor_in_group(body, GRID_2D_EXCLUDED_GROUP)
	):
		return false

	return true


func _node_or_ancestor_in_group(
	node: Node,
	group_name: String
) -> bool:
	var current: Node = node
	while current != null:
		if current.is_in_group(group_name):
			return true
		current = current.get_parent()
	return false


func _compute_dynamic_signature() -> int:
	var signature: int = 17

	for group_name in DYNAMIC_GRID_GROUPS:
		var nodes: Array[Node] = get_tree().get_nodes_in_group(
			group_name
		)
		for node in nodes:
			if not node is Node3D:
				continue
			if not is_ancestor_of(node):
				continue

			var node_3d := node as Node3D
			signature = hash([
				signature,
				node_3d.get_instance_id(),
				node_3d.global_transform,
				node_3d.visible,
			])
			if node_3d is CollisionObject3D:
				signature = hash([
					signature,
					(node_3d as CollisionObject3D).collision_layer,
				])

	return signature


func _on_tree_node_added(node: Node) -> void:
	if (
		node is CollisionObject3D
		or node is CollisionShape3D
	):
		_request_sweep()


func _on_tree_node_removed(node: Node) -> void:
	if (
		node is CollisionObject3D
		or node is CollisionShape3D
	):
		_request_sweep()


func _update_multimesh_instances() -> void:
	if _multimesh == null:
		return

	var index := 0
	var inverse_grid_transform := global_transform.affine_inverse()

	for key in _visible_cells.keys():
		if index >= max_active_cells:
			break

		var cell: Vector3i = key
		if not _cell_inside_current_volume(cell):
			continue

		var world_transform := Transform3D(
			Basis.IDENTITY,
			_cell_to_world_center(cell)
		)
		_multimesh.set_instance_transform(
			index,
			inverse_grid_transform * world_transform
		)
		index += 1

	_multimesh.visible_instance_count = index


func _volume_min_cell(center: Vector3i) -> Vector3i:
	return center - Vector3i.ONE * _lower_extent_cells


func _volume_max_cell(center: Vector3i) -> Vector3i:
	return center + Vector3i.ONE * _upper_extent_cells


func _cell_inside_current_volume(cell: Vector3i) -> bool:
	if _center_cell == INVALID_CELL:
		return false

	var min_cell := _volume_min_cell(_center_cell)
	var max_cell := _volume_max_cell(_center_cell)
	return (
		cell.x >= min_cell.x
		and cell.x <= max_cell.x
		and cell.y >= min_cell.y
		and cell.y <= max_cell.y
		and cell.z >= min_cell.z
		and cell.z <= max_cell.z
	)


func _world_to_cell(point: Vector3) -> Vector3i:
	var safe_cell_size := maxf(cell_size, 0.001)
	return Vector3i(
		int(floor(point.x / safe_cell_size)),
		int(floor(point.y / safe_cell_size)),
		int(floor(point.z / safe_cell_size))
	)


func _cell_to_world_center(cell: Vector3i) -> Vector3:
	return Vector3(
		(float(cell.x) + 0.5) * cell_size,
		(float(cell.y) + 0.5) * cell_size,
		(float(cell.z) + 0.5) * cell_size
	)
