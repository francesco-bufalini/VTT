extends Node3D

const GRID_3D_EXCLUDED_GROUP := "grid_3d_excluded"
const GRID_2D_EXCLUDED_GROUP := "grid_2d_excluded"
const TOKEN_GROUP := "dnd_token"
const INVALID_CELL := Vector3i(2147483647, 2147483647, 2147483647)
const CHUNK_SIZE := 8

@export var cell_size: float = 1.0
# Legacy: kept so older scenes keep loading without missing-property warnings.
@export_range(4, 100, 1) var cells_per_side: int = 70
@export_flags_3d_physics var collision_mask: int = 1

# Large camera-oriented view volume. Physics is NOT rescanned when the camera
# moves through already cached chunks.
@export_range(12, 96, 1) var forward_cells: int = 56
@export_range(0, 12, 1) var behind_cells: int = 4
@export_range(4, 40, 1) var half_width_cells: int = 22
@export_range(3, 28, 1) var half_height_cells: int = 14
@export_range(1.0, 30.0, 0.5) var camera_rotation_threshold_degrees: float = 7.5

# New chunks are filled progressively. Collision AABBs first reduce each
# chunk to a small candidate set; only those cells reach a physics query.
@export_range(16, 2048, 1) var max_physics_queries_per_frame: int = 128
@export_range(1, 32, 1) var max_query_results: int = 8
@export_range(0.75, 0.99, 0.005) var collision_probe_scale: float = 0.90
# Visual-only displacement of occupied grid cells. Useful for walkable
# surface grids: -0.5 on Y puts the top face of a voxel on the collision
# surface instead of centering the voxel around it.
@export var display_offset_cells: Vector3 = Vector3.ZERO
@export_range(0.25, 5.0, 0.25) var map_change_check_interval: float = 0.75
@export_range(64, 8192, 64) var max_cached_chunks: int = 2048

var _camera: Camera3D = null
var _grid_mesh_instance: MultiMeshInstance3D = null
var _multimesh: MultiMesh = null
var _grid_material: StandardMaterial3D = null
var _interaction_strength: float = 0.55
var _surface_overlay_bias_cells: float = 0.0

var _cell_probe_shape: BoxShape3D = null
var _cell_query: PhysicsShapeQueryParameters3D = null

var _center_cell: Vector3i = INVALID_CELL
var _volume_transform: Transform3D = Transform3D.IDENTITY
var _has_volume_transform: bool = false
var _half_extent_world: float = 56.5

# Vector3i chunk -> Dictionary(Vector3i cell -> true). Empty dictionaries are
# cached too, so empty space is never queried again until geometry changes.
var _chunk_cache: Dictionary = {}
var _visible_chunks: Dictionary = {}
var _queued_chunks: Dictionary = {}
var _chunk_queue: Array[Vector3i] = []
var _chunk_queue_index: int = 0

var _scan_chunk: Vector3i = INVALID_CELL
var _scan_cells: Array[Vector3i] = []
var _scan_index: int = 0
var _scan_occupied: Dictionary = {}

var _active_occupied: Dictionary = {}
var _visual_dirty: bool = true
var _view_dirty: bool = true
var _was_visible: bool = false

# Collision-shape tracking is used only to invalidate cached chunks when the
# map really changes. Camera movement never invalidates collision data.
var _tracked_shapes: Dictionary = {}
var _shape_signatures: Dictionary = {}
var _shape_bounds: Dictionary = {}
var _signature_elapsed: float = 999.0


func _ready() -> void:
	_configure_grid()
	_build_multimesh()
	_register_existing_map_shapes()

	get_tree().node_added.connect(_on_tree_node_added)
	get_tree().node_removed.connect(_on_tree_node_removed)


func _physics_process(delta: float) -> void:
	if not visible:
		_was_visible = false
		return
	if _camera == null or not is_instance_valid(_camera):
		return

	if not _was_visible:
		_was_visible = true
		_capture_volume_transform()
		_view_dirty = true

	var next_center := _world_to_cell(_camera.global_position)
	var center_changed := next_center != _center_cell
	var rotation_changed := _camera_rotation_changed()
	if center_changed:
		_center_cell = next_center

	if center_changed or rotation_changed:
		_capture_volume_transform()
		_view_dirty = true

	_signature_elapsed += delta
	if _signature_elapsed >= map_change_check_interval:
		_signature_elapsed = 0.0
		_check_map_shape_signatures(false)

	if _view_dirty:
		_refresh_visible_chunks()
		_view_dirty = false

	_process_chunk_scans()

	if _visual_dirty:
		_update_multimesh_instances()
		_visual_dirty = false


