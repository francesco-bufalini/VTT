extends Node

const RangeGeometry = preload("res://vtt/attack_range_geometry.gd")
const RangeOverlay2D = preload("res://vtt/attack_range_overlay_2d.gd")
const NORMAL_RANGE_COLOR := Color(0.22, 0.68, 1.0, 0.96)
const LONG_RANGE_COLOR := Color(1.0, 0.61, 0.22, 0.98)

var board_root: Node3D
var ui_root: CanvasLayer
var measurement_tool: Node3D

var _attacker: CharacterBody3D
var _attack_data: Dictionary = {}
var _targeting: bool = false
var _preview_only: bool = false
var _preview_selected_targets: Array[CharacterBody3D] = []
var _instruction_panel: PanelContainer
var _instruction_label: Label
var _result_generation: int = 0
var _range_preview: MeshInstance3D
var _long_range_preview: MeshInstance3D
var _range_outline: MeshInstance3D
var _long_range_outline: MeshInstance3D
var _range_overlay_2d: Control
var _range_normal_feet: float = 0.0
var _range_long_feet: float = 0.0
var _range_preview_long_radius: float = -1.0
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
	if ui_root != null:
		_range_overlay_2d = RangeOverlay2D.new()
		ui_root.add_child(_range_overlay_2d)
		_range_overlay_2d.call("setup", board_root, self)
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
	_preview_only = false
	_preview_selected_targets.clear()
	_result_generation += 1

	var limits: Vector2 = ranged_limits(_attack_data)
	_range_normal_feet = limits.x
	_range_long_feet = limits.y
	_show_range(_range_normal_feet, _range_long_feet)
	if _range_long_feet > _range_normal_feet:
		_set_instruction(
			"%s · gittata %d/%d ft (oltre %d ft: svantaggio) — scegli un token"
			% [
				String(_attack_data.get("name", "Attacco")),
				int(round(_range_normal_feet)),
				int(round(_range_long_feet)),
				int(round(_range_normal_feet))
			]
		)
	else:
		_set_instruction(
			"%s · gittata %d ft — scegli un token bersaglio"
			% [
				String(_attack_data.get("name", "Attacco")),
				int(round(_range_normal_feet))
			]
		)
	if board_root.has_method("capture_camera_control"):
		board_root.call("capture_camera_control")
	return true


# Read-only preview: selecting targets never rolls or applies damage.
func preview_attack_range(attacker: CharacterBody3D, attack_data: Dictionary) -> bool:
	if not start_attack(attacker, attack_data):
		return false
	_preview_only = true
	_set_instruction("%s · anteprima gittata: clic per selezionare bersagli, Esc per chiudere" % String(attack_data.get("name", "Attacco")))
	return true


func preview_selected_targets() -> Array[CharacterBody3D]:
	return _preview_selected_targets.duplicate()


func preview_targets_in_range() -> Array[CharacterBody3D]:
	var targets: Array[CharacterBody3D] = []
	if not _targeting or _attacker == null or not is_instance_valid(_attacker):
		return targets
	for token: CharacterBody3D in _reach_tokens():
		if token != _attacker and _target_in_range(token):
			targets.append(token)
	return targets


func cancel_attack(show_message: bool = true) -> void:
	var was_targeting := _targeting
	_targeting = false
	_preview_only = false
	_preview_selected_targets.clear()
	_attacker = null
	_attack_data.clear()
	_range_normal_feet = 0.0
	_range_long_feet = 0.0
	_clear_target_highlight()
	_hide_range()
	if show_message and was_targeting:
		_show_temporary_result("Attacco annullato.", 1.5)
	elif not show_message:
		_hide_instruction()


func handle_input(event: InputEvent) -> bool:
	if not _targeting:
		return false

	if _preview_only and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_attack(false)
		return true
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
		if _preview_only:
			var target: CharacterBody3D = _token_at_screen(screen_position)
			if target != null and target != _attacker and _target_in_range(target):
				if target in _preview_selected_targets:
					_preview_selected_targets.erase(target)
				else:
					_preview_selected_targets.append(target)
		else:
			_try_attack_target(screen_position)
		return true

	return false


