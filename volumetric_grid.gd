extends Node3D

const GRID_3D_EXCLUDED_GROUP := "grid_3d_excluded"
const GRID_2D_EXCLUDED_GROUP := "grid_2d_excluded"
const TOKEN_GROUP := "dnd_token"
const INVALID_CELL := Vector3i(2147483647, 2147483647, 2147483647)

@export var cell_size: float = 1.0
# Volume locale della griglia collision-aware. Con cell_size = 1 il default
# copre esattamente 70 x 70 x 70 metri/celle attorno alla camera.
@export_range(4, 100, 1) var cells_per_side: int = 70
@export_flags_3d_physics var collision_mask: int = 1
# La prima scansione del volume viene distribuita su più physics frame
# per evitare un picco di decine di migliaia di query nello stesso frame.
@export_range(1, 4096, 1) var max_cell_tests_per_frame: int = 768
@export_range(1, 64, 1) var max_query_results: int = 16
@export_range(1000, 1000000, 1000) var max_cached_cells: int = 500000
@export_range(0.1, 5.0, 0.1) var map_change_check_interval: float = 0.5
# Un overlap minimo rende affidabile il rilevamento di collisioni trimesh
# esattamente sul confine fra due celle.
@export_range(1.0, 1.05, 0.001) var collision_probe_scale: float = 1.002

var _camera: Camera3D = null
var _grid_mesh_instance: MultiMeshInstance3D = null
var _multimesh: MultiMesh = null
var _cell_query_shape: BoxShape3D = null
var _query_parameters: PhysicsShapeQueryParameters3D = null

var _center_cell: Vector3i = INVALID_CELL
var _lower_extent_cells: int = 35
var _upper_extent_cells: int = 34
var _half_extent_world: float = 35.0

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

	var old_center := _center_cell
	var next_center := _world_to_cell(_camera.global_position)
	var center_changed := next_center != _center_cell
	if center_changed:
		_center_cell = next_center

	if _map_dirty:
		_cell_cache.clear()
		_active_occupied.clear()
		_map_dirty = false
		_schedule_full_volume()
	elif center_changed:
		_schedule_for_center_change(old_center, next_center)

	_process_pending_cells()


func set_camera(new_camera: Camera3D) -> void:
	_camera = new_camera
	_center_cell = INVALID_CELL


func mark_map_dirty() -> void:
	# Le query vengono rifatte nel prossimo physics frame, e solo se la griglia
	# è visibile. In questo modo le modifiche alla scena non causano lavoro
	# inutile quando la griglia 3D è spenta.
	_map_dirty = true


func refresh() -> void:
	mark_map_dirty()


func get_half_extent_world() -> float:
	return _half_extent_world


func contains_world_point(point: Vector3) -> bool:
	if _center_cell == INVALID_CELL:
		return false

	var bounds := _world_bounds()
	var min_point: Vector3 = bounds["min"]
	var max_point: Vector3 = bounds["max"]
	var epsilon := maxf(cell_size * 0.001, 0.0001)

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

	var bounds := _world_bounds()
	var min_point: Vector3 = bounds["min"]
	var max_point: Vector3 = bounds["max"]

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
	cells_per_side = maxi(4, cells_per_side)

	# Supporta anche volumi pari (default 70x70x70). La cella della camera
	# resta inclusa; con un numero pari c'e inevitabilmente una cella in piu
	# su un lato rispetto all'altro.
	_lower_extent_cells = int(floor(float(cells_per_side) * 0.5))
	_upper_extent_cells = cells_per_side - _lower_extent_cells - 1
	_half_extent_world = float(cells_per_side) * cell_size * 0.5

	_cell_query_shape = BoxShape3D.new()
	_cell_query_shape.size = (
		Vector3.ONE
		* cell_size
		* maxf(collision_probe_scale, 1.0)
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

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.75, 1.0, 0.42)
	material.emission_enabled = true
	material.emission = Color(0.04, 0.22, 0.38, 1.0)
	material.emission_energy_multiplier = 0.55
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var wire_cube := ImmediateMesh.new()
	wire_cube.surface_begin(Mesh.PRIMITIVE_LINES, material)

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