func set_camera(new_camera: Camera3D) -> void:
	_camera = new_camera
	_center_cell = INVALID_CELL
	_has_volume_transform = false
	_view_dirty = true


func mark_map_dirty() -> void:
	_clear_collision_cache()
	_check_map_shape_signatures(true)
	_view_dirty = true


func refresh() -> void:
	mark_map_dirty()


func set_interaction_strength(value: float) -> void:
	_interaction_strength = clampf(value, 0.0, 1.0)
	_apply_material_strength()


func set_surface_overlay_bias_cells(value: float) -> void:
	_surface_overlay_bias_cells = clampf(value, 0.0, 0.25)
	var overlay_enabled: bool = _surface_overlay_bias_cells > 0.0
	if _grid_material != null:
		# In Vista 2D la griglia deve essere un overlay reale. Un semplice
		# offset geometrico non basta perché mappa e fog sono nel pass
		# trasparente e possono essere ordinati dopo le linee della griglia.
		_grid_material.no_depth_test = overlay_enabled
		_grid_material.render_priority = 127 if overlay_enabled else 0
	_visual_dirty = true


func get_half_extent_world() -> float:
	return _half_extent_world


func contains_world_point(point: Vector3) -> bool:
	if not _has_volume_transform:
		return false
	return _point_inside_volume(point)


func get_ray_exit_distance(origin: Vector3, direction: Vector3) -> float:
	if not _has_volume_transform:
		return 0.0

	var inverse := _volume_transform.affine_inverse()
	var local_origin: Vector3 = inverse * origin
	var local_direction: Vector3 = (
		_volume_transform.basis.inverse() * direction.normalized()
	)
	if local_direction.length_squared() < 0.000001:
		return 0.0

	var limits := _local_volume_limits()
	var min_point: Vector3 = limits["min"]
	var max_point: Vector3 = limits["max"]
	var t_min := -INF
	var t_max := INF

	for axis in range(3):
		var o: float = local_origin[axis]
		var d: float = local_direction[axis]
		var min_axis: float = min_point[axis]
		var max_axis: float = max_point[axis]

		if absf(d) < 0.000001:
			if o < min_axis or o > max_axis:
				return 0.0
			continue

		var t_a: float = (min_axis - o) / d
		var t_b: float = (max_axis - o) / d
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
	forward_cells = maxi(1, forward_cells)
	behind_cells = maxi(0, behind_cells)
	half_width_cells = maxi(1, half_width_cells)
	half_height_cells = maxi(1, half_height_cells)
	_half_extent_world = (
		float(maxi(forward_cells, maxi(half_width_cells, half_height_cells)))
		+ 0.5
	) * cell_size

	_cell_probe_shape = BoxShape3D.new()
	_cell_probe_shape.size = (
		Vector3.ONE
		* cell_size
		* clampf(collision_probe_scale, 0.75, 0.99)
	)
	_cell_query = PhysicsShapeQueryParameters3D.new()
	_cell_query.shape = _cell_probe_shape
	_cell_query.collide_with_bodies = true
	_cell_query.collide_with_areas = false


func _build_multimesh() -> void:
	if _grid_mesh_instance != null and is_instance_valid(_grid_mesh_instance):
		_grid_mesh_instance.queue_free()

	_grid_material = StandardMaterial3D.new()
	_grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var overlay_enabled: bool = _surface_overlay_bias_cells > 0.0
	_grid_material.no_depth_test = overlay_enabled
	_grid_material.render_priority = 127 if overlay_enabled else 0
	_apply_material_strength()

	var wire_cube := ImmediateMesh.new()
	wire_cube.surface_begin(Mesh.PRIMITIVE_LINES, _grid_material)

	var half := cell_size * 0.495
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
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
		Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
	]
	for edge in edges:
		wire_cube.surface_add_vertex(corners[edge.x])
		wire_cube.surface_add_vertex(corners[edge.y])
	wire_cube.surface_end()

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = wire_cube
	_multimesh.instance_count = 0

	_grid_mesh_instance = MultiMeshInstance3D.new()
	_grid_mesh_instance.name = "CachedCollisionGrid3D"
	_grid_mesh_instance.multimesh = _multimesh
	_grid_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grid_mesh_instance)


