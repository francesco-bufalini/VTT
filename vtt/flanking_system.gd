extends Node3D

const UPDATE_INTERVAL := 0.08
const EPSILON := 0.0001

var board_root: Node3D
var tokens_root: Node3D
var _line_instance: MeshInstance3D
var _line_mesh: ImmediateMesh
var _line_material: StandardMaterial3D
var _elapsed := 0.0
var _flanked_ids: Dictionary = {}


func setup(root: Node3D) -> void:
	board_root = root
	tokens_root = root.get_node_or_null("Tokens") as Node3D
	_build_line_renderer()
	set_process(true)
	refresh_now()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < UPDATE_INTERVAL:
		return
	_elapsed = 0.0
	refresh_now()


func refresh_now() -> void:
	if board_root == null or tokens_root == null:
		return

	var tokens: Array[CharacterBody3D] = []
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			node is CharacterBody3D
			and is_instance_valid(node)
			and board_root.is_ancestor_of(node)
			and not node.is_queued_for_deletion()
		):
			tokens.append(node as CharacterBody3D)

	for token: CharacterBody3D in tokens:
		token.set_meta("flanked", false)
	_flanked_ids.clear()

	var line_points: Array[Vector3] = []
	for target: CharacterBody3D in tokens:
		for first_index: int in range(tokens.size()):
			var first: CharacterBody3D = tokens[first_index]
			if first == target:
				continue

			var party_key := _party_key(first)
			if party_key.is_empty() or _party_key(target) == party_key:
				continue
			if not _token_reaches_target(first, target):
				continue

			for second_index: int in range(first_index + 1, tokens.size()):
				var second: CharacterBody3D = tokens[second_index]
				if (
					second == target
					or second == first
					or _party_key(second) != party_key
					or not _token_reaches_target(second, target)
				):
					continue

				var segment := flanking_segment(
					first.global_position,
					_token_half_extents(first),
					second.global_position,
					_token_half_extents(second),
					target.global_position,
					_token_half_extents(target)
				)
				if segment.size() != 2:
					continue

				line_points.append(segment[0])
				line_points.append(segment[1])
				_flanked_ids[target.get_instance_id()] = true
				target.set_meta("flanked", true)

	_render_lines(line_points)


func is_flanked(token: Node) -> bool:
	return (
		token != null
		and is_instance_valid(token)
		and _flanked_ids.has(token.get_instance_id())
	)


func _party_key(token: Node) -> String:
	if token == null or not is_instance_valid(token):
		return ""
	var value := ""
	if token.has_method("get_party_id"):
		value = String(token.call("get_party_id"))
	elif token.has_meta("party_id"):
		value = String(token.get_meta("party_id", ""))
	return value.strip_edges().to_lower()


func _token_reaches_target(
	attacker: CharacterBody3D,
	target: CharacterBody3D
) -> bool:
	var cell_size := maxf(float(board_root.get("cell_size")), 0.001)
	var reach_feet := 5.0
	if attacker.has_method("get_reach_feet"):
		reach_feet = maxf(float(attacker.call("get_reach_feet")), 0.0)
	var reach_world := reach_feet / 5.0 * cell_size
	return (
		aabb_gap_distance_world(
			attacker.global_position,
			_token_half_extents(attacker),
			target.global_position,
			_token_half_extents(target)
		)
		<= reach_world + EPSILON
	)


func _token_half_extents(token: CharacterBody3D) -> Vector3:
	var cell_size := maxf(float(board_root.get("cell_size")), 0.001)
	var footprint_cells := 1.0
	if token.has_method("get_footprint_cells"):
		footprint_cells = maxf(
			float(token.call("get_footprint_cells")),
			0.5
		)
	else:
		var footprint_value: Variant = token.get("_footprint_cells")
		if footprint_value is float or footprint_value is int:
			footprint_cells = maxf(float(footprint_value), 0.5)

	var height_cells := 2.0
	var height_value: Variant = token.get("token_height_cells")
	if height_value is float or height_value is int:
		height_cells = maxf(float(height_value), 0.1)

	return Vector3(
		footprint_cells * cell_size * 0.5,
		height_cells * cell_size * 0.5,
		footprint_cells * cell_size * 0.5
	)


static func aabb_gap_distance_world(
	first_center: Vector3,
	first_half: Vector3,
	second_center: Vector3,
	second_half: Vector3
) -> float:
	var delta := (second_center - first_center).abs()
	var gap := Vector3(
		maxf(delta.x - first_half.x - second_half.x, 0.0),
		maxf(delta.y - first_half.y - second_half.y, 0.0),
		maxf(delta.z - first_half.z - second_half.z, 0.0)
	)
	return gap.length()


static func flanking_segment(
	first_center: Vector3,
	first_half: Vector3,
	second_center: Vector3,
	second_half: Vector3,
	target_center: Vector3,
	target_half: Vector3
) -> PackedVector3Array:
	var delta := second_center - first_center
	if delta.length_squared() <= EPSILON * EPSILON:
		return PackedVector3Array()

	var direction := delta.normalized()
	var first_boundary := _box_boundary_distance(first_half, direction)
	var second_boundary := _box_boundary_distance(second_half, -direction)
	var start := first_center + direction * first_boundary
	var end := second_center - direction * second_boundary
	if start.distance_squared_to(end) <= EPSILON * EPSILON:
		return PackedVector3Array()

	if not segment_intersects_aabb(start, end, target_center, target_half):
		return PackedVector3Array()

	return PackedVector3Array([start, end])


static func segment_intersects_aabb(
	start: Vector3,
	end: Vector3,
	box_center: Vector3,
	box_half: Vector3
) -> bool:
	var local_start := start - box_center
	var direction := end - start
	var t_min := 0.0
	var t_max := 1.0

	for axis: int in range(3):
		var start_axis := local_start[axis]
		var direction_axis := direction[axis]
		var half_axis := box_half[axis]

		if absf(direction_axis) <= EPSILON:
			if start_axis < -half_axis or start_axis > half_axis:
				return false
			continue

		var inverse := 1.0 / direction_axis
		var near_t := (-half_axis - start_axis) * inverse
		var far_t := (half_axis - start_axis) * inverse
		if near_t > far_t:
			var swap := near_t
			near_t = far_t
			far_t = swap

		t_min = maxf(t_min, near_t)
		t_max = minf(t_max, far_t)
		if t_min > t_max:
			return false

	return true


static func _box_boundary_distance(
	half_extents: Vector3,
	direction: Vector3
) -> float:
	var distance := INF
	for axis: int in range(3):
		var component := absf(direction[axis])
		if component <= EPSILON:
			continue
		distance = minf(
			distance,
			maxf(half_extents[axis], 0.0) / component
		)
	return 0.0 if distance == INF else distance


func _build_line_renderer() -> void:
	_line_mesh = ImmediateMesh.new()
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.albedo_color = Color(1.0, 0.74, 0.18, 1.0)
	_line_material.emission_enabled = true
	_line_material.emission = Color(1.0, 0.42, 0.08, 1.0)
	_line_material.no_depth_test = true

	_line_instance = MeshInstance3D.new()
	_line_instance.name = "FlankingLines"
	_line_instance.mesh = _line_mesh
	_line_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line_instance)


func _render_lines(points: Array[Vector3]) -> void:
	if _line_mesh == null:
		return
	_line_mesh.clear_surfaces()
	if points.is_empty():
		return

	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_material)
	for point: Vector3 in points:
		_line_mesh.surface_add_vertex(to_local(point))
	_line_mesh.surface_end()
