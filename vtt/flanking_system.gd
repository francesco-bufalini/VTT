extends Node3D

const UPDATE_INTERVAL := 0.08
const EPSILON := 0.0001

var board_root: Node3D
var tokens_root: Node3D
var ui_root: Node
var camera: Camera3D
var _flanking_badges: Dictionary = {}
var _condition_visuals_visible: bool = true
var _line_root: Node3D
var _arrow_mesh: ImmediateMesh
var _arrow_instance: MeshInstance3D
var _line_material: StandardMaterial3D
var _line_outline_material: StandardMaterial3D
var _mutual_material: StandardMaterial3D
var _mutual_outline_material: StandardMaterial3D
var _elapsed := 0.0
var _flanked_ids: Dictionary = {}
var _screen_reach_arrows: Array[Vector3] = []
var _screen_mutual_markers: Array[Vector3] = []
var _screen_reach_links: Array[Dictionary] = []


func setup(root: Node3D) -> void:
	board_root = root
	tokens_root = root.get_node_or_null("Tokens") as Node3D
	ui_root = root.get_node_or_null("UI")
	camera = root.get_node_or_null("Camera3D") as Camera3D
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
	var visible_badge_targets: Dictionary = {}
	# The hitbox and faction for each token are invariant for this refresh.
	# Gather hostile attackers within melee reach once per target; test pairs
	# only if at least two can actually reach it.
	var half_extents: Dictionary = {}
	var parties: Dictionary = {}
	for token: CharacterBody3D in tokens:
		token.set_meta("flanked", false)
		half_extents[token.get_instance_id()] = _token_half_extents(token)
		parties[token.get_instance_id()] = _party_key(token)

	var arrow_points: Array[Vector3] = []
	var mutual_marker_points: Array[Vector3] = []
	for target: CharacterBody3D in tokens:
		var target_id := target.get_instance_id()
		var eligible: Array[CharacterBody3D] = []
		for attacker: CharacterBody3D in tokens:
			if attacker == target:
				continue
			if not party_keys_are_enemies(
				String(parties[attacker.get_instance_id()]),
				String(parties[target_id])
			):
				continue
			if _token_reaches_target(attacker, target):
				eligible.append(attacker)
		if eligible.size() < 2:
			continue

		var target_half: Vector3 = half_extents[target_id]
		var found := false
		for i: int in range(eligible.size() - 1):
			var first: CharacterBody3D = eligible[i]
			var first_half: Vector3 = half_extents[first.get_instance_id()]
			for j: int in range(i + 1, eligible.size()):
				var second: CharacterBody3D = eligible[j]
				var second_half: Vector3 = half_extents[second.get_instance_id()]
				if flanking_segment(
					first.global_position, first_half,
					second.global_position, second_half,
					target.global_position, target_half
				).size() == 2:
					found = true
					break
			if found:
				break
		if found:
			_flanked_ids[target_id] = true
			target.set_meta("flanked", true)

	# Reach arrows are a tactical hostility layer: every token points only
	# toward enemy-party tokens currently inside its own reach. Selection and
	# flanking state do not affect this visualization.
	var reach_visuals := _build_reach_visuals(tokens)
	var arrow_value: Variant = reach_visuals.get("arrows", [])
	if arrow_value is Array:
		for point: Variant in arrow_value as Array:
			if point is Vector3:
				arrow_points.append(point)
	var mutual_value: Variant = reach_visuals.get("mutual_markers", [])
	if mutual_value is Array:
		for point: Variant in mutual_value as Array:
			if point is Vector3:
				mutual_marker_points.append(point)

	# Affiancato is always shown. Condition text participates only when the
	# View toggle for condition visuals is enabled.
	for token: CharacterBody3D in tokens:
		var condition_parts := PackedStringArray()
		if _condition_visuals_visible:
			condition_parts = _token_condition_display_parts(token)
		var badge_text := compose_status_badge_text(
			bool(token.get_meta("flanked", false)),
			condition_parts
		)
		if badge_text.is_empty():
			continue
		visible_badge_targets[token.get_instance_id()] = {
			"token": token,
			"text": badge_text,
		}

	_screen_reach_arrows = arrow_points
	_screen_mutual_markers = mutual_marker_points
	_screen_reach_links = reach_visuals.get("links", [])
	_render_arrows(arrow_points, mutual_marker_points)
	_refresh_flanking_badges(visible_badge_targets)


func get_screen_reach_visuals() -> Dictionary:
	return {
		"arrows": _screen_reach_arrows,
		"mutual_markers": _screen_mutual_markers,
		"links": _screen_reach_links
	}


