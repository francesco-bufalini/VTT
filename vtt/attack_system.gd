extends Node

var board_root: Node3D
var ui_root: CanvasLayer
var measurement_tool: Node3D

var _attacker: CharacterBody3D
var _attack_data: Dictionary = {}
var _targeting: bool = false
var _instruction_panel: PanelContainer
var _instruction_label: Label
var _result_generation: int = 0
var _range_preview: MeshInstance3D
var _range_preview_center: Vector3 = Vector3.INF
var _range_preview_half_footprint: float = -1.0
var _range_preview_radius: float = -1.0
var _all_reaches_visible: bool = false
var _all_reach_root: Node3D
var _all_reach_elapsed: float = 0.0
var _all_reach_signature: String = ""


func setup(root: Node3D) -> void:
	board_root = root
	ui_root = board_root.get_node_or_null("UI") as CanvasLayer
	measurement_tool = board_root.get_node_or_null("MeasurementTool") as Node3D
	_build_instruction_ui()
	_all_reach_root = Node3D.new()
	_all_reach_root.name = "AllCreatureReachSpheres"
	add_child(_all_reach_root)
	set_process(true)


func is_targeting() -> bool:
	return _targeting


func start_attack(
	attacker: CharacterBody3D,
	attack_data: Dictionary
) -> bool:
	if (
		attacker == null
		or not is_instance_valid(attacker)
		or attack_data.is_empty()
	):
		return false

	cancel_attack(false)
	_attacker = attacker
	_attack_data = attack_data.duplicate(true)
	_targeting = true
	_result_generation += 1

	var range_feet := maxf(
		5.0,
		float(_attack_data.get("range_feet", 5.0))
	)
	_show_range(range_feet)
	_set_instruction(
		"%s · gittata %d ft — scegli un token bersaglio"
		% [
			String(_attack_data.get("name", "Attacco")),
			int(round(range_feet)),
		]
	)
	if board_root.has_method("capture_camera_control"):
		board_root.call("capture_camera_control")
	return true


func cancel_attack(show_message: bool = true) -> void:
	var was_targeting := _targeting
	_targeting = false
	_attacker = null
	_attack_data.clear()
	_clear_target_highlight()
	_hide_range()
	if show_message and was_targeting:
		_show_temporary_result("Attacco annullato.", 1.5)
	elif not show_message:
		_hide_instruction()


func handle_input(event: InputEvent) -> bool:
	if not _targeting:
		return false

	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		cancel_attack(true)
		return true

	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		var screen_position: Vector2 = (
			board_root.get_viewport().get_visible_rect().size * 0.5
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else event.position
		)
		_try_attack_target(screen_position)
		return true

	return false


func _process(delta: float) -> void:
	if _all_reaches_visible:
		_all_reach_elapsed += delta
		if _all_reach_elapsed >= 0.12:
			_all_reach_elapsed = 0.0
			_refresh_all_reach_spheres(false)

	if not _targeting:
		return
	if _attacker == null or not is_instance_valid(_attacker):
		cancel_attack(false)
		return

	var screen_position := board_root.get_viewport().get_visible_rect().size * 0.5
	var target := _token_at_screen(screen_position)
	if (
		target != null
		and target != _attacker
		and _target_in_range(target)
	):
		_set_target_highlight(target)
	else:
		_clear_target_highlight()


func set_all_reaches_visible(enabled: bool) -> void:
	_all_reaches_visible = enabled
	_all_reach_signature = ""
	if enabled:
		_refresh_all_reach_spheres(true)
	elif _all_reach_root != null:
		for child: Node in _all_reach_root.get_children():
			child.queue_free()


func are_all_reaches_visible() -> bool:
	return _all_reaches_visible


func _reach_tokens() -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	if board_root == null:
		return result
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			node is CharacterBody3D
			and is_instance_valid(node)
			and board_root.is_ancestor_of(node)
			and not node.is_queued_for_deletion()
		):
			result.append(node as CharacterBody3D)
	return result


func _refresh_all_reach_spheres(force: bool) -> void:
	if not _all_reaches_visible or _all_reach_root == null:
		return

	var cell_size := maxf(0.001, float(board_root.get("cell_size")))
	var tokens := _reach_tokens()
	var parts := PackedStringArray()
	for token: CharacterBody3D in tokens:
		var reach_feet := 5.0
		if token.has_method("get_reach_feet"):
			reach_feet = maxf(float(token.call("get_reach_feet")), 5.0)
		var footprint_world := _token_footprint_world(token, cell_size)
		parts.append(
			"%d:%s:%.3f:%.3f:%.3f:%.2f:%.2f"
			% [
				token.get_instance_id(),
				str(token.global_position.x),
				token.global_position.y,
				token.global_position.z,
				footprint_world,
				reach_feet,
				cell_size
			]
		)
	var signature := "|".join(parts)
	if not force and signature == _all_reach_signature:
		return
	_all_reach_signature = signature

	for child: Node in _all_reach_root.get_children():
		child.queue_free()

	for token: CharacterBody3D in tokens:
		_add_reach_sphere(token, cell_size)


