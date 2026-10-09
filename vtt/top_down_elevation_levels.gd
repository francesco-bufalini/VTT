extends Node3D

# Queries tactical, solid map surfaces without relying on the grid's
# progressively populated visual cache. Tokens never create floor levels.
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
	for hit_index: int in range(MAX_RAY_HITS):
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
	return _unique_heights(levels)


func get_lower_square_surface(world_point: Vector3, reference_level: float) -> Dictionary:
	var square_x: float = (floorf(world_point.x / cell_size) + 0.5) * cell_size
	var square_z: float = (floorf(world_point.z / cell_size) + 0.5) * cell_size
	var candidates: Array[float] = _surface_heights_at(
		square_x,
		square_z,
		reference_level - maxf(cell_size * 0.04, 0.025)
	)
	if candidates.is_empty():
		return {}
	var top: float = candidates[0]
	return {
		"level": top,
		"world_position": Vector3(square_x, top, square_z)
	}
