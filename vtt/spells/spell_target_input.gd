extends RefCounted

# UI-to-world projection only. No spell eligibility, phases, or cast effects
# belong here. Remote/mobile already supply resolved world points and token
# references, so they bypass these desktop projection functions entirely.

static func token_from_screen(
	board: Node3D,
	screen_position: Vector2,
	top_down: bool,
	collision_mask: int
) -> Node3D:
	if board == null or not is_instance_valid(board):
		return null
	var value: Variant
	if top_down and board.has_method("_raycast_token_from_screen"):
		value = board.call("_raycast_token_from_screen", screen_position, true)
	else:
		if not board.has_method("_raycast_from_screen"):
			return null
		value = board.call(
			"_raycast_from_screen", screen_position, collision_mask, true
		)
	if not value is Dictionary:
		return null
	var collider: Node = (value as Dictionary).get("collider") as Node
	if collider == null or not board.has_method("_find_interaction_target"):
		return null
	var candidate: Variant = board.call("_find_interaction_target", collider)
	if not candidate is Node3D:
		return null
	var token: Node3D = candidate as Node3D
	return token if token.is_in_group("dnd_token") else null


static func point_from_screen(
	board: Node3D,
	measurement: Node,
	screen_position: Vector2,
	top_down: bool,
	preferred_air_distance_world: float = -1.0,
	force_grid_target: bool = false
) -> Dictionary:
	if top_down:
		return top_down_point(board, screen_position)
	if measurement == null or not is_instance_valid(measurement):
		return {"valid": false}
	var projected: Variant = measurement.call(
		"get_spell_target_point", screen_position,
		preferred_air_distance_world, force_grid_target
	)
	return projected if projected is Dictionary else {"valid": false}


static func top_down_point(board: Node3D, screen_position: Vector2) -> Dictionary:
	# Top-down ray intersects the selected floor directly; geometry colliders
	# must not block cell targeting. The 3D adapter retains physics depth.
	if board == null or not is_instance_valid(board):
		return {"valid": false}
	var camera: Camera3D = board.get_node_or_null("Camera3D") as Camera3D
	if camera == null or not camera.has_method("get_top_down_level"):
		return {"valid": false}
	var plane_y: float = float(camera.call("get_top_down_level"))
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.00001:
		return {"valid": false}
	var depth: float = (plane_y - origin.y) / direction.y
	if depth < 0.0:
		return {"valid": false}
	return {
		"valid": true, "point": origin + direction * depth,
		"in_air": false, "normal": Vector3.UP
	}