func _apply_material_strength() -> void:
	if _grid_material == null:
		return
	var alpha: float = lerpf(0.16, 0.50, _interaction_strength)
	# Warm, desaturated cartographic tone: keeps the current readability while
	# feeling closer to a tabletop D&D map than a neon videogame overlay.
	_grid_material.albedo_color = Color(0.72, 0.67, 0.56, alpha)
	_grid_material.emission_enabled = true
	_grid_material.emission = Color(0.13, 0.10, 0.065, 1.0)
	_grid_material.emission_energy_multiplier = (
		lerpf(0.10, 0.22, _interaction_strength)
	)


func _capture_volume_transform() -> void:
	if _camera == null or not is_instance_valid(_camera):
		_has_volume_transform = false
		return
	_volume_transform = _camera.global_transform
	_has_volume_transform = true


func _camera_rotation_changed() -> bool:
	if (
		not _has_volume_transform
		or _camera == null
		or not is_instance_valid(_camera)
	):
		return true

	var old_forward: Vector3 = -_volume_transform.basis.z.normalized()
	var new_forward: Vector3 = -_camera.global_transform.basis.z.normalized()
	var dot_value: float = clampf(old_forward.dot(new_forward), -1.0, 1.0)
	return (
		rad_to_deg(acos(dot_value))
		>= camera_rotation_threshold_degrees
	)


func _local_volume_limits() -> Dictionary:
	var width: float = (float(half_width_cells) + 0.5) * cell_size
	var height: float = (float(half_height_cells) + 0.5) * cell_size
	var front: float = (float(forward_cells) + 0.5) * cell_size
	var behind: float = (float(behind_cells) + 0.5) * cell_size
	return {
		"min": Vector3(-width, -height, -front),
		"max": Vector3(width, height, behind)
	}


func _point_inside_volume(point: Vector3) -> bool:
	if not _has_volume_transform:
		return false
	var local: Vector3 = _volume_transform.affine_inverse() * point
	var limits := _local_volume_limits()
	var min_point: Vector3 = limits["min"]
	var max_point: Vector3 = limits["max"]
	return (
		local.x >= min_point.x
		and local.x <= max_point.x
		and local.y >= min_point.y
		and local.y <= max_point.y
		and local.z >= min_point.z
		and local.z <= max_point.z
	)


func _volume_world_bounds() -> Dictionary:
	var limits := _local_volume_limits()
	var min_local: Vector3 = limits["min"]
	var max_local: Vector3 = limits["max"]
	var first := true
	var min_world := Vector3.ZERO
	var max_world := Vector3.ZERO

	for x in [min_local.x, max_local.x]:
		for y in [min_local.y, max_local.y]:
			for z in [min_local.z, max_local.z]:
				var point: Vector3 = _volume_transform * Vector3(x, y, z)
				if first:
					min_world = point
					max_world = point
					first = false
				else:
					min_world = min_world.min(point)
					max_world = max_world.max(point)

	return {"min": min_world, "max": max_world}


func _refresh_visible_chunks() -> void:
	_visible_chunks.clear()
	_active_occupied.clear()

	if not _has_volume_transform:
		_visual_dirty = true
		return

	var bounds := _volume_world_bounds()
	var min_point: Vector3 = bounds["min"]
	var max_point: Vector3 = bounds["max"]
	var min_chunk := _world_to_chunk(min_point)
	var max_chunk := _world_to_chunk(max_point)

	for y in range(min_chunk.y, max_chunk.y + 1):
		for z in range(min_chunk.z, max_chunk.z + 1):
			for x in range(min_chunk.x, max_chunk.x + 1):
				var chunk := Vector3i(x, y, z)
				if not _chunk_might_touch_volume(chunk):
					continue

				_visible_chunks[chunk] = true
				if _chunk_cache.has(chunk):
					_add_cached_chunk_to_active(chunk)
				else:
					_enqueue_chunk(chunk)

	_visual_dirty = true
	_prune_chunk_cache()