func _build_reach_visuals(
	tokens: Array[CharacterBody3D]
) -> Dictionary:
	var arrows: Array[Vector3] = []
	var mutual_markers: Array[Vector3] = []
	var links: Array[Dictionary] = []
	var safe_cell := maxf(float(board_root.get("cell_size")), 0.001)

	# Work on unordered pairs so reciprocal adjacent reach can be represented
	# once instead of drawing two arrows on top of each other.
	for first_index: int in range(tokens.size()):
		var first := tokens[first_index]
		if first == null or not is_instance_valid(first):
			continue
		var first_half := _token_half_extents(first)

		for second_index: int in range(first_index + 1, tokens.size()):
			var second := tokens[second_index]
			if second == null or not is_instance_valid(second):
				continue
			if not party_keys_are_enemies(
				_party_key(first),
				_party_key(second)
			):
				continue

			var second_half := _token_half_extents(second)
			var first_reaches := _token_reaches_target(first, second)
			var second_reaches := _token_reaches_target(second, first)
			if not first_reaches and not second_reaches:
				continue
			# The 2D painter uses actual portrait bounds, not 3D mesh segments.
			# Combine reciprocal links at any reach into one legible marker.
			links.append({
				"from": first if first_reaches else second,
				"to": second if first_reaches else first,
				"mutual": first_reaches and second_reaches
			})

			var first_base := first.global_position
			var second_base := second.global_position
			first_base.y -= first_half.y
			second_base.y -= second_half.y

			if bases_share_tactical_plane(
				first_base.y,
				second_base.y,
				safe_cell
			):
				var shared_y := (first_base.y + second_base.y) * 0.5
				first_base.y = shared_y
				second_base.y = shared_y

			var tactical_distance := tactical_reach_distance_feet(
				first.global_position,
				first_half,
				second.global_position,
				second_half,
				safe_cell
			)
			if should_use_mutual_adjacent_marker(
				first_reaches,
				second_reaches,
				tactical_distance
			):
				var marker := mutual_reach_marker_segment(
					first_base,
					first_half,
					second_base,
					second_half,
					safe_cell
				)
				if marker.size() == 2:
					mutual_markers.append(marker[0])
					mutual_markers.append(marker[1])
				continue

			if first_reaches:
				var first_arrow := reach_arrow_segment(
					first_base,
					first_half,
					second_base,
					second_half,
					safe_cell
				)
				if first_arrow.size() == 2:
					arrows.append(first_arrow[0])
					arrows.append(first_arrow[1])

			if second_reaches:
				var second_arrow := reach_arrow_segment(
					second_base,
					second_half,
					first_base,
					first_half,
					safe_cell
				)
				if second_arrow.size() == 2:
					arrows.append(second_arrow[0])
					arrows.append(second_arrow[1])

	return {
		"arrows": arrows,
		"mutual_markers": mutual_markers,
		"links": links
	}


func set_condition_visuals_visible(value: bool) -> void:
	_condition_visuals_visible = value
	refresh_now()


func are_condition_visuals_visible() -> bool:
	return _condition_visuals_visible


func _refresh_flanking_badges(targets: Dictionary) -> void:
	# A creature sheet must never have condition text drawn on top of it,
	# even while the 3D camera is active. The badges are recreated as soon
	# as the sheet closes (the tactical system refreshes continuously).
	var creature_area: Node = (
		board_root.get_node_or_null("CreatureArea")
		if board_root != null else null
	)
	if (
		creature_area != null
		and creature_area.has_method("is_panel_open")
		and bool(creature_area.call("is_panel_open"))
	):
		_clear_flanking_badges()
		return
	# The 2D elevation overlay owns its compact status strip; avoid projecting
	# the 3D badge a second time, which also drifts across sliced floors.
	if (
		board_root != null and board_root.has_method("is_2d_view_enabled")
		and bool(board_root.call("is_2d_view_enabled"))
	):
		_clear_flanking_badges()
		return
	if ui_root == null or camera == null or not is_instance_valid(camera):
		_clear_flanking_badges()
		return

	var stale: Array[int] = []
	for key: Variant in _flanking_badges.keys():
		var token_id := int(key)
		if not targets.has(token_id):
			stale.append(token_id)
	for token_id: int in stale:
		var stale_panel: Variant = _flanking_badges.get(token_id)
		if stale_panel is Control and is_instance_valid(stale_panel):
			(stale_panel as Control).queue_free()
		_flanking_badges.erase(token_id)

	for key: Variant in targets.keys():
		var token_id := int(key)
		var item_value: Variant = targets[key]
		if not item_value is Dictionary:
			continue
		var item := item_value as Dictionary
		var target_value: Variant = item.get("token")
		if not target_value is CharacterBody3D:
			continue
		var target := target_value as CharacterBody3D
		if not is_instance_valid(target):
			continue

		var panel := _flanking_badges.get(token_id) as PanelContainer
		if panel == null or not is_instance_valid(panel):
			panel = _create_flanking_badge()
			_flanking_badges[token_id] = panel

		var label := panel.get_node_or_null("Label") as Label
		if label != null:
			label.text = String(item.get("text", ""))
		panel.reset_size()
		panel.size = panel.get_combined_minimum_size()

		var world_anchor := target.global_position
		var height_cells_value: Variant = target.get("token_height_cells")
		var height_cells := (
			float(height_cells_value)
			if height_cells_value is float or height_cells_value is int
			else 2.0
		)
		var safe_cell := maxf(float(board_root.get("cell_size")), 0.001)
		# The token name sits at top + 0.38 cells. Anchor this compact badge
		# immediately below it while keeping the whole panel above the model.
		world_anchor.y += height_cells * safe_cell * 0.5 + safe_cell * 0.04

		if camera.is_position_behind(world_anchor):
			panel.hide()
			continue

		var screen := camera.unproject_position(world_anchor)
		var camera_right := camera.global_transform.basis.x.normalized()
		var right_screen := camera.unproject_position(
			world_anchor + camera_right * safe_cell
		)
		var projected_cell_pixels := screen.distance_to(right_screen)
		var badge_scale := perspective_badge_scale(
			projected_cell_pixels,
			panel.size.y
		)
		panel.scale = Vector2.ONE * badge_scale
		var scaled_size := panel.size * badge_scale
		panel.position = Vector2(
			screen.x - scaled_size.x * 0.5,
			screen.y - scaled_size.y
		)
		panel.show()


