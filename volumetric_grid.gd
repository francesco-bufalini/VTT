extends Node3D

const GRID_3D_EXCLUDED_GROUP := "grid_3d_excluded"
const GRID_2D_EXCLUDED_GROUP := "grid_2d_excluded"
const TOKEN_GROUP := "dnd_token"
const INVALID_CELL := Vector3i(2147483647, 2147483647, 2147483647)

@export var cell_size: float = 1.0
# Legacy: mantenuto per compatibilita con scene salvate prima del volume
# orientato. Non determina piu direttamente il volume visualizzato.
@export_range(4, 100, 1) var cells_per_side: int = 70
@export_flags_3d_physics var collision_mask: int = 1

# Volume di scansione orientato con la camera. Il prisma parte solo due celle
# dietro la camera e si estende soprattutto nella direzione di vista.
@export_range(8, 60, 1) var forward_cells: int = 30
@export_range(0, 8, 1) var behind_cells: int = 2
@export_range(2, 24, 1) var half_width_cells: int = 12
@export_range(2, 20, 1) var half_height_cells: int = 8
@export_range(1.0, 20.0, 0.5) var camera_rotation_threshold_degrees: float = 5.0

# Query distribuite su piu physics frame: un budget piu basso evita picchi.
@export_range(1, 2048, 1) var max_cell_tests_per_frame: int = 128
@export_range(1, 32, 1) var max_query_results: int = 8
@export_range(1000, 250000, 1000) var max_cached_cells: int = 120000
@export_range(0.25, 5.0, 0.25) var map_change_check_interval: float = 1.0

# Il probe e leggermente piu piccolo della cella: in questo modo il semplice
# contatto con la collisione della cella adiacente non crea cubi d'aria.
@export_range(0.80, 1.0, 0.005) var collision_probe_scale: float = 0.96

var _camera: Camera3D = null
var _grid_mesh_instance: MultiMeshInstance3D = null
var _multimesh: MultiMesh = null
var _grid_material: StandardMaterial3D = null
var _interaction_strength: float = 0.55
var _cell_query_shape: BoxShape3D = null
var _query_parameters: PhysicsShapeQueryParameters3D = null

var _center_cell: Vector3i = INVALID_CELL
var _half_extent_world: float = 30.5
var _volume_transform: Transform3D = Transform3D.IDENTITY
var _has_volume_transform: bool = false

# Cache globale delle celle già testate: Vector3i -> bool.
# Quando la camera si sposta di una cella, in genere bisogna interrogare solo
# il nuovo "strato" entrato nel volume, non tutte le celle del 70^3.
var _cell_cache: Dictionary = {}
var _active_occupied: Dictionary = {}

var _pending_cells: Array[Vector3i] = []
var _pending_lookup: Dictionary = {}
var _pending_index: int = 0

var _map_dirty: bool = true
var _was_visible: bool = false
var _signature_elapsed: float = 0.0
var _tracked_map_shapes: Dictionary = {}
var _shape_signatures: Dictionary = {}


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

	if not _was_visible:
		_was_visible = true
		_check_map_shape_signatures(true)

	if _camera == null or not is_instance_valid(_camera):
		return

	_signature_elapsed += delta
	if _signature_elapsed >= map_change_check_interval:
		_signature_elapsed = 0.0
		_check_map_shape_signatures(false)

	var next_center := _world_to_cell(_camera.global_position)
	var center_changed := next_center != _center_cell
	var rotation_changed := _camera_rotation_changed()
	if center_changed:
		_center_cell = next_center

	if _map_dirty:
		_cell_cache.clear()
		_active_occupied.clear()
		_map_dirty = false
		_capture_volume_transform()
		_schedule_full_volume()
	elif center_changed or rotation_changed:
		_capture_volume_transform()
		_schedule_full_volume()

	_process_pending_cells()


func set_camera(new_camera: Camera3D) -> void:
	_camera = new_camera
	_center_cell = INVALID_CELL
	_has_volume_transform = false