func _chunk_might_touch_volume(chunk: Vector3i) -> bool:
	var center := _chunk_world_center(chunk)
	var local: Vector3 = _volume_transform.affine_inverse() * center
	var limits := _local_volume_limits()
	var min_point: Vector3 = limits["min"]
	var max_point: Vector3 = limits["max"]
	# A chunk is axis-aligned in world space; use its half diagonal as a
	# conservative expansion in camera-local space.
	var padding := (
		float(CHUNK_SIZE) * cell_size * 0.5 * sqrt(3.0)
	)
	return (
		local.x >= min_point.x - padding
		and local.x <= max_point.x + padding
		and local.y >= min_point.y - padding
		and local.y <= max_point.y + padding
		and local.z >= min_point.z - padding
		and local.z <= max_point.z + padding
	)


func _enqueue_chunk(chunk: Vector3i) -> void:
	if _chunk_cache.has(chunk) or _queued_chunks.has(chunk):
		return
	_queued_chunks[chunk] = true
	_chunk_queue.append(chunk)


func _process_chunk_scans() -> void:
	var budget := maxi(1, max_physics_queries_per_frame)
	var queries := 0

	while queries < budget:
		if _scan_chunk == INVALID_CELL:
			if not _start_next_chunk_scan():
				break
			_build_current_chunk_cells()
			if _scan_cells.is_empty():
				_finish_current_chunk()
				continue

		while _scan_index < _scan_cells.size() and queries < budget:
			var cell: Vector3i = _scan_cells[_scan_index]
			_scan_index += 1
			queries += 1
			if _cell_intersects_map(cell):
				_scan_occupied[cell] = true

		if _scan_index >= _scan_cells.size():
			_finish_current_chunk()


func _start_next_chunk_scan() -> bool:
	while _chunk_queue_index < _chunk_queue.size():
		var chunk: Vector3i = _chunk_queue[_chunk_queue_index]
		_chunk_queue_index += 1
		_queued_chunks.erase(chunk)

		if _chunk_cache.has(chunk):
			continue
		if not _visible_chunks.has(chunk):
			continue

		_scan_chunk = chunk
		_scan_cells.clear()
		_scan_index = 0
		_scan_occupied.clear()
		return true

	if _chunk_queue_index >= _chunk_queue.size():
		_chunk_queue.clear()
		_chunk_queue_index = 0
	return false


func _build_current_chunk_cells() -> void:
	# Use collision bounds as a cheap broad phase. Only cells close enough to
	# an actual map CollisionShape reach the expensive physics query.
	var chunk_min := _chunk_min_cell(_scan_chunk)
	var chunk_max := chunk_min + Vector3i.ONE * (CHUNK_SIZE - 1)
	var candidates: Dictionary = {}
	var expand := Vector3.ONE * (cell_size * 0.51)

	for value in _shape_bounds.values():
		if not value is AABB:
			continue
		var bounds: AABB = value
		if bounds.size.length_squared() <= 0.000001:
			continue

		var shape_min := _world_to_cell(bounds.position - expand)
		var shape_max := _world_to_cell(
			bounds.position + bounds.size + expand
		)
		var min_cell := Vector3i(
			maxi(chunk_min.x, shape_min.x),
			maxi(chunk_min.y, shape_min.y),
			maxi(chunk_min.z, shape_min.z)
		)
		var max_cell := Vector3i(
			mini(chunk_max.x, shape_max.x),
			mini(chunk_max.y, shape_max.y),
			mini(chunk_max.z, shape_max.z)
		)
		if (
			min_cell.x > max_cell.x
			or min_cell.y > max_cell.y
			or min_cell.z > max_cell.z
		):
			continue

		for y in range(min_cell.y, max_cell.y + 1):
			for z in range(min_cell.z, max_cell.z + 1):
				for x in range(min_cell.x, max_cell.x + 1):
					candidates[Vector3i(x, y, z)] = true

	for key in candidates.keys():
		_scan_cells.append(key)


func _finish_current_chunk() -> void:
	if _scan_chunk == INVALID_CELL:
		return

	_chunk_cache[_scan_chunk] = _scan_occupied.duplicate()
	if _visible_chunks.has(_scan_chunk):
		for key in _scan_occupied.keys():
			var cell: Vector3i = key
			if _point_inside_volume(_cell_to_world_center(cell)):
				_active_occupied[cell] = true
		_visual_dirty = true

	_scan_chunk = INVALID_CELL
	_scan_cells.clear()
	_scan_index = 0
	_scan_occupied.clear()