func _process(delta: float) -> void:
	if _all_reach_root != null and board_root != null:
		_all_reach_root.visible = not (
			board_root.has_method("is_2d_view_enabled")
			and bool(board_root.call("is_2d_view_enabled"))
		)
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
	if _preview_only:
		# A previously selected creature can move outside the preview reach.
		for selected: CharacterBody3D in _preview_selected_targets.duplicate():
			if not is_instance_valid(selected) or not _target_in_range(selected):
				_preview_selected_targets.erase(selected)

	# 2D attacks point at the mouse, exactly like 2D spell targeting.
	_show_range(_range_normal_feet, _range_long_feet)
	var screen_position: Vector2 = (
		board_root.get_viewport().get_mouse_position()
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		else board_root.get_viewport().get_visible_rect().size * 0.5
	)
	if _preview_only:
		_clear_target_highlight()
		return
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
		var long_range: float = float(token.get_meta("active_weapon_long_range_feet", 0.0))
		parts.append(
			"%d:%s:%.3f:%.3f:%.3f:%.2f:%.2f:%.2f"
			% [
				token.get_instance_id(),
				str(token.global_position.x),
				token.global_position.y,
				token.global_position.z,
				footprint_world,
				reach_feet,
				long_range,
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
	var reach_feet: float = 5.0
	if token.has_method("get_reach_feet"):
		reach_feet = maxf(float(token.call("get_reach_feet")), 5.0)
	var long_range: float = float(token.get_meta("active_weapon_long_range_feet", 0.0))
	var half_footprint: float = _token_footprint_world(token, cell_size) * 0.5
	var ranges: Array[Dictionary] = [
		{"distance": reach_feet, "name": "Normal", "color": NORMAL_RANGE_COLOR}
	]
	if long_range > reach_feet:
		ranges.append({"distance": long_range, "name": "Long", "color": LONG_RANGE_COLOR})
	# Every creature has one hollow 3D sphere per range. Never use a
	# horizontal disc or fill the inside of the selected weapon's reach.
	for entry: Dictionary in ranges:
		var tint: Color = entry.get("color", NORMAL_RANGE_COLOR)
		var reach_world: float = float(entry.get("distance", 0.0)) / 5.0 * cell_size
		var sphere_radius: float = reach_world + half_footprint
		var label: String = String(entry.get("name", "Normal"))
		var wire := MeshInstance3D.new()
		wire.name = "Reach%s_%d" % [label, token.get_instance_id()]
		wire.mesh = RangeGeometry.sphere_wire_mesh(sphere_radius)
		wire.material_override = _range_material(tint, 0.80)
		wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_all_reach_root.add_child(wire)
		wire.global_position = token.global_position
		var equator := MeshInstance3D.new()
		equator.name = "Reach%sEquator_%d" % [label, token.get_instance_id()]
		equator.mesh = RangeGeometry.sphere_equator_mesh(sphere_radius)
		equator.material_override = _range_material(tint, 0.96)
		equator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_all_reach_root.add_child(equator)
		equator.global_position = token.global_position


static func ranged_limits(data: Dictionary) -> Vector2:
	var normal: float = maxf(5.0, float(data.get("range_feet", 5.0)))
	var long_range: float = float(data.get("long_range_feet", 0.0))
	if bool(data.get("melee", false)) or long_range <= normal:
		long_range = 0.0
	return Vector2(normal, long_range)


func _max_attack_range_feet() -> float:
	return maxf(_range_normal_feet, _range_long_feet)


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

	var range_feet: float = _max_attack_range_feet()
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
	if _range_long_feet > _range_normal_feet and distance_feet > _range_normal_feet + 0.001:
		message += " · gittata lunga: svantaggio al tiro per colpire"
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
		<= _max_attack_range_feet() + 0.001
	)


func _show_range(normal_feet: float, long_feet: float = 0.0) -> void:
	if _attacker == null or not is_instance_valid(_attacker):
		return

	var cell_size: float = maxf(0.001, float(board_root.get("cell_size")))
	var half_footprint: float = _token_footprint_world(_attacker, cell_size) * 0.5
	var normal_radius: float = maxf(normal_feet / 5.0 * cell_size, cell_size * 0.05)
	var long_radius: float = long_feet / 5.0 * cell_size if long_feet > normal_feet else 0.0
	var center: Vector3 = _attacker.global_position
	var show_3d: bool = not (
		board_root.has_method("is_2d_view_enabled")
		and bool(board_root.call("is_2d_view_enabled"))
	)
	var unchanged: bool = (
		is_instance_valid(_range_preview)
		and is_instance_valid(_range_outline)
		and _range_preview_center.is_equal_approx(center)
		and is_equal_approx(_range_preview_half_footprint, half_footprint)
		and is_equal_approx(_range_preview_radius, normal_radius)
		and is_equal_approx(_range_preview_long_radius, long_radius)
	)
	if unchanged:
		_range_preview.visible = show_3d
		_range_outline.visible = show_3d
		if long_radius > 0.0:
			if is_instance_valid(_long_range_preview):
				_long_range_preview.visible = show_3d
			if is_instance_valid(_long_range_outline):
				_long_range_outline.visible = show_3d
		return

	if not is_instance_valid(_range_preview):
		_range_preview = MeshInstance3D.new()
		_range_preview.name = "AttackNormalRange"
		add_child(_range_preview)
	if not is_instance_valid(_range_outline):
		_range_outline = MeshInstance3D.new()
		_range_outline.name = "AttackNormalRangeBorder"
		add_child(_range_outline)
	_range_preview.mesh = RangeGeometry.sphere_wire_mesh(normal_radius + half_footprint)
	_range_preview.material_override = _range_material(NORMAL_RANGE_COLOR, 0.80)
	_range_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_range_preview.global_position = center
	_range_preview.visible = show_3d
	_range_outline.mesh = RangeGeometry.sphere_equator_mesh(normal_radius + half_footprint)
	_range_outline.material_override = _range_material(NORMAL_RANGE_COLOR, 0.96)
	_range_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_range_outline.global_position = center
	_range_outline.visible = show_3d

	if long_radius > 0.0:
		if not is_instance_valid(_long_range_preview):
			_long_range_preview = MeshInstance3D.new()
			_long_range_preview.name = "AttackLongRange"
			add_child(_long_range_preview)
		if not is_instance_valid(_long_range_outline):
			_long_range_outline = MeshInstance3D.new()
			_long_range_outline.name = "AttackLongRangeBorder"
			add_child(_long_range_outline)
		_long_range_preview.mesh = RangeGeometry.sphere_wire_mesh(long_radius + half_footprint)
		_long_range_preview.material_override = _range_material(LONG_RANGE_COLOR, 0.80)
		_long_range_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_long_range_preview.global_position = center
		_long_range_preview.visible = show_3d
		_long_range_outline.mesh = RangeGeometry.sphere_equator_mesh(long_radius + half_footprint)
		_long_range_outline.material_override = _range_material(LONG_RANGE_COLOR, 0.96)
		_long_range_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_long_range_outline.global_position = center
		_long_range_outline.visible = show_3d
	else:
		if is_instance_valid(_long_range_preview):
			_long_range_preview.hide()
		if is_instance_valid(_long_range_outline):
			_long_range_outline.hide()

	_range_preview_center = center
	_range_preview_half_footprint = half_footprint
	_range_preview_radius = normal_radius
	_range_preview_long_radius = long_radius


func _range_material(color: Color, opacity: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Let nearby geometry occlude the rear of a shell in 3D. No solid
	# triangles are drawn, so nothing inside the sphere receives a tint.
	material.no_depth_test = false
	material.albedo_color = Color(color.r, color.g, color.b, opacity)
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 0.18
	return material


func _hide_range() -> void:
	if is_instance_valid(_range_preview):
		_range_preview.hide()
	if is_instance_valid(_range_outline):
		_range_outline.hide()
	if is_instance_valid(_long_range_preview):
		_long_range_preview.hide()
	if is_instance_valid(_long_range_outline):
		_long_range_outline.hide()
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


func select_mobile_preview_target(attacker: CharacterBody3D, target: CharacterBody3D, data: Dictionary) -> Dictionary:
	var limits := ranged_limits(data)
	var distance := _distance_feet(attacker, target)
	if distance > maxf(limits.x, limits.y) + 0.001:
		return {"ok": false, "error": "Bersaglio fuori gittata: %d ft." % int(ceil(distance))}
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if board_root.is_ancestor_of(node):
			node.set_meta("mobile_target_selected", node == target)
	board_root.call("set_affected_token_highlight", [target])
	return {"ok": true, "target_id": String(target.call("get_token_id")), "distance_feet": distance,
		"long_range": limits.y > limits.x and distance > limits.x}