func _add_reach_sphere(
	token: CharacterBody3D,
	cell_size: float
) -> void:
	var reach_feet := 5.0
	if token.has_method("get_reach_feet"):
		reach_feet = maxf(float(token.call("get_reach_feet")), 5.0)
	var footprint_world := _token_footprint_world(token, cell_size)
	var radius := (
		reach_feet / 5.0 * cell_size
		+ footprint_world * 0.5
	)

	var sphere := SphereMesh.new()
	sphere.radius = maxf(radius, cell_size * 0.5)
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.18, 0.58, 1.0, 0.045)
	material.emission_enabled = true
	material.emission = Color(0.08, 0.28, 0.72, 1.0)
	material.emission_energy_multiplier = 0.10

	var preview := MeshInstance3D.new()
	preview.name = "Reach_%d" % token.get_instance_id()
	preview.mesh = sphere
	preview.material_override = material
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_all_reach_root.add_child(preview)
	preview.global_position = token.global_position


func _try_attack_target(screen_position: Vector2) -> void:
	if _attacker == null or not is_instance_valid(_attacker):
		cancel_attack(false)
		return

	var target := _token_at_screen(screen_position)
	if target == null:
		_set_instruction("Scegli un token bersaglio.")
		return
	if target == _attacker:
		_set_instruction("L'attaccante non può essere il proprio bersaglio.")
		return

	var range_feet := float(_attack_data.get("range_feet", 5.0))
	var distance_feet := _distance_feet(_attacker, target)
	if distance_feet > range_feet + 0.001:
		_set_instruction(
			"Bersaglio fuori gittata: %.1f ft / %d ft."
			% [distance_feet, int(round(range_feet))]
		)
		return

	var expression := String(
		_attack_data.get("damage_expression", "0")
	).strip_edges()
	var damage := maxi(0, _roll_damage_expression(expression))
	var attack_name := String(_attack_data.get("name", "Attacco"))
	var target_name := _token_name(target)

	var applied := false
	var hp_result: Dictionary = {}
	var sheets: Node = board_root.get_node_or_null("CreatureArea")
	if sheets != null and is_instance_valid(sheets) and sheets.has_method("apply_attack_damage_to_token"):
		var result: Variant = sheets.call("apply_attack_damage_to_token", target, damage)
		if result is Dictionary:
			hp_result = result as Dictionary
			applied = bool(hp_result.get("applied", false))

	# Keep the rolled damage on every token, including NPCs that do not yet
	# have a managed HP pool. This lets later monster-sheet work reuse it.
	target.set_meta("last_attack_damage", damage)
	target.set_meta("last_attack_name", attack_name)

	_targeting = false
	_clear_target_highlight()
	_hide_range()
	_attacker = null
	_attack_data.clear()

	var message := "%s colpisce %s: %d danni" % [
		attack_name,
		target_name,
		damage,
	]
	if applied:
		if int(hp_result.get("second_form_hp", 0)) > 0:
			message += " · Forma %d/%d PF" % [
				int(hp_result.get("second_form_hp", 0)),
				int(hp_result.get("second_form_max_hp", 0))
			]
		else:
			message += " · PF %d/%d" % [
				int(hp_result.get("current_hp", 0)),
				int(hp_result.get("max_hp", 0)),
			]
	else:
		message += " · bersaglio senza PF gestiti"
	_show_temporary_result(message, 3.0)


static func distance_from_footprint_to_point_world(
	attacker_center: Vector3,
	footprint_world: float,
	target_point: Vector3
) -> float:
	# Weapon range starts from the whole horizontal space occupied by the
	# attacker, not from the token centre. The closest point can therefore be
	# on a side or at a corner of the footprint. Vertical distance keeps using
	# the token centre, preserving the previous 3D targeting behaviour.
	var half_footprint := maxf(0.0, footprint_world * 0.5)
	var delta := target_point - attacker_center
	var outside := Vector3(
		maxf(absf(delta.x) - half_footprint, 0.0),
		absf(delta.y),
		maxf(absf(delta.z) - half_footprint, 0.0)
	)
	return outside.length()