func _cell_intersects_map(cell: Vector3i) -> bool:
	if _cell_query == null:
		return false
	_cell_query.collision_mask = collision_mask
	_cell_query.transform = Transform3D(
		Basis.IDENTITY,
		_cell_to_world_center(cell)
	)

	var hits: Array[Dictionary] = (
		get_world_3d().direct_space_state.intersect_shape(
			_cell_query,
			maxi(1, max_query_results)
		)
	)
	for hit in hits:
		if _is_map_collider(hit.get("collider")):
			return true
	return false


func _is_map_collider(collider: Variant) -> bool:
	if collider == null or not is_instance_valid(collider):
		return false
	if not collider is PhysicsBody3D:
		return false
	if collider is CharacterBody3D:
		return false

	var body := collider as PhysicsBody3D
	if (body.collision_layer & collision_mask) == 0:
		return false
	return not _has_excluded_group_in_ancestry(body)


func _has_excluded_group_in_ancestry(node: Node) -> bool:
	var current: Node = node
	while current != null:
		if (
			current.is_in_group(TOKEN_GROUP)
			or current.is_in_group(GRID_3D_EXCLUDED_GROUP)
			or current.is_in_group(GRID_2D_EXCLUDED_GROUP)
		):
			return true
		current = current.get_parent()
	return false


func _add_cached_chunk_to_active(chunk: Vector3i) -> void:
	var value: Variant = _chunk_cache.get(chunk)
	if not value is Dictionary:
		return
	var occupied: Dictionary = value
	for key in occupied.keys():
		var cell: Vector3i = key
		if _point_inside_volume(_cell_to_world_center(cell)):
			_active_occupied[cell] = true


func _update_multimesh_instances() -> void:
	if _multimesh == null:
		return

	var count := _active_occupied.size()
	_multimesh.instance_count = count
	_multimesh.visible_instance_count = count
	if count == 0:
		return

	var inverse_grid_transform := global_transform.affine_inverse()
	var index := 0
	for key in _active_occupied.keys():
		var cell: Vector3i = key
		var world_transform := Transform3D(
			Basis.IDENTITY,
			_cell_to_world_center(cell)
			+ display_offset_cells * cell_size
			+ Vector3.UP * _surface_overlay_bias_cells * cell_size
		)
		_multimesh.set_instance_transform(
			index,
			inverse_grid_transform * world_transform
		)
		index += 1


func _remove_chunk_from_active(chunk: Vector3i) -> void:
	var stale: Array[Vector3i] = []
	for key in _active_occupied.keys():
		var cell: Vector3i = key
		if _cell_to_chunk(cell) == chunk:
			stale.append(cell)
	for cell in stale:
		_active_occupied.erase(cell)
	if not stale.is_empty():
		_visual_dirty = true


func _clear_collision_cache() -> void:
	_chunk_cache.clear()
	_queued_chunks.clear()
	_chunk_queue.clear()
	_chunk_queue_index = 0
	_scan_chunk = INVALID_CELL
	_scan_cells.clear()
	_scan_index = 0
	_scan_occupied.clear()
	_active_occupied.clear()
	_visual_dirty = true


func _prune_chunk_cache() -> void:
	if _chunk_cache.size() <= max_cached_chunks:
		return

	var retained: Dictionary = {}
	# Always keep the currently visible area.
	for key in _visible_chunks.keys():
		if _chunk_cache.has(key):
			retained[key] = _chunk_cache[key]

	# Keep nearby cached chunks until the limit is reached.
	if retained.size() < max_cached_chunks:
		var camera_chunk := _world_to_chunk(_camera.global_position)
		var candidates: Array[Dictionary] = []
		for key in _chunk_cache.keys():
			if retained.has(key):
				continue
			var chunk: Vector3i = key
			candidates.append({
				"chunk": chunk,
				"distance": (
					Vector3(chunk - camera_chunk).length_squared()
				)
			})
		candidates.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return float(a["distance"]) < float(b["distance"])
		)
		for item in candidates:
			if retained.size() >= max_cached_chunks:
				break
			var chunk: Vector3i = item["chunk"]
			retained[chunk] = _chunk_cache[chunk]

	_chunk_cache = retained


