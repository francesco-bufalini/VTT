extends Node3D

const GRID_3D_EXCLUDED_GROUP := "grid_3d_excluded"
const GRID_2D_EXCLUDED_GROUP := "grid_2d_excluded"
const TOKEN_GROUP := "dnd_token"
const INVALID_CELL := Vector3i(2147483647, 2147483647, 2147483647)

@export var cell_size: float = 1.0
# This is now only the logical/range volume. Cost no longer scales with N^3:
# visible surface cells are discovered with screen-space raycasts.
@export_range(8, 120, 1) var cells_per_side: int = 70
@export_flags_3d_physics var collision_mask: int = 1

# Screen-space sampling. At 1920x1080 and 20 px this is about 5k rays for a
# complete sweep, spread over several physics frames.
@export_range(8, 64, 1) var ray_spacing_pixels: int = 20
@export_range(1000, 12000, 250) var target_screen_samples: int = 4500
@export_range(32, 2048, 1) var max_ray_tests_per_physics_frame: int = 192
@export_range(0.15, 2.0, 0.05) var cell_retention_seconds: float = 0.65
@export_range(0.02, 0.5, 0.01) var visual_update_interval: float = 0.08
@export_range(0.01, 0.25, 0.01) var surface_inset_fraction: float = 0.06
# Legacy compatibility with encounter scripts created when the grid used
# per-cell collision shape probes. The current raycast-based grid no longer
# needs this value internally, but keeping the exported property lets older
# scenes tune it without crashing at runtime.
@export_range(0.75, 0.99, 0.005) var collision_probe_scale: float = 0.90
# Visual-only displacement of rendered grid cells. Some encounter scenes set
# this at runtime (for example Vector3(0, -0.5, 0)) so the voxel top face sits
# on the walkable collision surface instead of being centered around it.
@export var display_offset_cells: Vector3 = Vector3.ZERO
# Expand each raycast hit across nearby cells on the tangent plane of the
# detected surface. This stabilizes the visible grid when the camera angle
# changes without filling cells behind or in front of the surface.
@export_range(0, 3, 1) var neighbor_margin_cells: int = 1
@export_range(256, 30000, 256) var max_active_cells: int = 12288
@export_range(0.1, 2.0, 0.1) var exclusion_refresh_interval: float = 0.5

var _camera: Camera3D = null
var _grid_mesh_instance: MultiMeshInstance3D = null
var _multimesh: MultiMesh = null
var _grid_material: StandardMaterial3D = null

var _center_cell: Vector3i = INVALID_CELL
var _lower_extent_cells: int = 35
var _upper_extent_cells: int = 34
var _half_extent_world: float = 35.0

# Vector3i -> last seen timestamp (milliseconds).
var _visible_cells: Dictionary = {}
var _sample_points: Array[Vector2] = []
var _sample_index: int = 0
var _sample_viewport_size: Vector2i = Vector2i.ZERO

var _ray_query: PhysicsRayQueryParameters3D = null
var _excluded_rids: Array[RID] = []
var _exclusion_elapsed: float = 999.0
var _visual_elapsed: float = 999.0
var _visual_dirty: bool = true
var _interaction_strength: float = 0.55


func _ready() -> void:
	_configure_grid()
	_build_multimesh()
	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collide_with_bodies = true
	_ray_query.collide_with_areas = false
	_ray_query.collision_mask = collision_mask


func _physics_process(delta: float) -> void:
	if not visible:
		return
	if _camera == null or not is_instance_valid(_camera):
		return

	_center_cell = _world_to_cell(_camera.global_position)

	var viewport_size := Vector2i(
		_camera.get_viewport().get_visible_rect().size
	)
	if viewport_size != _sample_viewport_size or _sample_points.is_empty():
		_rebuild_sample_pattern(viewport_size)

	_exclusion_elapsed += delta
	if _exclusion_elapsed >= exclusion_refresh_interval:
		_exclusion_elapsed = 0.0
		_refresh_exclusions()

	_sample_visible_surfaces()

	_visual_elapsed += delta
	if _visual_elapsed >= visual_update_interval:
		_visual_elapsed = 0.0
		if _prune_stale_cells():
			_visual_dirty = true
		if _visual_dirty:
			_update_multimesh_instances()
			_visual_dirty = false


func set_camera(new_camera: Camera3D) -> void:
	_camera = new_camera
	_center_cell = INVALID_CELL
	_sample_points.clear()
	_sample_index = 0
	_visual_dirty = true


func mark_map_dirty() -> void:
	# With raycast sampling there is no expensive collision voxel cache to
	# invalidate. Clearing here makes changed geometry disappear immediately.
	_visible_cells.clear()
	_visual_dirty = true


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


