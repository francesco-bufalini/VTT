extends Node3D

# Queries tactical, solid map surfaces without relying on the grid's
# progressively populated visual cache. Tokens supply additional navigable levels.
const MAP_MASK := 1 | 4
const MAX_RAY_HITS := 32
const MAX_RAY_HEIGHT := 1500.0
const MIN_RAY_HEIGHT := -1500.0

var board_root: Node3D
var cell_size: float = 1.0


func setup(board: Node3D) -> void:
	board_root = board
	cell_size = maxf(float(board.get("cell_size")), 0.001)


func _is_map_surface(collider: Variant) -> bool:
	if not collider is PhysicsBody3D:
		return false
	if collider is CharacterBody3D:
		return false
	var node: Node = collider as Node
	while node != null:
		if (
			node.is_in_group("dnd_token")
			or node.is_in_group("grid_3d_excluded")
			or node.is_in_group("grid_2d_excluded")
		):
			return false
		node = node.get_parent()
	return true


func _surface_heights_at(x: float, z: float, starting_y: float) -> Array[float]:
	var heights: Array[float] = []
	var origin_y: float = starting_y
	var step: float = maxf(cell_size * 0.04, 0.025)
	for _hit_index: int in range(MAX_RAY_HITS):
		if origin_y <= MIN_RAY_HEIGHT:
			break
		var query: PhysicsRayQueryParameters3D = (
			PhysicsRayQueryParameters3D.create(
				Vector3(x, origin_y, z),
				Vector3(x, MIN_RAY_HEIGHT, z),
				MAP_MASK
			)
		)
		query.collide_with_areas = false
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var position: Vector3 = hit.get("position", Vector3.ZERO)
		var normal: Vector3 = hit.get("normal", Vector3.UP)
		if _is_map_surface(hit.get("collider")) and normal.dot(Vector3.UP) > 0.35:
			heights.append(position.y)
		origin_y = position.y - step
	return heights


# The support of a creature is the FREE grid cell immediately below its
# occupied footprint, not the lowest cell occupied by its body. Using an
# epsilon below the bottom face also handles exact integer boundaries.
static func token_support_air_level(token: Node3D, tactical_cell_size: float) -> float:
	var safe: float = maxf(tactical_cell_size, 0.001)
	var height_value: Variant = token.get("token_height_cells")
	var size_value: Variant = token.get("cell_size")
	var height_cells: float = maxf(
		float(height_value) if height_value is float or height_value is int else 1.0,
		0.1
	)
	var token_cell: float = maxf(
		float(size_value) if size_value is float or size_value is int else safe,
		0.001
	)
	var bottom_y: float = (
		token.global_position.y - height_cells * token_cell * 0.5
	)
	return (floorf((bottom_y - safe * 0.001) / safe) + 0.5) * safe


func _token_has_solid_support(token: CharacterBody3D) -> bool:
	# A token standing on a real floor uses that floor's navigable level.
	# Otherwise its adjacent air cell would insert an unwanted extra stop
	# beneath the floor every time Space / Shift+Space is pressed.
	var token_cell: float = maxf(float(token.get("cell_size")), 0.001)
	var height_cells: float = maxf(float(token.get("token_height_cells")), 0.1)
	var bottom_y: float = token.global_position.y - height_cells * token_cell * 0.5
	var tolerance: float = cell_size * 0.13
	var top: Vector3 = Vector3(
		token.global_position.x, bottom_y + tolerance,
		token.global_position.z
	)
	var bottom: Vector3 = top - Vector3.UP * tolerance * 2.0
	var query: PhysicsRayQueryParameters3D = (
		PhysicsRayQueryParameters3D.create(top, bottom, MAP_MASK)
	)
	query.collide_with_areas = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return (
		not hit.is_empty()
		and _is_map_surface(hit.get("collider"))
		and Vector3(hit.get("normal", Vector3.ZERO)).dot(Vector3.UP) > 0.35
		and absf(float(Vector3(hit.get("position", Vector3.ZERO)).y) - bottom_y) <= tolerance
	)


func _unique_heights(values: Array[float]) -> Array[float]:
	values.sort()
	var unique: Array[float] = []
	for height: float in values:
		if unique.is_empty() or height - unique[-1] > cell_size * 0.22:
			unique.append(height)
	return unique


func get_solid_levels() -> Array[float]:
	if board_root == null or not is_instance_valid(board_root):
		return []
	var camera: Camera3D = board_root.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return []
	var levels: Array[float] = []
	var center: Vector3 = camera.global_position
	if camera.has_method("get_top_down_level"):
		var screen_center: Vector2 = camera.get_viewport().get_visible_rect().size * 0.5
		var ray_origin: Vector3 = camera.project_ray_origin(screen_center)
		var ray_direction: Vector3 = camera.project_ray_normal(screen_center)
		if absf(ray_direction.y) > 0.00001:
			var floor_y: float = float(camera.call("get_top_down_level"))
			var distance: float = (floor_y - ray_origin.y) / ray_direction.y
			if distance > 0.0:
				center = ray_origin + ray_direction * distance
	# Sample nearby squares as well as the center: ships and other multilevel
	# maps can have a gap or stairwell precisely beneath the camera.
	for x_offset: float in [-2.0, 0.0, 2.0]:
		for z_offset: float in [-2.0, 0.0, 2.0]:
			levels.append_array(
				_surface_heights_at(
					center.x + x_offset * cell_size,
					center.z + z_offset * cell_size,
					MAX_RAY_HEIGHT
				)
			)
	# A floating token contributes the AIR square supporting its feet;
	# grounded tokens are already represented by the solid floor collision.
	var tokens_root: Node3D = board_root.get_node_or_null("Tokens") as Node3D
	if tokens_root != null:
		for node: Node in tokens_root.get_children():
			if (
				not node is CharacterBody3D
				or not node.is_in_group("dnd_token")
				or node.is_queued_for_deletion()
			):
				continue
			var token: CharacterBody3D = node as CharacterBody3D
			if not _token_has_solid_support(token):
				levels.append(token_support_air_level(token, cell_size))
	return _unique_heights(levels)


func get_visible_square_surface(
	world_point: Vector3,
	reference_level: float
) -> Dictionary:
	var square_x: float = (floorf(world_point.x / cell_size) + 0.5) * cell_size
	var square_z: float = (floorf(world_point.z / cell_size) + 0.5) * cell_size
	# Include the surface at the selected camera level. The old probe
	# started *below* it, so hovering over an exposed upper deck still
	# reported the deck underneath after changing camera floors.
	#
	# Physics/voxel faces may be offset by up to half a tactical cell
	# from the selected camera level. Sample them before looking below;
	# otherwise the probe can skip the visible floor and report -1 square.
	# Do not admit the next full floor (+1 cell) into this camera slice.
	var epsilon: float = maxf(cell_size * 0.55, 0.025)
	var candidates: Array[float] = _surface_heights_at(
		square_x,
		square_z,
		reference_level + epsilon
	)
	if candidates.is_empty():
		return {}
	var top: float = candidates[0]
	return {
		"level": top,
		"world_position": Vector3(square_x, top, square_z)
	}


# Compatibility for external callers of the original square probe.
func get_lower_square_surface(
	world_point: Vector3,
	reference_level: float
) -> Dictionary:
	return get_visible_square_surface(world_point, reference_level)