func pick_visible_top_cell_from_ray(
	origin: Vector3,
	direction: Vector3,
	max_distance: float
) -> Dictionary:
	if _active_occupied.is_empty() or max_distance <= 0.0:
		return {}

	var ray_direction := direction.normalized()
	if ray_direction.length_squared() < 0.000001:
		return {}

	# Token placement must follow the grid the player actually points at, not
	# the collision mesh hidden underneath it. On shallow camera angles a ray
	# can enter the visible top of one voxel and only hit the source mesh one
	# or more cells farther away.
	var safe := maxf(cell_size, 0.001)
	var half := safe * 0.5
	var epsilon := safe * 0.002
	var visual_offset := display_offset_cells * safe
	var best_distance := INF
	var best_cell := INVALID_CELL
	var best_top_center := Vector3.ZERO

	if absf(ray_direction.y) <= 0.000001:
		return {}

	for key: Variant in _active_occupied.keys():
		if not key is Vector3i:
			continue
		var cell: Vector3i = key as Vector3i
		var visual_center := _cell_to_world_center(cell) + visual_offset
		var top_y := visual_center.y + half
		var distance := (top_y - origin.y) / ray_direction.y
		if (
			distance < 0.0
			or distance > max_distance
			or distance >= best_distance
		):
			continue

		var ray_point := origin + ray_direction * distance
		if (
			ray_point.x < visual_center.x - half - epsilon
			or ray_point.x > visual_center.x + half + epsilon
			or ray_point.z < visual_center.z - half - epsilon
			or ray_point.z > visual_center.z + half + epsilon
		):
			continue

		best_distance = distance
		best_cell = cell
		best_top_center = Vector3(
			visual_center.x,
			top_y,
			visual_center.z
		)

	if best_cell == INVALID_CELL:
		return {}

	return {
		"valid": true,
		"cell": best_cell,
		"top_center": best_top_center,
		"distance": best_distance,
	}


func get_support_top_y(
	world_point: Vector3,
	max_y: float,
	min_y: float
) -> float:
	if max_y < min_y:
		var swap_y := max_y
		max_y = min_y
		min_y = swap_y

	var safe := maxf(cell_size, 0.001)
	var x_cell := int(floor(world_point.x / safe))
	var z_cell := int(floor(world_point.z / safe))

	# The rendered cube can be displaced from the collision-probe cell.
	# Search a small guard band so a token already intersecting a cell is
	# repaired upward instead of being allowed to continue through it.
	var max_cell_y := int(floor(max_y / safe)) + 2
	var min_cell_y := int(floor(min_y / safe)) - 2
	var epsilon := safe * 0.02

	for y_cell: int in range(max_cell_y, min_cell_y - 1, -1):
		var cell := Vector3i(x_cell, y_cell, z_cell)
		if not _support_cell_is_occupied(cell):
			continue
		var top_y := _cell_visual_top_y(cell)
		if (
			top_y <= max_y + safe * 0.55
			and top_y >= min_y - epsilon
		):
			return top_y

	return INF


func get_support_top_for_footprint(
	world_center: Vector3,
	footprint_cells: float,
	max_y: float,
	min_y: float
) -> float:
	var safe_footprint := maxf(footprint_cells, 0.5)
	var rounded := maxi(1, roundi(safe_footprint))
	var samples: Array[Vector2] = []

	if (
		is_equal_approx(safe_footprint, float(rounded))
		and rounded > 1
	):
		var first_offset := -float(rounded - 1) * 0.5
		for x_index: int in range(rounded):
			for z_index: int in range(rounded):
				samples.append(
					Vector2(
						first_offset + float(x_index),
						first_offset + float(z_index)
					)
				)
	else:
		samples.append(Vector2.ZERO)

	var highest := -INF
	for sample: Vector2 in samples:
		var point := world_center + Vector3(
			sample.x * cell_size,
			0.0,
			sample.y * cell_size
		)
		var support_y := get_support_top_y(point, max_y, min_y)
		if support_y < INF:
			highest = maxf(highest, support_y)

	return INF if highest == -INF else highest


func _support_cell_is_occupied(cell: Vector3i) -> bool:
	if _active_occupied.has(cell):
		return true

	var chunk := _cell_to_chunk(cell)
	var cached_value: Variant = _chunk_cache.get(chunk)
	if cached_value is Dictionary:
		var cached: Dictionary = cached_value as Dictionary
		if cached.has(cell):
			return true

	# A token may be falling over a chunk that has not been scanned yet.
	# Query the same collision definition used to construct the visible grid,
	# so the tactical grid remains authoritative even before rendering catches
	# up with the camera.
	if not _point_inside_volume(_cell_to_world_center(cell)):
		return false
	return _cell_intersects_map(cell)