func mark_map_dirty() -> void:
	# Le query vengono rifatte nel prossimo physics frame, e solo se la griglia
	# è visibile. In questo modo le modifiche alla scena non causano lavoro
	# inutile quando la griglia 3D è spenta.
	_map_dirty = true


func refresh() -> void:
	mark_map_dirty()


func set_interaction_strength(value: float) -> void:
	_interaction_strength = clampf(value, 0.0, 1.0)
	_apply_material_strength()


func _apply_material_strength() -> void:
	if _grid_material == null:
		return
	var alpha: float = lerpf(0.18, 0.52, _interaction_strength)
	_grid_material.albedo_color = Color(0.42, 0.75, 1.0, alpha)
	_grid_material.emission_enabled = true
	_grid_material.emission = Color(0.04, 0.22, 0.38, 1.0)
	_grid_material.emission_energy_multiplier = (
		lerpf(0.30, 0.70, _interaction_strength)
	)


func get_half_extent_world() -> float:
	return _half_extent_world


func contains_world_point(point: Vector3) -> bool:
	if not _has_volume_transform:
		return false
	return _point_inside_volume(point)


func get_ray_exit_distance(origin: Vector3, direction: Vector3) -> float:
	if not _has_volume_transform:
		return 0.0

	var local_origin: Vector3 = _volume_transform.affine_inverse() * origin
	var local_direction: Vector3 = (
		_volume_transform.basis.inverse() * direction.normalized()
	)
	if local_direction.length_squared() < 0.000001:
		return 0.0

	var width: float = (float(half_width_cells) + 0.5) * cell_size
	var height: float = (float(half_height_cells) + 0.5) * cell_size
	var front: float = (float(forward_cells) + 0.5) * cell_size
	var behind: float = (float(behind_cells) + 0.5) * cell_size
	var min_point := Vector3(-width, -height, -front)
	var max_point := Vector3(width, height, behind)

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
			var swap: float = t_a
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

	_cell_query_shape = BoxShape3D.new()
	_cell_query_shape.size = (
		Vector3.ONE
		* cell_size
		* clampf(collision_probe_scale, 0.80, 1.0)
	)

	_query_parameters = PhysicsShapeQueryParameters3D.new()
	_query_parameters.shape = _cell_query_shape
	_query_parameters.collision_mask = collision_mask
	_query_parameters.collide_with_bodies = true
	_query_parameters.collide_with_areas = false


func _build_multimesh() -> void:
	if (
		_grid_mesh_instance != null
		and is_instance_valid(_grid_mesh_instance)
	):
		_grid_mesh_instance.queue_free()

	_grid_material = StandardMaterial3D.new()
	_grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
		Vector2i(0, 1),
		Vector2i(1, 2),
		Vector2i(2, 3),
		Vector2i(3, 0),
		Vector2i(4, 5),
		Vector2i(5, 6),
		Vector2i(6, 7),
		Vector2i(7, 4),
		Vector2i(0, 4),
		Vector2i(1, 5),
		Vector2i(2, 6),
		Vector2i(3, 7),
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
	_grid_mesh_instance.name = "CollisionCellGrid3D"
	_grid_mesh_instance.multimesh = _multimesh
	_grid_mesh_instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	add_child(_grid_mesh_instance)


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
	var angle_degrees: float = rad_to_deg(acos(dot_value))
	return angle_degrees >= camera_rotation_threshold_degrees


func _schedule_full_volume() -> void:
	_reset_pending_queue()
	_active_occupied.clear()
	if not _has_volume_transform:
		_update_multimesh_instances()
		return

	var bounds: Dictionary = _volume_world_bounds()
	var min_point: Vector3 = bounds.get("min", Vector3.ZERO)
	var max_point: Vector3 = bounds.get("max", Vector3.ZERO)
	var min_cell: Vector3i = _world_to_cell(min_point)
	var max_cell: Vector3i = _world_to_cell(max_point)

	for y in range(min_cell.y, max_cell.y + 1):
		for z in range(min_cell.z, max_cell.z + 1):
			for x in range(min_cell.x, max_cell.x + 1):
				var cell := Vector3i(x, y, z)
				if _cell_inside_current_volume(cell):
					_enqueue_cell(cell)

	_prune_cache_if_needed()
	_update_multimesh_instances()