func _build_multimesh() -> void:
	if (
		_grid_mesh_instance != null
		and is_instance_valid(_grid_mesh_instance)
	):
		_grid_mesh_instance.queue_free()

	_grid_material = StandardMaterial3D.new()
	_grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_grid_material.no_depth_test = false

	var wire_cube := ImmediateMesh.new()
	wire_cube.surface_begin(Mesh.PRIMITIVE_LINES, _grid_material)

	# Tiny oversize keeps the line just outside block-aligned surfaces and
	# avoids most z-fighting without drawing a filled cube.
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
	# Fixed capacity: changing instance_count repeatedly can cause allocations.
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

	# Start from the centre of the screen so the most useful part of the grid
	# appears first after activation.
	points_with_distance.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["distance"]) < float(b["distance"])
	)

	for item in points_with_distance:
		_sample_points.append(item["point"])


func _sample_visible_surfaces() -> void:
	if _sample_points.is_empty() or _ray_query == null:
		return

	var now := Time.get_ticks_msec()
	var tests := mini(
		maxi(1, max_ray_tests_per_physics_frame),
		_sample_points.size()
	)
	var ray_length := minf(
		_camera.far,
		maxf(cell_size, _half_extent_world * sqrt(3.0) * 1.08)
	)

	_ray_query.collision_mask = collision_mask
	_ray_query.exclude = _excluded_rids

	for _test in range(tests):
		var screen_point := _sample_points[_sample_index]
		_sample_index = (_sample_index + 1) % _sample_points.size()

		var origin := _camera.project_ray_origin(screen_point)
		var direction := _camera.project_ray_normal(screen_point)
		_ray_query.from = origin
		_ray_query.to = origin + direction * ray_length

		var hit := get_world_3d().direct_space_state.intersect_ray(
			_ray_query
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

		var cell := _world_to_cell(point)
		if not _cell_inside_current_volume(cell):
			continue

		_mark_visible_cell_with_margin(cell, normal, now)


func _mark_visible_cell_with_margin(
	cell: Vector3i,
	normal: Vector3,
	now: int
) -> void:
	_mark_visible_cell(cell, now)

	var margin := maxi(0, neighbor_margin_cells)
	if margin == 0:
		return

	var abs_normal := normal.abs()
	if abs_normal.x >= abs_normal.y and abs_normal.x >= abs_normal.z:
		for y_offset in range(-margin, margin + 1):
			for z_offset in range(-margin, margin + 1):
				_mark_visible_cell(
					cell + Vector3i(0, y_offset, z_offset),
					now
				)
	elif abs_normal.y >= abs_normal.x and abs_normal.y >= abs_normal.z:
		for x_offset in range(-margin, margin + 1):
			for z_offset in range(-margin, margin + 1):
				_mark_visible_cell(
					cell + Vector3i(x_offset, 0, z_offset),
					now
				)
	else:
		for x_offset in range(-margin, margin + 1):
			for y_offset in range(-margin, margin + 1):
				_mark_visible_cell(
					cell + Vector3i(x_offset, y_offset, 0),
					now
				)


func _mark_visible_cell(cell: Vector3i, now: int) -> void:
	if not _cell_inside_current_volume(cell):
		return
	if (
		not _visible_cells.has(cell)
		and _visible_cells.size() >= max_active_cells
	):
		return

	var previous: int = int(_visible_cells.get(cell, 0))
	_visible_cells[cell] = now
	if previous == 0:
		_visual_dirty = true


func _refresh_exclusions() -> void:
	_excluded_rids.clear()

	# Tokens and explicitly excluded physical helpers must not hide the map
	# from the grid raycasts.
	for node in get_tree().get_nodes_in_group(TOKEN_GROUP):
		if node is CollisionObject3D:
			_excluded_rids.append((node as CollisionObject3D).get_rid())

	for group_name in [
		GRID_3D_EXCLUDED_GROUP,
		GRID_2D_EXCLUDED_GROUP
	]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is CollisionObject3D:
				var rid := (node as CollisionObject3D).get_rid()
				if not _excluded_rids.has(rid):
					_excluded_rids.append(rid)


func _is_grid_collider(collider: Variant) -> bool:
	if collider == null or not is_instance_valid(collider):
		return false
	if not collider is PhysicsBody3D:
		return false
	if collider is CharacterBody3D:
		return false

	var body := collider as PhysicsBody3D
	if (body.collision_layer & collision_mask) == 0:
		return false

	var current: Node = body
	while current != null:
		if (
			current.is_in_group(TOKEN_GROUP)
			or current.is_in_group(GRID_3D_EXCLUDED_GROUP)
			or current.is_in_group(GRID_2D_EXCLUDED_GROUP)
		):
			return false
		current = current.get_parent()

	return true


func _prune_stale_cells() -> bool:
	if _visible_cells.is_empty():
		return false

	var now := Time.get_ticks_msec()
	var retention_ms := int(cell_retention_seconds * 1000.0)
	var changed := false

	for key in _visible_cells.keys():
		var cell: Vector3i = key
		var last_seen := int(_visible_cells[key])
		if (
			now - last_seen > retention_ms
			or not _cell_inside_current_volume(cell)
		):
			_visible_cells.erase(cell)
			changed = true

	return changed


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
			+ display_offset_cells * cell_size
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