func _cell_visual_top_y(cell: Vector3i) -> float:
	return (
		_cell_to_world_center(cell).y
		+ display_offset_cells.y * cell_size
		+ cell_size * 0.5
	)


func _world_to_cell(point: Vector3) -> Vector3i:
	var safe := maxf(cell_size, 0.001)
	return Vector3i(
		int(floor(point.x / safe)),
		int(floor(point.y / safe)),
		int(floor(point.z / safe))
	)


func _cell_to_world_center(cell: Vector3i) -> Vector3:
	return Vector3(
		(float(cell.x) + 0.5) * cell_size,
		(float(cell.y) + 0.5) * cell_size,
		(float(cell.z) + 0.5) * cell_size
	)


func _world_to_chunk(point: Vector3) -> Vector3i:
	return _cell_to_chunk(_world_to_cell(point))


func _cell_to_chunk(cell: Vector3i) -> Vector3i:
	return Vector3i(
		int(floor(float(cell.x) / float(CHUNK_SIZE))),
		int(floor(float(cell.y) / float(CHUNK_SIZE))),
		int(floor(float(cell.z) / float(CHUNK_SIZE)))
	)


func _chunk_min_cell(chunk: Vector3i) -> Vector3i:
	return chunk * CHUNK_SIZE


func _chunk_world_center(chunk: Vector3i) -> Vector3:
	var min_cell := _chunk_min_cell(chunk)
	return Vector3(
		(float(min_cell.x) + float(CHUNK_SIZE) * 0.5) * cell_size,
		(float(min_cell.y) + float(CHUNK_SIZE) * 0.5) * cell_size,
		(float(min_cell.z) + float(CHUNK_SIZE) * 0.5) * cell_size
	)


func _register_existing_map_shapes() -> void:
	if get_tree() == null or get_tree().root == null:
		return
	for node in get_tree().root.find_children(
		"*",
		"CollisionShape3D",
		true,
		false
	):
		_register_map_shape(node as CollisionShape3D)


func _on_tree_node_added(node: Node) -> void:
	if node is CollisionShape3D:
		# Never keep the CollisionShape3D itself as a deferred argument.
		# Runtime terrain builders can add and free a shape in the same frame;
		# by the time the deferred call runs that Object may already be freed.
		# An integer instance id remains safe to pass through the queue.
		call_deferred(
			"_register_added_collision_shape_by_id",
			node.get_instance_id()
		)


func _register_added_collision_shape_by_id(instance_id: int) -> void:
	var value: Object = instance_from_id(instance_id)
	if value == null or not is_instance_valid(value):
		return
	if not value is CollisionShape3D:
		return

	var collision := value as CollisionShape3D
	if _register_map_shape(collision):
		var bounds: AABB = _collision_world_aabb(collision)
		_invalidate_chunks_for_aabb(bounds)


func _on_tree_node_removed(node: Node) -> void:
	var id := node.get_instance_id()
	if not _tracked_shapes.has(id):
		return

	var old_bounds_value: Variant = _shape_bounds.get(id)
	if old_bounds_value is AABB:
		_invalidate_chunks_for_aabb(old_bounds_value)

	_tracked_shapes.erase(id)
	_shape_signatures.erase(id)
	_shape_bounds.erase(id)


func _register_map_shape(collision: CollisionShape3D) -> bool:
	if collision == null or not is_instance_valid(collision):
		return false
	if collision.shape == null:
		return false

	var body := _find_physics_body(collision)
	if body == null or not _is_map_collider(body):
		return false

	var id := collision.get_instance_id()
	if _tracked_shapes.has(id):
		return false

	_tracked_shapes[id] = collision
	_shape_signatures[id] = _collision_shape_signature(collision, body)
	_shape_bounds[id] = _collision_world_aabb(collision)
	return true


func _find_physics_body(node: Node) -> PhysicsBody3D:
	var current := node.get_parent()
	while current != null:
		if current is Area3D:
			return null
		if current is PhysicsBody3D:
			return current as PhysicsBody3D
		current = current.get_parent()
	return null