func _volume_world_bounds() -> Dictionary:
	var width: float = (float(half_width_cells) + 0.5) * cell_size
	var height: float = (float(half_height_cells) + 0.5) * cell_size
	var front: float = (float(forward_cells) + 0.5) * cell_size
	var behind: float = (float(behind_cells) + 0.5) * cell_size

	var center_local := Vector3(0.0, 0.0, (behind - front) * 0.5)
	var half_depth: float = (front + behind) * 0.5
	var center_world: Vector3 = _volume_transform * center_local
	var basis: Basis = _volume_transform.basis
	var extents := Vector3(
		absf(basis.x.x) * width
			+ absf(basis.y.x) * height
			+ absf(basis.z.x) * half_depth,
		absf(basis.x.y) * width
			+ absf(basis.y.y) * height
			+ absf(basis.z.y) * half_depth,
		absf(basis.x.z) * width
			+ absf(basis.y.z) * height
			+ absf(basis.z.z) * half_depth
	)

	return {
		"min": center_world - extents,
		"max": center_world + extents
	}


func _point_inside_volume(point: Vector3) -> bool:
	if not _has_volume_transform:
		return false

	var local: Vector3 = _volume_transform.affine_inverse() * point
	var width: float = (float(half_width_cells) + 0.5) * cell_size
	var height: float = (float(half_height_cells) + 0.5) * cell_size
	var front: float = (float(forward_cells) + 0.5) * cell_size
	var behind: float = (float(behind_cells) + 0.5) * cell_size

	return (
		absf(local.x) <= width
		and absf(local.y) <= height
		and local.z >= -front
		and local.z <= behind
	)


func _enqueue_cell(cell: Vector3i) -> void:
	if _cell_cache.has(cell):
		if bool(_cell_cache[cell]):
			_active_occupied[cell] = true
		return

	if _pending_lookup.has(cell):
		return

	_pending_lookup[cell] = true
	_pending_cells.append(cell)


func _process_pending_cells() -> void:
	if not _has_pending_cells():
		return

	var tested := 0
	var visual_changed := false
	var budget := maxi(1, max_cell_tests_per_frame)

	while _pending_index < _pending_cells.size() and tested < budget:
		var cell := _pending_cells[_pending_index]
		_pending_index += 1
		_pending_lookup.erase(cell)

		if not _cell_inside_current_volume(cell):
			continue

		if _cell_cache.has(cell):
			if bool(_cell_cache[cell]):
				_active_occupied[cell] = true
				visual_changed = true
			continue

		var occupied := _cell_intersects_map(cell)
		_cell_cache[cell] = occupied
		tested += 1

		if occupied:
			_active_occupied[cell] = true
			visual_changed = true

	if _pending_index >= _pending_cells.size():
		_reset_pending_queue()
		_prune_cache_if_needed()

	if visual_changed:
		_update_multimesh_instances()


func _cell_intersects_map(cell: Vector3i) -> bool:
	if _query_parameters == null or _cell_query_shape == null:
		return false

	_query_parameters.collision_mask = collision_mask
	_query_parameters.transform = Transform3D(
		Basis.IDENTITY,
		_cell_to_world_center(cell)
	)

	var hits: Array[Dictionary] = (
		get_world_3d().direct_space_state.intersect_shape(
			_query_parameters,
			maxi(1, max_query_results)
		)
	)

	for hit in hits:
		var collider: Variant = hit.get("collider")
		if _is_map_collider(collider):
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
	if _has_excluded_group_in_ancestry(body):
		return false

	return true


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
		if not _cell_inside_current_volume(cell):
			continue

		var world_transform := Transform3D(
			Basis.IDENTITY,
			_cell_to_world_center(cell)
		)
		var local_transform := inverse_grid_transform * world_transform
		_multimesh.set_instance_transform(index, local_transform)
		index += 1

	# Normalmente count e index coincidono. Questo protegge comunque da
	# eventuali celle rimosse fra conteggio e aggiornamento.
	if index != count:
		_multimesh.visible_instance_count = index