func _token_footprint_world(token: Node3D, cell_size: float) -> float:
	if token != null and token.has_method("get_footprint_cells"):
		return (
			maxf(float(token.call("get_footprint_cells")), 0.5)
			* cell_size
		)
	return cell_size


func _distance_feet(
	attacker: Node3D,
	target: Node3D
) -> float:
	var cell_size := maxf(
		0.001,
		float(board_root.get("cell_size"))
	)
	var footprint_world := _token_footprint_world(attacker, cell_size)
	return (
		distance_from_footprint_to_point_world(
			attacker.global_position,
			footprint_world,
			target.global_position
		)
		/ cell_size
		* 5.0
	)


func _target_in_range(target: CharacterBody3D) -> bool:
	if (
		target == null
		or _attacker == null
		or not is_instance_valid(target)
		or not is_instance_valid(_attacker)
	):
		return false
	return (
		_distance_feet(_attacker, target)
		<= float(_attack_data.get("range_feet", 5.0)) + 0.001
	)


func _show_range(range_feet: float) -> void:
	if _attacker == null or not is_instance_valid(_attacker):
		return

	var cell_size := maxf(
		0.001,
		float(board_root.get("cell_size"))
	)
	var footprint_world := _token_footprint_world(_attacker, cell_size)
	var half_footprint := footprint_world * 0.5
	var radius_world := maxf(
		range_feet / 5.0 * cell_size,
		cell_size * 0.05
	)
	var center := _attacker.global_position

	if (
		is_instance_valid(_range_preview)
		and _range_preview_center.is_equal_approx(center)
		and is_equal_approx(
			_range_preview_half_footprint,
			half_footprint
		)
		and is_equal_approx(_range_preview_radius, radius_world)
	):
		_range_preview.show()
		return

	if not is_instance_valid(_range_preview):
		_range_preview = MeshInstance3D.new()
		_range_preview.name = "AttackRangePreview"
		add_child(_range_preview)

	_range_preview.mesh = _build_rounded_footprint_range_mesh(
		half_footprint,
		radius_world
	)
	_range_preview.global_position = center

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.18, 0.58, 1.0, 0.055)
	material.emission_enabled = true
	material.emission = Color(0.08, 0.28, 0.72, 1.0)
	material.emission_energy_multiplier = 0.14
	_range_preview.material_override = material

	_range_preview_center = center
	_range_preview_half_footprint = half_footprint
	_range_preview_radius = radius_world
	_range_preview.show()


func _build_rounded_footprint_range_mesh(
	half_footprint: float,
	radius: float
) -> ArrayMesh:
	# Exact rounded offset of the attacker's horizontal square. This is the
	# Minkowski sum of the occupied square and a sphere of weapon range, so
	# the visible range genuinely starts at every side and every corner.
	var half_extents := Vector3(
		maxf(half_footprint, 0.0),
		0.0,
		maxf(half_footprint, 0.0)
	)
	var safe_radius := maxf(radius, 0.001)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	_add_range_box_faces(surface, half_extents, safe_radius)
	_add_range_edge_patches(surface, half_extents, safe_radius, 10)
	_add_range_corner_patches(surface, half_extents, safe_radius, 8)

	return surface.commit()


func _add_range_box_faces(
	surface: SurfaceTool,
	half_extents: Vector3,
	radius: float
) -> void:
	var hx := half_extents.x
	var hy := half_extents.y
	var hz := half_extents.z

	# Top and bottom are the only non-degenerate face patches for the flat
	# footprint used by weapon range. Keeping the generic six-face form makes
	# the geometry helper safe if vertical extents are added later.
	_add_range_quad(
		surface,
		Vector3(-hx, hy + radius, -hz),
		Vector3(hx, hy + radius, -hz),
		Vector3(hx, hy + radius, hz),
		Vector3(-hx, hy + radius, hz)
	)
	_add_range_quad(
		surface,
		Vector3(-hx, -hy - radius, hz),
		Vector3(hx, -hy - radius, hz),
		Vector3(hx, -hy - radius, -hz),
		Vector3(-hx, -hy - radius, -hz)
	)

	if hy > 0.000001:
		_add_range_quad(
			surface,
			Vector3(hx + radius, -hy, -hz),
			Vector3(hx + radius, hy, -hz),
			Vector3(hx + radius, hy, hz),
			Vector3(hx + radius, -hy, hz)
		)
		_add_range_quad(
			surface,
			Vector3(-hx - radius, -hy, hz),
			Vector3(-hx - radius, hy, hz),
			Vector3(-hx - radius, hy, -hz),
			Vector3(-hx - radius, -hy, -hz)
		)
		_add_range_quad(
			surface,
			Vector3(-hx, -hy, hz + radius),
			Vector3(hx, -hy, hz + radius),
			Vector3(hx, hy, hz + radius),
			Vector3(-hx, hy, hz + radius)
		)
		_add_range_quad(
			surface,
			Vector3(-hx, hy, -hz - radius),
			Vector3(hx, hy, -hz - radius),
			Vector3(hx, -hy, -hz - radius),
			Vector3(-hx, -hy, -hz - radius)
		)