func _check_map_shape_signatures(discover_new: bool) -> void:
	if discover_new:
		_discover_untracked_map_shapes()

	var stale: Array[int] = []
	for key in _tracked_shapes.keys():
		var id: int = int(key)
		var value: Variant = _tracked_shapes[id]
		if not is_instance_valid(value):
			stale.append(id)
			continue

		var collision := value as CollisionShape3D
		var body := _find_physics_body(collision)
		if (
			body == null
			or collision.shape == null
			or not _is_map_collider(body)
		):
			stale.append(id)
			continue

		var signature := _collision_shape_signature(collision, body)
		if String(_shape_signatures.get(id, "")) == signature:
			continue

		var old_bounds_value: Variant = _shape_bounds.get(id)
		if old_bounds_value is AABB:
			_invalidate_chunks_for_aabb(old_bounds_value)

		var new_bounds := _collision_world_aabb(collision)
		_invalidate_chunks_for_aabb(new_bounds)
		_shape_signatures[id] = signature
		_shape_bounds[id] = new_bounds

	for id in stale:
		var old_bounds_value: Variant = _shape_bounds.get(id)
		if old_bounds_value is AABB:
			_invalidate_chunks_for_aabb(old_bounds_value)
		_tracked_shapes.erase(id)
		_shape_signatures.erase(id)
		_shape_bounds.erase(id)


func _discover_untracked_map_shapes() -> void:
	if get_tree() == null or get_tree().root == null:
		return
	for node in get_tree().root.find_children(
		"*",
		"CollisionShape3D",
		true,
		false
	):
		var collision := node as CollisionShape3D
		if collision != null and _register_map_shape(collision):
			_invalidate_chunks_for_aabb(_collision_world_aabb(collision))


func _collision_shape_signature(
	collision: CollisionShape3D,
	body: PhysicsBody3D
) -> String:
	var shape_id := 0
	var shape_class := "none"
	if collision.shape != null:
		shape_id = collision.shape.get_instance_id()
		shape_class = collision.shape.get_class()
	return "%s|%s|%s|%s|%s|%s" % [
		str(collision.global_transform),
		str(collision.disabled),
		str(body.collision_layer),
		str(body.global_transform),
		shape_class,
		str(shape_id)
	]


func _collision_world_aabb(collision: CollisionShape3D) -> AABB:
	if (
		collision == null
		or not is_instance_valid(collision)
		or collision.shape == null
	):
		return AABB(Vector3.ZERO, Vector3.ZERO)

	var local_aabb := AABB(Vector3.ZERO, Vector3.ZERO)
	var has_bounds := false
	if collision.shape.has_method("get_debug_mesh"):
		var debug_mesh: Variant = collision.shape.call("get_debug_mesh")
		if debug_mesh is Mesh:
			local_aabb = (debug_mesh as Mesh).get_aabb()
			has_bounds = true

	if not has_bounds:
		return AABB(collision.global_position, Vector3.ONE * cell_size)

	var min_local := local_aabb.position
	var max_local := local_aabb.position + local_aabb.size
	var first := true
	var min_world := Vector3.ZERO
	var max_world := Vector3.ZERO

	for x in [min_local.x, max_local.x]:
		for y in [min_local.y, max_local.y]:
			for z in [min_local.z, max_local.z]:
				var point := collision.global_transform * Vector3(x, y, z)
				if first:
					min_world = point
					max_world = point
					first = false
				else:
					min_world = min_world.min(point)
					max_world = max_world.max(point)

	return AABB(min_world, max_world - min_world)


func _invalidate_chunks_for_aabb(bounds: AABB) -> void:
	if bounds.size.length_squared() <= 0.000001:
		return

	var padding := Vector3.ONE * cell_size
	var min_chunk := _world_to_chunk(bounds.position - padding)
	var max_chunk := _world_to_chunk(
		bounds.position + bounds.size + padding
	)

	for y in range(min_chunk.y, max_chunk.y + 1):
		for z in range(min_chunk.z, max_chunk.z + 1):
			for x in range(min_chunk.x, max_chunk.x + 1):
				var chunk := Vector3i(x, y, z)
				_chunk_cache.erase(chunk)
				_remove_chunk_from_active(chunk)
				if chunk == _scan_chunk:
					_scan_chunk = INVALID_CELL
					_scan_cells.clear()
					_scan_index = 0
					_scan_occupied.clear()
				if _visible_chunks.has(chunk):
					_enqueue_chunk(chunk)

	_visual_dirty = true