func _remove_active_cells_outside_volume() -> void:
	for key in _active_occupied.keys():
		var cell: Vector3i = key
		if not _cell_inside_current_volume(cell):
			_active_occupied.erase(cell)


func _reset_pending_queue() -> void:
	_pending_cells.clear()
	_pending_lookup.clear()
	_pending_index = 0


func _has_pending_cells() -> bool:
	return _pending_index < _pending_cells.size()


func _prune_cache_if_needed() -> void:
	if _cell_cache.size() <= max_cached_cells:
		return

	var retained: Dictionary = {}
	for key in _cell_cache.keys():
		var cell: Vector3i = key
		if _cell_inside_current_volume(cell):
			retained[cell] = _cell_cache[cell]
	_cell_cache = retained


func _cell_inside_current_volume(cell: Vector3i) -> bool:
	return _point_inside_volume(_cell_to_world_center(cell))


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


func _world_bounds() -> Dictionary:
	return _volume_world_bounds()


func _register_existing_map_shapes() -> void:
	if get_tree() == null or get_tree().root == null:
		return

	for node in get_tree().root.find_children(
		"*",
		"CollisionShape3D",
		true,
		false
	):
		_register_map_shape(node as CollisionShape3D, false)


func _on_tree_node_added(node: Node) -> void:
	if node is CollisionShape3D:
		call_deferred(
			"_register_added_collision_shape",
			node as CollisionShape3D
		)


func _register_added_collision_shape(
	collision: CollisionShape3D
) -> void:
	if collision == null or not is_instance_valid(collision):
		return

	if _register_map_shape(collision, true):
		mark_map_dirty()


func _on_tree_node_removed(node: Node) -> void:
	var instance_id := node.get_instance_id()
	if not _tracked_map_shapes.has(instance_id):
		return

	_tracked_map_shapes.erase(instance_id)
	_shape_signatures.erase(instance_id)
	mark_map_dirty()


func _register_map_shape(
	collision: CollisionShape3D,
	update_existing_signature: bool
) -> bool:
	if collision == null or not is_instance_valid(collision):
		return false

	var body := _find_physics_body(collision)
	if body == null or not _is_map_collider(body):
		return false

	var instance_id := collision.get_instance_id()
	var was_known := _tracked_map_shapes.has(instance_id)
	_tracked_map_shapes[instance_id] = collision

	if not was_known or update_existing_signature:
		_shape_signatures[instance_id] = (
			_collision_shape_signature(collision, body)
		)

	return not was_known


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

	var changed := false
	var stale_ids: Array[int] = []

	for key in _tracked_map_shapes.keys():
		var instance_id: int = int(key)
		var collision: Variant = _tracked_map_shapes[instance_id]

		if (
			not is_instance_valid(collision)
			or not (collision as CollisionShape3D).is_inside_tree()
		):
			stale_ids.append(instance_id)
			changed = true
			continue

		var collision_shape := collision as CollisionShape3D
		var body := _find_physics_body(collision_shape)
		if body == null or not _is_map_collider(body):
			stale_ids.append(instance_id)
			changed = true
			continue

		var signature := _collision_shape_signature(
			collision_shape,
			body
		)
		if String(_shape_signatures.get(instance_id, "")) != signature:
			_shape_signatures[instance_id] = signature
			changed = true

	for instance_id in stale_ids:
		_tracked_map_shapes.erase(instance_id)
		_shape_signatures.erase(instance_id)

	if changed:
		mark_map_dirty()


func _discover_untracked_map_shapes() -> void:
	if get_tree() == null or get_tree().root == null:
		return

	var discovered := false
	for node in get_tree().root.find_children(
		"*",
		"CollisionShape3D",
		true,
		false
	):
		var collision := node as CollisionShape3D
		if (
			collision != null
			and not _tracked_map_shapes.has(
				collision.get_instance_id()
			)
			and _register_map_shape(collision, false)
		):
			discovered = true

	if discovered:
		mark_map_dirty()


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