func _add_range_edge_patches(
	surface: SurfaceTool,
	half_extents: Vector3,
	radius: float,
	segments: int
) -> void:
	var hx := half_extents.x
	var hy := half_extents.y
	var hz := half_extents.z
	var safe_segments := maxi(2, segments)

	# Edges parallel to X. With a flat footprint, the ±Y variants combine
	# into the rounded front/back half-cylinders.
	for sy: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var base_a := Vector3(-hx, sy * hy, sz * hz)
			var base_b := Vector3(hx, sy * hy, sz * hz)
			for index: int in range(safe_segments):
				var a0 := (
					PI * 0.5 * float(index) / float(safe_segments)
				)
				var a1 := (
					PI * 0.5 * float(index + 1)
					/ float(safe_segments)
				)
				var offset0 := Vector3(
					0.0,
					sy * cos(a0) * radius,
					sz * sin(a0) * radius
				)
				var offset1 := Vector3(
					0.0,
					sy * cos(a1) * radius,
					sz * sin(a1) * radius
				)
				_add_range_quad(
					surface,
					base_a + offset0,
					base_b + offset0,
					base_b + offset1,
					base_a + offset1
				)

	# Edges parallel to Z. The ±Y variants form the left/right
	# half-cylinders.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var base_a := Vector3(sx * hx, sy * hy, -hz)
			var base_b := Vector3(sx * hx, sy * hy, hz)
			for index: int in range(safe_segments):
				var a0 := (
					PI * 0.5 * float(index) / float(safe_segments)
				)
				var a1 := (
					PI * 0.5 * float(index + 1)
					/ float(safe_segments)
				)
				var offset0 := Vector3(
					sx * cos(a0) * radius,
					sy * sin(a0) * radius,
					0.0
				)
				var offset1 := Vector3(
					sx * cos(a1) * radius,
					sy * sin(a1) * radius,
					0.0
				)
				_add_range_quad(
					surface,
					base_a + offset0,
					base_b + offset0,
					base_b + offset1,
					base_a + offset1
				)

	# Parallel-Y edges only exist for a footprint with vertical thickness.
	if hy <= 0.000001:
		return
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var base_a := Vector3(sx * hx, -hy, sz * hz)
			var base_b := Vector3(sx * hx, hy, sz * hz)
			for index: int in range(safe_segments):
				var a0 := (
					PI * 0.5 * float(index) / float(safe_segments)
				)
				var a1 := (
					PI * 0.5 * float(index + 1)
					/ float(safe_segments)
				)
				var offset0 := Vector3(
					sx * cos(a0) * radius,
					0.0,
					sz * sin(a0) * radius
				)
				var offset1 := Vector3(
					sx * cos(a1) * radius,
					0.0,
					sz * sin(a1) * radius
				)
				_add_range_quad(
					surface,
					base_a + offset0,
					base_b + offset0,
					base_b + offset1,
					base_a + offset1
				)


func _add_range_corner_patches(
	surface: SurfaceTool,
	half_extents: Vector3,
	radius: float,
	segments: int
) -> void:
	var safe_segments := maxi(2, segments)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var base := Vector3(
					sx * half_extents.x,
					sy * half_extents.y,
					sz * half_extents.z
				)
				for phi_index: int in range(safe_segments):
					var phi0 := (
						PI * 0.5 * float(phi_index)
						/ float(safe_segments)
					)
					var phi1 := (
						PI * 0.5 * float(phi_index + 1)
						/ float(safe_segments)
					)
					for theta_index: int in range(safe_segments):
						var theta0 := (
							PI * 0.5 * float(theta_index)
							/ float(safe_segments)
						)
						var theta1 := (
							PI * 0.5 * float(theta_index + 1)
							/ float(safe_segments)
						)
						var p00 := base + _range_octant_vector(
							sx, sy, sz, phi0, theta0
						) * radius
						var p10 := base + _range_octant_vector(
							sx, sy, sz, phi1, theta0
						) * radius
						var p11 := base + _range_octant_vector(
							sx, sy, sz, phi1, theta1
						) * radius
						var p01 := base + _range_octant_vector(
							sx, sy, sz, phi0, theta1
						) * radius
						_add_range_quad(surface, p00, p10, p11, p01)


