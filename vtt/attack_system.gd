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


func setup(root: Node3D) -> void:
	board_root = root
	ui_root = board_root.get_node_or_null("UI") as CanvasLayer
	measurement_tool = board_root.get_node_or_null("MeasurementTool") as Node3D
	_build_instruction_ui()
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


func _process(_delta: float) -> void:
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
	var player_area_value: Variant = board_root.get("player_area")
	if player_area_value is Node:
		var player_area := player_area_value as Node
		if (
			is_instance_valid(player_area)
			and player_area.has_method("apply_attack_damage_to_token")
		):
			var result: Variant = player_area.call(
				"apply_attack_damage_to_token",
				target,
				damage
			)
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
		message += " · PF %d/%d" % [
			int(hp_result.get("current_hp", 0)),
			int(hp_result.get("max_hp", 0)),
		]
	else:
		message += " · bersaglio senza PF gestiti"
	_show_temporary_result(message, 3.0)


func _distance_feet(
	attacker: Node3D,
	target: Node3D
) -> float:
	var cell_size := maxf(
		0.001,
		float(board_root.get("cell_size"))
	)
	return (
		attacker.global_position.distance_to(target.global_position)
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
	if (
		measurement_tool == null
		or not is_instance_valid(measurement_tool)
		or _attacker == null
		or not measurement_tool.has_method("show_spell_range_preview")
	):
		return
	var cell_size := maxf(
		0.001,
		float(board_root.get("cell_size"))
	)
	measurement_tool.call(
		"show_spell_range_preview",
		_attacker.global_position,
		range_feet / 5.0 * cell_size
	)


func _hide_range() -> void:
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
			var sign := 1
			if count_text.begins_with("-"):
				sign = -1
				count_text = count_text.substr(1)
			var count := 1 if count_text.is_empty() else int(count_text)
			var sides := int(sides_text)
			if count <= 0 or sides <= 0:
				continue
			for _roll_index: int in range(count):
				total += sign * randi_range(1, sides)
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