func _schedule_full_volume() -> void:
	_reset_pending_queue()
	_active_occupied.clear()

	var min_cell := _volume_min_cell(_center_cell)
	var max_cell := _volume_max_cell(_center_cell)

	for y in range(min_cell.y, max_cell.y + 1):
		for z in range(min_cell.z, max_cell.z + 1):
			for x in range(min_cell.x, max_cell.x + 1):
				_enqueue_cell(Vector3i(x, y, z))

	_update_multimesh_instances()


func _schedule_for_center_change(
	old_center: Vector3i,
	new_center: Vector3i
) -> void:
	_remove_active_cells_outside_volume()

	# Se la scansione precedente non era ancora finita, ricostruiamo la coda
	# del volume corrente usando comunque la cache delle celle già testate.
	if _has_pending_cells() or old_center == INVALID_CELL:
		_schedule_full_volume()
		return

	var delta := new_center - old_center
	if (
		absi(delta.x) >= cells_per_side
		or absi(delta.y) >= cells_per_side
		or absi(delta.z) >= cells_per_side
	):
		_schedule_full_volume()
		return

	_reset_pending_queue()

	var old_min := _volume_min_cell(old_center)
	var old_max := _volume_max_cell(old_center)
	var new_min := _volume_min_cell(new_center)
	var new_max := _volume_max_cell(new_center)

	if new_min.x < old_min.x:
		_enqueue_x_slab(new_min.x, old_min.x - 1, new_min, new_max)
	elif new_max.x > old_max.x:
		_enqueue_x_slab(old_max.x + 1, new_max.x, new_min, new_max)

	if new_min.y < old_min.y:
		_enqueue_y_slab(new_min.y, old_min.y - 1, new_min, new_max)
	elif new_max.y > old_max.y:
		_enqueue_y_slab(old_max.y + 1, new_max.y, new_min, new_max)

	if new_min.z < old_min.z:
		_enqueue_z_slab(new_min.z, old_min.z - 1, new_min, new_max)
	elif new_max.z > old_max.z:
		_enqueue_z_slab(old_max.z + 1, new_max.z, new_min, new_max)

	_prune_cache_if_needed()
	_update_multimesh_instances()


func _enqueue_x_slab(
	from_x: int,
	to_x: int,
	min_cell: Vector3i,
	max_cell: Vector3i
) -> void:
	if from_x > to_x:
		return

	for x in range(from_x, to_x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			for z in range(min_cell.z, max_cell.z + 1):
				_enqueue_cell(Vector3i(x, y, z))


func _enqueue_y_slab(
	from_y: int,
	to_y: int,
	min_cell: Vector3i,
	max_cell: Vector3i
) -> void:
	if from_y > to_y:
		return

	for y in range(from_y, to_y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			for z in range(min_cell.z, max_cell.z + 1):
				_enqueue_cell(Vector3i(x, y, z))


func _enqueue_z_slab(
	from_z: int,
	to_z: int,
	min_cell: Vector3i,
	max_cell: Vector3i
) -> void:
	if from_z > to_z:
		return

	for z in range(from_z, to_z + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			for y in range(min_cell.y, max_cell.y + 1):
				_enqueue_cell(Vector3i(x, y, z))


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
	if _cell_cache.size() <= maxi(max_cached_cells, cells_per_side):
		return

	var retained: Dictionary = {}
	var padding := 2

	var min_cell := (
		_volume_min_cell(_center_cell)
		- Vector3i.ONE * padding
	)
	var max_cell := (
		_volume_max_cell(_center_cell)
		+ Vector3i.ONE * padding
	)

	for key in _cell_cache.keys():
		var cell: Vector3i = key
		if (
			cell.x >= min_cell.x
			and cell.x <= max_cell.x
			and cell.y >= min_cell.y
			and cell.y <= max_cell.y
			and cell.z >= min_cell.z
			and cell.z <= max_cell.z
		):
			retained[cell] = _cell_cache[cell]

	_cell_cache = retained


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


func _world_bounds() -> Dictionary:
	var min_cell := _volume_min_cell(_center_cell)
	var max_cell := _volume_max_cell(_center_cell)

	return {
		"min": Vector3(
			float(min_cell.x) * cell_size,
			float(min_cell.y) * cell_size,
			float(min_cell.z) * cell_size
		),
		"max": Vector3(
			float(max_cell.x + 1) * cell_size,
			float(max_cell.y + 1) * cell_size,
			float(max_cell.z + 1) * cell_size
		)
	}


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