func _create_flanking_badge() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "FlankingNotice"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Below the creature-sheet interface (z=30).
	panel.z_index = 10

	# Deliberately identical to the opportunity-attack popup style.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.04, 0.05, 0.86)
	style.border_color = Color(0.72, 0.48, 0.20, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.name = "Label"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	panel.add_child(label)

	ui_root.add_child(panel)
	panel.reset_size()
	return panel


func _token_condition_display_parts(
	token: CharacterBody3D
) -> PackedStringArray:
	if (
		token != null
		and is_instance_valid(token)
		and token.has_method("get_active_condition_display_parts")
	):
		var value: Variant = token.call("get_active_condition_display_parts")
		if value is PackedStringArray:
			return value as PackedStringArray
		if value is Array:
			var converted := PackedStringArray()
			for item: Variant in value as Array:
				converted.append(String(item))
			return converted
	return PackedStringArray()


static func compose_status_badge_text(
	flanked: bool,
	condition_parts: PackedStringArray
) -> String:
	var parts := PackedStringArray()
	if flanked:
		parts.append("⚔ Affiancato")
	for part: String in condition_parts:
		var clean := part.strip_edges()
		if not clean.is_empty():
			parts.append(clean)
	return ", ".join(parts)


static func perspective_badge_scale(
	projected_cell_pixels: float,
	natural_height_pixels: float
) -> float:
	if projected_cell_pixels <= EPSILON or natural_height_pixels <= EPSILON:
		return 1.0
	# Keep the badge compact beneath the token name while preserving world
	# perspective: about a quarter of a grid cell tall at every depth.
	return clampf(
		projected_cell_pixels * 0.24 / natural_height_pixels,
		0.05,
		1.8
	)


func _clear_flanking_badges() -> void:
	for value: Variant in _flanking_badges.values():
		if value is Control and is_instance_valid(value):
			(value as Control).queue_free()
	_flanking_badges.clear()


func is_flanked(token: Node) -> bool:
	return (
		token != null
		and is_instance_valid(token)
		and _flanked_ids.has(token.get_instance_id())
	)


static func normalized_party_key(value: String) -> String:
	var clean := value.strip_edges().to_lower()
	return clean if not clean.is_empty() else "default"


static func party_keys_are_enemies(
	first_party: String,
	second_party: String
) -> bool:
	return (
		normalized_party_key(first_party)
		!= normalized_party_key(second_party)
	)


static func flankers_are_hostile_to_target(
	first_flanker_party: String,
	second_flanker_party: String,
	target_party: String
) -> bool:
	# The flankers do not need to be allies with each other. Each one only
	# needs to be hostile to the creature being flanked.
	return (
		party_keys_are_enemies(first_flanker_party, target_party)
		and party_keys_are_enemies(second_flanker_party, target_party)
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
	return normalized_party_key(value)


func _token_reaches_target(
	attacker: CharacterBody3D,
	target: CharacterBody3D
) -> bool:
	var cell_size := maxf(float(board_root.get("cell_size")), 0.001)
	var reach_feet := 5.0
	if attacker.has_method("get_reach_feet"):
		reach_feet = maxf(float(attacker.call("get_reach_feet")), 0.0)
	return (
		tactical_reach_distance_feet(
			attacker.global_position,
			_token_half_extents(attacker),
			target.global_position,
			_token_half_extents(target),
			cell_size
		)
		<= reach_feet + EPSILON
	)


func _token_half_extents(token: CharacterBody3D) -> Vector3:
	return token_half_extents_world(
		token,
		maxf(float(board_root.get("cell_size")), 0.001)
	)


static func token_half_extents_world(
	token: Node,
	cell_size: float
) -> Vector3:
	var safe_cell := maxf(cell_size, 0.001)
	var footprint_cells := 1.0
	if token != null and token.has_method("get_footprint_cells"):
		footprint_cells = maxf(
			float(token.call("get_footprint_cells")),
			1.0 # Tiny still occupies one tactical square.
		)
	elif token != null:
		var footprint_value: Variant = token.get("_footprint_cells")
		if footprint_value is float or footprint_value is int:
			footprint_cells = maxf(float(footprint_value), 1.0)

	var height_cells := 2.0
	if token != null:
		var height_value: Variant = token.get("token_height_cells")
		if height_value is float or height_value is int:
			height_cells = maxf(float(height_value), 0.1)

	return Vector3(
		footprint_cells * safe_cell * 0.5,
		height_cells * safe_cell * 0.5,
		footprint_cells * safe_cell * 0.5
	)


static func tactical_reach_distance_feet(
	first_center: Vector3,
	first_half: Vector3,
	second_center: Vector3,
	second_half: Vector3,
	cell_size: float
) -> float:
	var safe_cell := maxf(cell_size, 0.001)
	var first_base := first_center.y - first_half.y
	var second_base := second_center.y - second_half.y
	if bases_share_tactical_plane(first_base, second_base, safe_cell):
		return grid_reach_distance_feet(
			first_center,
			first_half,
			second_center,
			second_half,
			safe_cell
		)
	# Never switch to continuous hitbox-edge distance just because the
	# spawn heights differ. That used to turn a one-square gap (10 ft on
	# the tactical grid) into a 5 ft edge gap until a token was moved.
	# In 3D, count the intervening grid cells on all three axes using
	# the same diagonal/Chebyshev convention as the flat tactical grid.
	var delta: Vector3 = (second_center - first_center).abs()
	var gap_x: float = maxf(delta.x - first_half.x - second_half.x, 0.0)
	var gap_y: float = maxf(delta.y - first_half.y - second_half.y, 0.0)
	var gap_z: float = maxf(delta.z - first_half.z - second_half.z, 0.0)
	return _tactical_gap_feet(maxf(gap_x, maxf(gap_y, gap_z)), safe_cell)


static func bases_share_tactical_plane(
	first_base_y: float,
	second_base_y: float,
	cell_size: float
) -> bool:
	var safe_cell := maxf(cell_size, 0.001)
	# Tokens resting on the same rendered surface can differ slightly in Y
	# because of legacy height data, landing offsets or imported model bounds.
	# Treat sub-half-cell differences as the same tactical grid plane. A full
	# grid level remains distinct.
	return absf(first_base_y - second_base_y) < safe_cell * 0.5


static func _tactical_gap_feet(empty_span: float, cell_size: float) -> float:
	var safe_cell := maxf(cell_size, EPSILON)
	# The first occupied square always counts as the first 5 ft. Every
	# complete or partial intervening square adds another tactical step.
	# Bias integer boundaries only to suppress floating-point jitter.
	var empty_cells: int = maxi(0, ceili(
		(empty_span - EPSILON * safe_cell) / safe_cell
	))
	return float(empty_cells + 1) * 5.0


static func grid_reach_distance_feet(
	first_center: Vector3,
	first_half: Vector3,
	second_center: Vector3,
	second_half: Vector3,
	cell_size: float
) -> float:
	var delta: Vector3 = (second_center - first_center).abs()
	var gap_x: float = maxf(delta.x - first_half.x - second_half.x, 0.0)
	var gap_z: float = maxf(delta.z - first_half.z - second_half.z, 0.0)
	return _tactical_gap_feet(maxf(gap_x, gap_z), cell_size)


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
	# A real 3D test: ANY two points in the flankers' occupied boxes may
	# connect across two opposing faces of the target's occupied box.
	# Test each of the three face axes in both directions. Within each
	# candidate axial slice, the transverse coordinates are solved by
	# clipping a small convex polygon (not by sampling mesh vertices).
	for axis: int in range(3):
		var result := _flanking_on_axis(
			first_center, first_half, second_center, second_half,
			target_center, target_half, axis
		)
		if result.size() == 2:
			return result
		result = _flanking_on_axis(
			second_center, second_half, first_center, first_half,
			target_center, target_half, axis
		)
		if result.size() == 2:
			return PackedVector3Array([result[1], result[0]])
	return PackedVector3Array()


static func _flanking_on_axis(
	first_center: Vector3,
	first_half: Vector3,
	second_center: Vector3,
	second_half: Vector3,
	target_center: Vector3,
	target_half: Vector3,
	axis: int
) -> PackedVector3Array:
	var low := target_center[axis] - target_half[axis]
	var high := target_center[axis] + target_half[axis]
	var first_low := first_center[axis] - first_half[axis]
	var first_high := first_center[axis] + first_half[axis]
	var second_low := second_center[axis] - second_half[axis]
	var second_high := second_center[axis] + second_half[axis]
	# Require a genuine crossing, not a segment that merely touches a face.
	var margin := maxf(0.000001, minf(target_half.x, minf(
		target_half.y, target_half.z
	)) * 0.0001)
	if first_low >= low - margin or second_high <= high + margin:
		return PackedVector3Array()

	var left_limit := minf(first_high, low - margin)
	var right_limit := maxf(second_low, high + margin)
	if left_limit < first_low or right_limit > second_high:
		return PackedVector3Array()

	# Prefer central slices. Additional slices handle partial axial overlaps
	# and asymmetrically sized/offset miniature volumes. Only a constant
	# number of 2D polygon clips is needed; no voxel or ray enumeration.
	var fractions := PackedFloat32Array([0.5, 0.0, 1.0, 0.25, 0.75])
	for left_fraction: float in fractions:
		var a := lerpf(first_low, left_limit, left_fraction)
		for right_fraction: float in fractions:
			var b := lerpf(right_limit, second_high, right_fraction)
			var near_fraction := (low - a) / (b - a)
			var far_fraction := (high - a) / (b - a)
			var start := first_center
			var end := second_center
			start[axis] = a
			end[axis] = b
			var valid := true
			for transverse_axis: int in range(3):
				if transverse_axis == axis:
					continue
				var a_min := first_center[transverse_axis] - first_half[transverse_axis]
				var a_max := first_center[transverse_axis] + first_half[transverse_axis]
				var b_min := second_center[transverse_axis] - second_half[transverse_axis]
				var b_max := second_center[transverse_axis] + second_half[transverse_axis]
				var target_min := target_center[transverse_axis] - target_half[transverse_axis] + margin
				var target_max := target_center[transverse_axis] + target_half[transverse_axis] - margin
				var polygon := PackedVector2Array([
					Vector2(a_min, b_min), Vector2(a_max, b_min),
					Vector2(a_max, b_max), Vector2(a_min, b_max)
				])
				for fraction: float in [near_fraction, far_fraction]:
					polygon = _clip_flanking_pair(polygon, fraction, target_min, true)
					if polygon.is_empty():
						break
					polygon = _clip_flanking_pair(polygon, fraction, target_max, false)
					if polygon.is_empty():
						break
				if polygon.is_empty():
					valid = false
					break
				# The polygon contains exactly the (first, second) coordinates
				# whose straight line stays inside both transverse face bounds.
				var witness := Vector2.ZERO
				for point: Vector2 in polygon:
					witness += point
				witness /= float(polygon.size())
				start[transverse_axis] = witness.x
				end[transverse_axis] = witness.y
			if valid:
				return PackedVector3Array([start, end])
	return PackedVector3Array()


static func _clip_flanking_pair(
	polygon: PackedVector2Array,
	fraction: float,
	bound: float,
	keep_above: bool
) -> PackedVector2Array:
	if polygon.is_empty():
		return polygon
	var clipped := PackedVector2Array()
	var previous: Vector2 = polygon[polygon.size() - 1]
	var previous_delta := lerpf(previous.x, previous.y, fraction) - bound
	var previous_inside := previous_delta >= 0.0 if keep_above else previous_delta <= 0.0
	for current: Vector2 in polygon:
		var current_delta := lerpf(current.x, current.y, fraction) - bound
		var current_inside := current_delta >= 0.0 if keep_above else current_delta <= 0.0
		if previous_inside != current_inside:
			var crossing := previous_delta / (previous_delta - current_delta)
			clipped.append(previous.lerp(current, clampf(crossing, 0.0, 1.0)))
		if current_inside:
			clipped.append(current)
		previous = current
		previous_delta = current_delta
		previous_inside = current_inside
	return clipped


static func centers_form_flanking_pair(
	first_center: Vector3,
	second_center: Vector3,
	target_center: Vector3,
	target_half: Vector3
) -> bool:
	# Compatibility alias for callers/tests. The actual rule is the strict
	# opposite-side/opposite-corner test below.
	return centers_cross_opposite_borders(
		first_center,
		second_center,
		target_center,
		target_half
	)


static func segment_intersects_horizontal_rect(
	start: Vector3,
	end: Vector3,
	box_center: Vector3,
	box_half: Vector3
) -> bool:
	var start_2d := Vector2(start.x - box_center.x, start.z - box_center.z)
	var end_2d := Vector2(end.x - box_center.x, end.z - box_center.z)
	var delta := end_2d - start_2d
	var half := Vector2(
		maxf(box_half.x, EPSILON),
		maxf(box_half.z, EPSILON)
	)
	var t_min := 0.0
	var t_max := 1.0
	for axis: int in range(2):
		var origin := start_2d[axis]
		var step := delta[axis]
		if absf(step) <= EPSILON:
			if origin < -half[axis] or origin > half[axis]:
				return false
			continue
		var near_t := (-half[axis] - origin) / step
		var far_t := (half[axis] - origin) / step
		if near_t > far_t:
			var swap := near_t
			near_t = far_t
			far_t = swap
		t_min = maxf(t_min, near_t)
		t_max = minf(t_max, far_t)
		if t_min > t_max:
			return false
	return t_max >= 0.0 and t_min <= 1.0


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
	_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Cool teal keeps reach information visually distinct from the warm amber
	# used by status/UI notifications and remains legible over stone or grid.
	_line_material.albedo_color = Color(0.20, 0.82, 0.78, 0.84)
	_line_material.emission_enabled = true
	_line_material.emission = Color(0.04, 0.34, 0.40, 1.0)
	_line_material.emission_energy_multiplier = 0.45
	_line_material.no_depth_test = true
	_line_material.render_priority = 2

	_line_outline_material = StandardMaterial3D.new()
	_line_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_outline_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_line_outline_material.albedo_color = Color(0.012, 0.065, 0.085, 0.90)
	_line_outline_material.emission_enabled = true
	_line_outline_material.emission = Color(0.015, 0.12, 0.15, 1.0)
	_line_outline_material.emission_energy_multiplier = 0.08
	_line_outline_material.no_depth_test = true
	_line_outline_material.render_priority = 1

	# Reciprocal adjacent reach uses a quieter mint marker instead of two
	# overlapping arrows. It reads as a single bidirectional relationship.
	_mutual_material = StandardMaterial3D.new()
	_mutual_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mutual_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mutual_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mutual_material.albedo_color = Color(0.40, 0.92, 0.72, 0.94)
	_mutual_material.emission_enabled = true
	_mutual_material.emission = Color(0.06, 0.28, 0.24, 1.0)
	_mutual_material.emission_energy_multiplier = 0.32
	_mutual_material.no_depth_test = true
	_mutual_material.render_priority = 4

	_mutual_outline_material = StandardMaterial3D.new()
	_mutual_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mutual_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mutual_outline_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mutual_outline_material.albedo_color = Color(0.015, 0.09, 0.085, 0.94)
	_mutual_outline_material.emission_enabled = true
	_mutual_outline_material.emission = Color(0.01, 0.08, 0.07, 1.0)
	_mutual_outline_material.emission_energy_multiplier = 0.06
	_mutual_outline_material.no_depth_test = true
	_mutual_outline_material.render_priority = 3

	_line_root = Node3D.new()
	_line_root.name = "ReachArrows"
	add_child(_line_root)

	_arrow_mesh = ImmediateMesh.new()
	_arrow_instance = MeshInstance3D.new()
	_arrow_instance.name = "ReachArrowMesh"
	_arrow_instance.mesh = _arrow_mesh
	_arrow_instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	_line_root.add_child(_arrow_instance)


static func reach_arrow_segment(
	flanker_center: Vector3,
	flanker_half: Vector3,
	target_center: Vector3,
	target_half: Vector3,
	cell_size: float
) -> PackedVector3Array:
	var delta := target_center - flanker_center
	var horizontal := Vector2(delta.x, delta.z)
	var horizontal_length := horizontal.length()
	if horizontal_length <= EPSILON:
		return PackedVector3Array()

	var horizontal_direction := horizontal / horizontal_length
	var flanker_boundary := _horizontal_box_boundary_distance(
		Vector2(flanker_half.x, flanker_half.z),
		horizontal_direction
	)
	var target_boundary := _horizontal_box_boundary_distance(
		Vector2(target_half.x, target_half.z),
		-horizontal_direction
	)
	var safe_cell := maxf(cell_size, 0.001)
	var total_horizontal := maxf(horizontal_length, EPSILON)
	var start_fraction := clampf(
		(flanker_boundary + safe_cell * 0.04) / total_horizontal,
		0.0,
		0.45
	)
	var end_fraction := clampf(
		1.0 - (target_boundary + safe_cell * 0.07) / total_horizontal,
		0.55,
		1.0
	)
	if end_fraction <= start_fraction:
		return PackedVector3Array()

	var start := flanker_center.lerp(target_center, start_fraction)
	var end := flanker_center.lerp(target_center, end_fraction)
	# Same-plane flankers are already projected to their shared base plane.
	# A tiny lift only prevents z-fighting with the rendered grid/terrain.
	var lift := Vector3.UP * safe_cell * 0.018
	start += lift
	end += lift
	return PackedVector3Array([start, end])


static func flanking_arrow_segment(
	flanker_center: Vector3,
	flanker_half: Vector3,
	target_center: Vector3,
	target_half: Vector3,
	cell_size: float
) -> PackedVector3Array:
	# Compatibility alias for older callers/tests.
	return reach_arrow_segment(
		flanker_center,
		flanker_half,
		target_center,
		target_half,
		cell_size
	)


static func should_use_mutual_adjacent_marker(
	first_reaches: bool,
	second_reaches: bool,
	tactical_distance_feet: float
) -> bool:
	return (
		first_reaches
		and second_reaches
		and tactical_distance_feet <= 5.001
	)


static func mutual_reach_marker_segment(
	first_base: Vector3,
	first_half: Vector3,
	second_base: Vector3,
	second_half: Vector3,
	cell_size: float
) -> PackedVector3Array:
	var horizontal := Vector2(
		second_base.x - first_base.x,
		second_base.z - first_base.z
	)
	var horizontal_length := horizontal.length()
	if horizontal_length <= EPSILON:
		return PackedVector3Array()

	var safe_cell := maxf(cell_size, 0.001)
	var direction_2d := horizontal / horizontal_length
	var direction := Vector3(direction_2d.x, 0.0, direction_2d.y)
	var right := Vector3(-direction.z, 0.0, direction.x)

	var first_boundary_distance := _horizontal_box_boundary_distance(
		Vector2(first_half.x, first_half.z),
		direction_2d
	)
	var second_boundary_distance := _horizontal_box_boundary_distance(
		Vector2(second_half.x, second_half.z),
		-direction_2d
	)
	var first_boundary := first_base + direction * first_boundary_distance
	var second_boundary := second_base - direction * second_boundary_distance
	var midpoint := (first_boundary + second_boundary) * 0.5

	# Move the compact ↔ marker slightly beside the touching edge so it stays
	# visible instead of sitting underneath both bases.
	var lateral_offset := right * safe_cell * 0.12
	var half_length := safe_cell * 0.22
	var lift := Vector3.UP * safe_cell * 0.022
	var start := midpoint - direction * half_length + lateral_offset + lift
	var end := midpoint + direction * half_length + lateral_offset + lift
	return PackedVector3Array([start, end])


static func _horizontal_box_boundary_distance(
	half_extents: Vector2,
	direction: Vector2
) -> float:
	var distance := INF
	if absf(direction.x) > EPSILON:
		distance = minf(
			distance,
			maxf(half_extents.x, 0.0) / absf(direction.x)
		)
	if absf(direction.y) > EPSILON:
		distance = minf(
			distance,
			maxf(half_extents.y, 0.0) / absf(direction.y)
		)
	return 0.0 if distance == INF else distance


func _render_arrows(
	points: Array[Vector3],
	mutual_points: Array[Vector3]
) -> void:
	if _arrow_mesh == null:
		return

	_arrow_mesh.clear_surfaces()
	# The 2D overlay projects the same segments onto the visible floor.
	# Keep the world-space mesh from drawing a second, offset set of arrows.
	_arrow_instance.visible = not (
		board_root.has_method("is_2d_view_enabled")
		and bool(board_root.call("is_2d_view_enabled"))
	)
	if not _arrow_instance.visible:
		return
	if points.is_empty() and mutual_points.is_empty():
		return

	var safe_cell := maxf(float(board_root.get("cell_size")), 0.001)
	var body_half_width := safe_cell * 0.028
	var head_half_width := safe_cell * 0.095

	if not points.is_empty():
		# One-way / longer-range arrows.
		_arrow_mesh.surface_begin(
			Mesh.PRIMITIVE_TRIANGLES,
			_line_outline_material
		)
		for index: int in range(0, points.size() - 1, 2):
			_append_flat_arrow_vertices(
				_arrow_mesh,
				points[index],
				points[index + 1],
				body_half_width * 1.55,
				head_half_width * 1.28,
				safe_cell,
				0.0
			)
		_arrow_mesh.surface_end()

		_arrow_mesh.surface_begin(
			Mesh.PRIMITIVE_TRIANGLES,
			_line_material
		)
		for index: int in range(0, points.size() - 1, 2):
			_append_flat_arrow_vertices(
				_arrow_mesh,
				points[index],
				points[index + 1],
				body_half_width,
				head_half_width,
				safe_cell,
				safe_cell * 0.002
			)
		_arrow_mesh.surface_end()

	if not mutual_points.is_empty():
		var mutual_body_half_width := safe_cell * 0.024
		var mutual_head_half_width := safe_cell * 0.080

		_arrow_mesh.surface_begin(
			Mesh.PRIMITIVE_TRIANGLES,
			_mutual_outline_material
		)
		for index: int in range(0, mutual_points.size() - 1, 2):
			_append_double_arrow_vertices(
				_arrow_mesh,
				mutual_points[index],
				mutual_points[index + 1],
				mutual_body_half_width * 1.55,
				mutual_head_half_width * 1.30,
				safe_cell,
				0.0
			)
		_arrow_mesh.surface_end()

		_arrow_mesh.surface_begin(
			Mesh.PRIMITIVE_TRIANGLES,
			_mutual_material
		)
		for index: int in range(0, mutual_points.size() - 1, 2):
			_append_double_arrow_vertices(
				_arrow_mesh,
				mutual_points[index],
				mutual_points[index + 1],
				mutual_body_half_width,
				mutual_head_half_width,
				safe_cell,
				safe_cell * 0.002
			)
		_arrow_mesh.surface_end()


static func _append_flat_arrow_vertices(
	mesh: ImmediateMesh,
	start: Vector3,
	end: Vector3,
	body_half_width: float,
	head_half_width: float,
	cell_size: float,
	lift: float
) -> void:
	var delta := end - start
	var length := delta.length()
	if length <= EPSILON:
		return

	var direction := delta / length
	var right := Vector3.UP.cross(direction)
	if right.length_squared() <= EPSILON * EPSILON:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var head_length := minf(
		maxf(cell_size * 0.18, length * 0.18),
		length * 0.36
	)
	var safe_head_length := minf(
		maxf(head_length, 0.001),
		length * 0.48
	)
	var offset := Vector3.UP * lift
	var lifted_start := start + offset
	var lifted_end := end + offset
	var neck := lifted_end - direction * safe_head_length

	var body_left_start := lifted_start - right * body_half_width
	var body_right_start := lifted_start + right * body_half_width
	var body_left_end := neck - right * body_half_width
	var body_right_end := neck + right * body_half_width
	var head_left := neck - right * head_half_width
	var head_right := neck + right * head_half_width

	var vertices := PackedVector3Array([
		body_left_start, body_right_start, body_left_end,
		body_right_start, body_right_end, body_left_end,
		head_left, head_right, lifted_end,
	])
	for vertex: Vector3 in vertices:
		mesh.surface_add_vertex(vertex)


static func _append_double_arrow_vertices(
	mesh: ImmediateMesh,
	start: Vector3,
	end: Vector3,
	body_half_width: float,
	head_half_width: float,
	cell_size: float,
	lift: float
) -> void:
	var delta := end - start
	var length := delta.length()
	if length <= EPSILON:
		return

	var direction := delta / length
	var right := Vector3.UP.cross(direction)
	if right.length_squared() <= EPSILON * EPSILON:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var head_length := minf(
		maxf(cell_size * 0.11, length * 0.22),
		length * 0.30
	)
	var offset := Vector3.UP * lift
	var left_tip := start + offset
	var right_tip := end + offset
	var left_neck := left_tip + direction * head_length
	var right_neck := right_tip - direction * head_length

	var shaft_left_a := left_neck - right * body_half_width
	var shaft_left_b := left_neck + right * body_half_width
	var shaft_right_a := right_neck - right * body_half_width
	var shaft_right_b := right_neck + right * body_half_width

	var left_head_a := left_neck - right * head_half_width
	var left_head_b := left_neck + right * head_half_width
	var right_head_a := right_neck - right * head_half_width
	var right_head_b := right_neck + right * head_half_width

	var vertices := PackedVector3Array([
		# Short central shaft.
		shaft_left_a, shaft_left_b, shaft_right_a,
		shaft_left_b, shaft_right_b, shaft_right_a,
		# Arrow head pointing toward the first creature.
		left_tip, left_head_a, left_head_b,
		# Arrow head pointing toward the second creature.
		right_tip, right_head_b, right_head_a,
	])
	for vertex: Vector3 in vertices:
		mesh.surface_add_vertex(vertex)
