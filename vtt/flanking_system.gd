extends Node3D

const UPDATE_INTERVAL := 0.08
const EPSILON := 0.0001

var board_root: Node3D
var tokens_root: Node3D
var _line_root: Node3D
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

	_flanked_ids.clear()
	for token: CharacterBody3D in tokens:
		token.set_meta("flanked", false)

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

				var first_half := _token_half_extents(first)
				var second_half := _token_half_extents(second)
				var target_half := _token_half_extents(target)
				var first_center := first.global_position
				var second_center := second.global_position
				var target_center := target.global_position
				var cell_size := maxf(
					float(board_root.get("cell_size")),
					0.001
				)
				var display_centers := project_centers_to_shared_base(
					first_center,
					first_half,
					second_center,
					second_half,
					target_center,
					target_half,
					cell_size * 0.08,
					cell_size * 0.035
				)
				var segment := flanking_segment(
					display_centers[0],
					first_half,
					display_centers[1],
					second_half,
					display_centers[2],
					target_half
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
	if token.has_method("get_effective_party_id"):
		value = String(token.call("get_effective_party_id"))
	elif token.has_method("get_party_id"):
		value = String(token.call("get_party_id"))
	elif token.has_meta("party_id"):
		value = String(token.get_meta("party_id", ""))
	value = value.strip_edges()
	if value.is_empty():
		value = "Default"
	return value.to_lower()


func _token_reaches_target(
	attacker: CharacterBody3D,
	target: CharacterBody3D
) -> bool:
	var cell_size := maxf(float(board_root.get("cell_size")), 0.001)
	var reach_feet := 5.0
	if attacker.has_method("get_reach_feet"):
		reach_feet = maxf(float(attacker.call("get_reach_feet")), 0.0)

	var attacker_half := _token_half_extents(attacker)
	var target_half := _token_half_extents(target)
	var attacker_base := attacker.global_position.y - attacker_half.y
	var target_base := target.global_position.y - target_half.y

	# On the same tactical plane use square-grid reach: adjacent occupied
	# spaces are 5 ft apart, one empty square between them is 10 ft.
	if absf(attacker_base - target_base) <= cell_size * 0.08:
		return (
			grid_reach_distance_feet(
				attacker.global_position,
				attacker_half,
				target.global_position,
				target_half,
				cell_size
			)
			<= reach_feet + EPSILON
		)

	# Different elevations retain the previous true 3D hitbox distance.
	var reach_world := reach_feet / 5.0 * cell_size
	return (
		aabb_gap_distance_world(
			attacker.global_position,
			attacker_half,
			target.global_position,
			target_half
		)
		< reach_world - EPSILON
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


static func grid_reach_distance_feet(
	first_center: Vector3,
	first_half: Vector3,
	second_center: Vector3,
	second_half: Vector3,
	cell_size: float
) -> float:
	var safe_cell := maxf(cell_size, EPSILON)
	var delta := (second_center - first_center).abs()
	var gap_x := maxf(delta.x - first_half.x - second_half.x, 0.0)
	var gap_z := maxf(delta.z - first_half.z - second_half.z, 0.0)
	var empty_span := maxf(gap_x, gap_z)

	# Adjacent bases have an empty span of zero and are one grid step apart.
	# An exact one-cell empty span means there is one whole square between
	# the creatures, hence two grid steps.
	var empty_cells := int(floor((empty_span + EPSILON) / safe_cell))
	if empty_span > EPSILON and is_equal_approx(
		empty_span,
		float(empty_cells) * safe_cell
	):
		empty_cells = maxi(empty_cells, 1)
	elif empty_span > float(empty_cells) * safe_cell + EPSILON:
		empty_cells += 1
	return float(empty_cells + 1) * 5.0


static func project_centers_to_shared_base(
	first_center: Vector3,
	first_half: Vector3,
	second_center: Vector3,
	second_half: Vector3,
	target_center: Vector3,
	target_half: Vector3,
	tolerance: float,
	lift: float = 0.0
) -> Array[Vector3]:
	var first_base := first_center.y - first_half.y
	var second_base := second_center.y - second_half.y
	var target_base := target_center.y - target_half.y
	var minimum := minf(first_base, minf(second_base, target_base))
	var maximum := maxf(first_base, maxf(second_base, target_base))
	if maximum - minimum > maxf(tolerance, EPSILON):
		return [first_center, second_center, target_center]

	var shared_y := (first_base + second_base + target_base) / 3.0 + lift
	var first := first_center
	var second := second_center
	var target := target_center
	first.y = shared_y
	second.y = shared_y
	target.y = shared_y
	return [first, second, target]


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
	# DMG 2014 square-grid test: use the centers of the flankers' spaces and
	# require that line to cross opposite sides or opposite corners of the
	# target's space. Merely touching/intersecting the target is not enough.
	if not centers_cross_opposite_borders(
		first_center,
		second_center,
		target_center,
		target_half
	):
		return PackedVector3Array()

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

	return PackedVector3Array([start, end])


static func centers_cross_opposite_borders(
	first_center: Vector3,
	second_center: Vector3,
	target_center: Vector3,
	target_half: Vector3
) -> bool:
	var start := Vector2(
		first_center.x - target_center.x,
		first_center.z - target_center.z
	)
	var end := Vector2(
		second_center.x - target_center.x,
		second_center.z - target_center.z
	)
	var delta := end - start
	if delta.length_squared() <= EPSILON * EPSILON:
		return false

	var half := Vector2(
		maxf(target_half.x, EPSILON),
		maxf(target_half.z, EPSILON)
	)
	var t_enter := 0.0
	var t_exit := 1.0

	# Liang-Barsky style clipping against the target's horizontal rectangle.
	for axis: int in range(2):
		var origin := start[axis]
		var step := delta[axis]
		var minimum := -half[axis]
		var maximum := half[axis]

		if absf(step) <= EPSILON:
			if origin < minimum or origin > maximum:
				return false
			continue

		var near_t := (minimum - origin) / step
		var far_t := (maximum - origin) / step
		if near_t > far_t:
			var swap := near_t
			near_t = far_t
			far_t = swap

		t_enter = maxf(t_enter, near_t)
		t_exit = minf(t_exit, far_t)
		if t_enter > t_exit:
			return false

	if t_exit < 0.0 or t_enter > 1.0:
		return false

	var entry := start + delta * clampf(t_enter, 0.0, 1.0)
	var exit := start + delta * clampf(t_exit, 0.0, 1.0)
	var entry_edges := _rectangle_border_flags(entry, half)
	var exit_edges := _rectangle_border_flags(exit, half)
	if entry_edges.is_empty() or exit_edges.is_empty():
		return false

	var entry_corner := entry_edges.size() == 2
	var exit_corner := exit_edges.size() == 2

	# Opposite corners are valid; a side-to-corner crossing is not treated as
	# flanking because the DMG wording requires opposite sides OR corners.
	if entry_corner or exit_corner:
		if not (entry_corner and exit_corner):
			return false
		return (
			("left" in entry_edges and "right" in exit_edges
				or "right" in entry_edges and "left" in exit_edges)
			and
			("top" in entry_edges and "bottom" in exit_edges
				or "bottom" in entry_edges and "top" in exit_edges)
		)

	return (
		("left" in entry_edges and "right" in exit_edges)
		or ("right" in entry_edges and "left" in exit_edges)
		or ("top" in entry_edges and "bottom" in exit_edges)
		or ("bottom" in entry_edges and "top" in exit_edges)
	)


static func _rectangle_border_flags(
	point: Vector2,
	half: Vector2
) -> Array[String]:
	var tolerance := maxf(maxf(half.x, half.y) * 0.001, 0.0005)
	var result: Array[String] = []
	if absf(point.x + half.x) <= tolerance:
		result.append("left")
	if absf(point.x - half.x) <= tolerance:
		result.append("right")
	if absf(point.y + half.y) <= tolerance:
		result.append("top")
	if absf(point.y - half.y) <= tolerance:
		result.append("bottom")
	return result


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
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.albedo_color = Color(1.0, 0.72, 0.12, 1.0)
	_line_material.emission_enabled = true
	_line_material.emission = Color(1.0, 0.34, 0.02, 1.0)
	_line_material.emission_energy_multiplier = 2.5
	_line_material.no_depth_test = true

	_line_root = Node3D.new()
	_line_root.name = "FlankingLines"
	add_child(_line_root)


func _render_lines(points: Array[Vector3]) -> void:
	if _line_root == null:
		return

	for child: Node in _line_root.get_children():
		child.queue_free()

	if points.is_empty():
		return

	var cell_size := maxf(float(board_root.get("cell_size")), 0.001)
	var radius := maxf(cell_size * 0.045, 0.02)
	for index: int in range(0, points.size() - 1, 2):
		_add_visible_segment(points[index], points[index + 1], radius)


func _add_visible_segment(
	start: Vector3,
	end: Vector3,
	radius: float
) -> void:
	var delta := end - start
	var length := delta.length()
	if length <= EPSILON:
		return

	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10
	mesh.rings = 1

	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _line_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var direction := delta / length
	var reference := Vector3.UP
	if absf(direction.dot(reference)) > 0.95:
		reference = Vector3.FORWARD
	var x_axis := reference.cross(direction).normalized()
	var z_axis := x_axis.cross(direction).normalized()
	var basis := Basis(x_axis, direction, z_axis)

	_line_root.add_child(instance)
	instance.global_transform = Transform3D(
		basis,
		(start + end) * 0.5
	)