func _range_octant_vector(
	sx: float,
	sy: float,
	sz: float,
	phi: float,
	theta: float
) -> Vector3:
	var sin_phi := sin(phi)
	return Vector3(
		sx * sin_phi * cos(theta),
		sy * cos(phi),
		sz * sin_phi * sin(theta)
	)


func _add_range_quad(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3
) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(d)


func _hide_range() -> void:
	if is_instance_valid(_range_preview):
		_range_preview.hide()
	# Compatibility cleanup in case an older attack preview was already
	# visible when scripts were hot-reloaded.
	if (
		measurement_tool != null
		and is_instance_valid(measurement_tool)
		and measurement_tool.has_method("hide_spell_range_preview")
	):
		measurement_tool.call("hide_spell_range_preview")


func _token_at_screen(
	screen_position: Vector2
) -> CharacterBody3D:
	if (
		board_root == null
		or not is_instance_valid(board_root)
		or not board_root.has_method("get_attack_token_at_screen")
	):
		return null
	var value: Variant = board_root.call(
		"get_attack_token_at_screen",
		screen_position
	)
	if value is CharacterBody3D:
		return value as CharacterBody3D
	return null


func _set_target_highlight(target: CharacterBody3D) -> void:
	if board_root.has_method("set_affected_token_highlight"):
		board_root.call(
			"set_affected_token_highlight",
			[target]
		)


func _clear_target_highlight() -> void:
	if (
		board_root != null
		and is_instance_valid(board_root)
		and board_root.has_method("set_affected_token_highlight")
	):
		board_root.call("set_affected_token_highlight", [])


func _roll_damage_expression(expression: String) -> int:
	var normalized := expression.to_lower().replace(" ", "")
	if normalized.is_empty() or normalized == "—":
		return 0

	normalized = normalized.replace("-", "+-")
	var total := 0
	for raw_term: String in normalized.split("+", false):
		var term := raw_term.strip_edges()
		if term.is_empty():
			continue
		var d_index := term.find("d")
		if d_index >= 0:
			var count_text := term.substr(0, d_index)
			var sides_text := term.substr(d_index + 1)
			var term_sign := 1
			if count_text.begins_with("-"):
				term_sign = -1
				count_text = count_text.substr(1)
			var count := 1 if count_text.is_empty() else int(count_text)
			var sides := int(sides_text)
			if count <= 0 or sides <= 0:
				continue
			for _roll_index: int in range(count):
				total += term_sign * randi_range(1, sides)
		else:
			total += int(term)
	return total


func _token_name(token: CharacterBody3D) -> String:
	if token.has_method("get_display_name"):
		var display_name := String(
			token.call("get_display_name")
		).strip_edges()
		if not display_name.is_empty():
			return display_name
	return String(token.name)


func _build_instruction_ui() -> void:
	if ui_root == null:
		return
	_instruction_panel = PanelContainer.new()
	_instruction_panel.name = "AttackTargetInstruction"
	_instruction_panel.anchor_left = 0.5
	_instruction_panel.anchor_right = 0.5
	_instruction_panel.anchor_top = 0.0
	_instruction_panel.anchor_bottom = 0.0
	_instruction_panel.offset_left = -310.0
	_instruction_panel.offset_right = 310.0
	_instruction_panel.offset_top = 58.0
	_instruction_panel.offset_bottom = 102.0
	_instruction_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.025, 0.035, 0.96)
	style.border_color = Color(0.65, 0.22, 0.18, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	_instruction_panel.add_theme_stylebox_override("panel", style)
	ui_root.add_child(_instruction_panel)

	_instruction_label = Label.new()
	_instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instruction_label.add_theme_font_size_override("font_size", 15)
	_instruction_panel.add_child(_instruction_label)
	_instruction_panel.hide()


func _set_instruction(message: String) -> void:
	if _instruction_label != null:
		_instruction_label.text = message
	if _instruction_panel != null:
		_instruction_panel.show()


func _hide_instruction() -> void:
	if _instruction_panel != null:
		_instruction_panel.hide()


func _show_temporary_result(
	message: String,
	seconds: float
) -> void:
	_result_generation += 1
	var generation := _result_generation
	_set_instruction(message)
	var timer := get_tree().create_timer(maxf(0.2, seconds))
	timer.timeout.connect(
		func() -> void:
			if generation == _result_generation and not _targeting:
				_hide_instruction()
	)


func get_current_attack() -> Dictionary:
	return _attack_data.duplicate(true)
