extends Node

const DiceChatSync = preload("res://network/dice_chat_sync.gd")
const HISTORY_DIR := "user://dice_chat"
const PROFILE_PATH := "user://dice_chat/profile.cfg"
const MAX_HISTORY := 300

var board_root: Node3D
var ui_root: CanvasLayer
var sync: Node
var session_key := "1"
var history: Array[Dictionary] = []
var seen_ids: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _selected_identity_token_id := ""
var _scene_identity_configured := false
var _identity_change_mode := false
var _identity_placement_pending := false
var _identity_profile_choices: Array[Dictionary] = []
var _selected_die := "d20"
var _pending_identity_callback := Callable()

var toggle_button: Button
var panel: PanelContainer
var history_view: RichTextLabel
var chat_input: LineEdit
var status_label: Label
var dice_count_input: SpinBox
var dice_modifier_input: SpinBox
var roll_mode_input: OptionButton
var roll_button: Button
var scene_identity_dialog: ConfirmationDialog
var scene_identity_selector: OptionButton
var scene_identity_miniature_section: VBoxContainer
var scene_identity_miniature_search: LineEdit
var scene_identity_miniature_list: ItemList
var quick_result_panel: PanelContainer
var quick_result_label: Label
var _quick_result_generation := 0
var close_button: Button


func setup(
	root: Node3D,
	initial_session_key: String,
	tailscale_peer_provider: Callable
) -> void:
	board_root = root
	ui_root = board_root.get_node_or_null("UI") as CanvasLayer
	if ui_root == null:
		push_error("DiceRollerChat: UI CanvasLayer non trovato")
		queue_free()
		return

	rng.randomize()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(HISTORY_DIR)
	)
	_load_scene_identity()

	sync = DiceChatSync.new()
	sync.name = "DiceChatSync"
	add_child(sync)
	sync.call("setup", tailscale_peer_provider)
	sync.event_received.connect(_on_remote_event)
	sync.status_changed.connect(_on_sync_status)

	_build_ui()
	_build_scene_identity_dialog()
	set_session_key(initial_session_key)
	call_deferred("_prompt_initial_identity_after_scene_ready")


func set_session_key(value: String) -> void:
	var clean := value.strip_edges()
	if clean.is_empty():
		clean = "1"

	if clean == session_key and not history.is_empty():
		if sync != null:
			sync.call("listen", true, clean)
		return

	_save_history()
	session_key = clean
	_load_history()
	if sync != null:
		sync.call("listen", true, session_key)
	_render_history()


func toggle_panel() -> void:
	if panel == null:
		return
	if panel.visible:
		hide_panel()
	else:
		show_panel()


func show_panel() -> void:
	if panel == null:
		return
	if not ensure_scene_identity(Callable(self, "show_panel")):
		return
	if roll_mode_input != null:
		roll_mode_input.select(0)
	panel.show()
	if board_root.has_method("release_camera_control"):
		board_root.call("release_camera_control")
	elif board_root.has_method("_release_mouse"):
		board_root.call("_release_mouse")
	if chat_input != null:
		chat_input.call_deferred("grab_focus")


func hide_panel() -> void:
	if panel == null:
		return
	panel.hide()
	if board_root.has_method("capture_camera_control"):
		board_root.call("capture_camera_control")
	elif board_root.has_method("_capture_mouse"):
		board_root.call("_capture_mouse")


func _input(event: InputEvent) -> void:
	if (
		panel != null
		and panel.visible
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		hide_panel()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	toggle_button = Button.new()
	toggle_button.name = "DiceChatToggle"
	toggle_button.text = "d20"
	toggle_button.tooltip_text = "Dice roller e chat"
	toggle_button.anchor_left = 1.0
	toggle_button.anchor_top = 1.0
	toggle_button.anchor_right = 1.0
	toggle_button.anchor_bottom = 1.0
	toggle_button.offset_left = -70.0
	toggle_button.offset_top = -70.0
	toggle_button.offset_right = -12.0
	toggle_button.offset_bottom = -12.0
	toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	toggle_button.pressed.connect(toggle_panel)
	ui_root.add_child(toggle_button)

	panel = PanelContainer.new()
	panel.name = "DiceChatPanel"
	panel.anchor_left = 1.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -402.0
	panel.offset_top = -620.0
	panel.offset_right = -12.0
	panel.offset_bottom = -96.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.clip_contents = true
	panel.hide()
	ui_root.add_child(panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.028, 0.036, 0.98)
	panel_style.border_color = Color(0.48, 0.38, 0.24, 0.9)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_top = 9
	panel_style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", panel_style)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 7)
	panel.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	outer.add_child(header)

	var title := Label.new()
	title.text = "Dice Roller · Chat"
	title.add_theme_font_size_override("font_size", 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	close_button = Button.new()
	close_button.text = "×"
	close_button.tooltip_text = "Chiudi dice roller (Esc)"
	close_button.custom_minimum_size = Vector2(34, 30)
	close_button.pressed.connect(hide_panel)
	header.add_child(close_button)

	status_label = Label.new()
	status_label.text = "Partita %s · sincronizzazione automatica" % session_key
	status_label.modulate = Color(0.70, 0.74, 0.80, 1.0)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 12)
	outer.add_child(status_label)

	history_view = RichTextLabel.new()
	history_view.name = "DiceChatHistory"
	history_view.bbcode_enabled = true
	history_view.fit_content = false
	history_view.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	history_view.scroll_active = true
	history_view.selection_enabled = true
	history_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_view.custom_minimum_size = Vector2(0, 220)
	history_view.add_theme_constant_override("line_separation", 4)
	outer.add_child(history_view)

	var separator := HSeparator.new()
	outer.add_child(separator)

	var roll_settings := HBoxContainer.new()
	roll_settings.add_theme_constant_override("separation", 8)
	outer.add_child(roll_settings)

	var count_label := Label.new()
	count_label.text = "Dadi:"
	roll_settings.add_child(count_label)

	dice_count_input = SpinBox.new()
	dice_count_input.min_value = 1
	dice_count_input.max_value = 100
	dice_count_input.step = 1
	dice_count_input.value = 1
	dice_count_input.allow_greater = false
	dice_count_input.allow_lesser = false
	dice_count_input.custom_minimum_size = Vector2(78, 32)
	dice_count_input.tooltip_text = "Numero di dadi da lanciare"
	dice_count_input.value_changed.connect(_on_dice_count_changed)
	roll_settings.add_child(dice_count_input)

	var modifier_label := Label.new()
	modifier_label.text = "Mod:"
	roll_settings.add_child(modifier_label)

	dice_modifier_input = SpinBox.new()
	dice_modifier_input.min_value = -9999
	dice_modifier_input.max_value = 9999
	dice_modifier_input.step = 1
	dice_modifier_input.value = 0
	dice_modifier_input.allow_greater = false
	dice_modifier_input.allow_lesser = false
	dice_modifier_input.custom_minimum_size = Vector2(98, 32)
	dice_modifier_input.tooltip_text = (
		"Modificatore aggiunto una sola volta al totale del tiro"
	)
	roll_settings.add_child(dice_modifier_input)

	var settings_hint := Label.new()
	settings_hint.text = "es. 3d20 + 5"
	settings_hint.modulate = Color(0.55, 0.59, 0.66, 1.0)
	settings_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roll_settings.add_child(settings_hint)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	outer.add_child(mode_row)

	var mode_label := Label.new()
	mode_label.text = "Modalità:"
	mode_row.add_child(mode_label)

	roll_mode_input = OptionButton.new()
	roll_mode_input.add_item("Normale")
	roll_mode_input.set_item_metadata(0, "normal")
	roll_mode_input.add_item("Vantaggio")
	roll_mode_input.set_item_metadata(1, "advantage")
	roll_mode_input.add_item("Svantaggio")
	roll_mode_input.set_item_metadata(2, "disadvantage")
	roll_mode_input.select(0)
	roll_mode_input.tooltip_text = (
		"Con un solo dado, vantaggio/svantaggio tira due volte "
		+ "quel dado e tiene rispettivamente il risultato più alto o più basso."
	)
	mode_row.add_child(roll_mode_input)

	var mode_hint := Label.new()
	mode_hint.text = "Disponibile quando Dadi = 1, per qualsiasi dado."
	mode_hint.modulate = Color(0.55, 0.59, 0.66, 1.0)
	mode_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(mode_hint)

	var dice_grid := GridContainer.new()
	dice_grid.columns = 4
	dice_grid.add_theme_constant_override("h_separation", 5)
	dice_grid.add_theme_constant_override("v_separation", 5)
	outer.add_child(dice_grid)

	var dice_button_group := ButtonGroup.new()
	for die: String in [
		"d20", "d12", "d10", "d8",
		"d6", "d4", "d100", "d%"
	]:
		var button := Button.new()
		button.text = die
		button.toggle_mode = true
		button.button_group = dice_button_group
		button.button_pressed = die == _selected_die
		button.custom_minimum_size = Vector2(82, 34)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = (
			"Seleziona il dado percentuale"
			if die == "d%"
			else "Seleziona %s" % die
		)
		button.pressed.connect(_select_die.bind(die))
		dice_grid.add_child(button)

	roll_button = Button.new()
	roll_button.text = "ROLL %s" % _selected_die
	roll_button.custom_minimum_size = Vector2(0, 36)
	roll_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roll_button.tooltip_text = "Esegui il tiro con il dado selezionato"
	roll_button.pressed.connect(_roll_selected_die)
	outer.add_child(roll_button)

	var chat_row := HBoxContainer.new()
	chat_row.custom_minimum_size = Vector2(0, 42)
	chat_row.add_theme_constant_override("separation", 6)
	outer.add_child(chat_row)

	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Scrivi in chat…"
	chat_input.max_length = 1000
	chat_input.custom_minimum_size = Vector2(0, 42)
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_input.text_submitted.connect(
		func(_value: String) -> void:
			_send_chat()
	)
	chat_row.add_child(chat_input)

	var send := Button.new()
	send.text = "Invia"
	send.pressed.connect(_send_chat)
	chat_row.add_child(send)

	_build_quick_result_popup()


func _build_quick_result_popup() -> void:
	quick_result_panel = PanelContainer.new()
	quick_result_panel.name = "DiceQuickResult"
	quick_result_panel.anchor_left = 0.5
	quick_result_panel.anchor_right = 0.5
	quick_result_panel.offset_left = -175.0
	quick_result_panel.offset_top = 72.0
	quick_result_panel.offset_right = 175.0
	quick_result_panel.offset_bottom = 132.0
	quick_result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quick_result_panel.z_index = 100
	quick_result_panel.hide()

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.028, 0.036, 0.94)
	style.border_color = Color(0.82, 0.62, 0.24, 0.95)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	quick_result_panel.add_theme_stylebox_override("panel", style)

	quick_result_label = Label.new()
	quick_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quick_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quick_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quick_result_label.add_theme_font_size_override("font_size", 18)
	quick_result_panel.add_child(quick_result_label)
	ui_root.add_child(quick_result_panel)


func _select_die(die: String) -> void:
	_selected_die = die
	if roll_button != null:
		roll_button.text = "ROLL %s" % _selected_die


func _roll_selected_die() -> void:
	_roll(_selected_die)


func _on_dice_count_changed(value: float) -> void:
	if roll_mode_input == null:
		return
	var single_die := int(value) == 1
	roll_mode_input.disabled = not single_die
	if not single_die:
		roll_mode_input.select(0)


func _roll(die: String) -> void:
	var count := 1
	var modifier := 0
	if dice_count_input != null:
		count = clampi(int(dice_count_input.value), 1, 100)
	if dice_modifier_input != null:
		modifier = clampi(int(dice_modifier_input.value), -9999, 9999)
	_roll_specific(
		"",
		die,
		count,
		modifier,
		"",
		_selected_action_actor()
	)


func roll_from_sheet(
	label: String,
	die: String,
	count: int = 1,
	modifier: int = 0,
	roll_mode: String = "",
	actor: Node3D = null
) -> void:
	_roll_specific(
		label.strip_edges(),
		die,
		clampi(count, 1, 100),
		clampi(modifier, -9999, 9999),
		roll_mode,
		actor
	)


func _roll_specific(
	label: String,
	die: String,
	count: int,
	modifier: int,
	roll_mode_override: String = "",
	actor: Node3D = null
) -> void:
	if die not in [
		"d20", "d12", "d10", "d8",
		"d6", "d4", "d100", "d%"
	]:
		return

	var event := _new_event("roll")
	var resolved_actor: Node3D = actor
	if resolved_actor == null or not is_instance_valid(resolved_actor):
		resolved_actor = _selected_action_actor()
	_attach_actor_combat_context(event, resolved_actor)
	event["die"] = die
	event["count"] = count
	event["modifier"] = modifier
	if not label.is_empty():
		event["label"] = label.left(160)

	var roll_mode := normalize_roll_mode(roll_mode_override)
	if roll_mode_override.strip_edges().is_empty():
		roll_mode = _selected_roll_mode(count)
	if count != 1:
		roll_mode = "normal"
	event["roll_mode"] = roll_mode

	var rolls: Array[int] = []
	var candidate_rolls: Array = []
	var percentile_faces: Array[Dictionary] = []
	for _index: int in range(count):
		if die == "d%":
			var first_face := _roll_percentile_face()
			if roll_mode != "normal":
				var second_face := _roll_percentile_face()
				var first := int(first_face.get("value", 0))
				var second := int(second_face.get("value", 0))
				var kept := choose_d20_pair(first, second, roll_mode)
				candidate_rolls.append([first, second])
				rolls.append(kept)
				percentile_faces.append(
					first_face
					if kept == first
					else second_face
				)
			else:
				rolls.append(int(first_face.get("value", 0)))
				percentile_faces.append(first_face)
		elif roll_mode != "normal":
			var sides := int(die.trim_prefix("d"))
			var first := rng.randi_range(1, sides)
			var second := rng.randi_range(1, sides)
			candidate_rolls.append([first, second])
			rolls.append(choose_d20_pair(first, second, roll_mode))
		else:
			var sides := int(die.trim_prefix("d"))
			rolls.append(rng.randi_range(1, sides))

	event["rolls"] = rolls
	event["total"] = _roll_total(rolls, modifier)
	if not candidate_rolls.is_empty():
		event["candidate_rolls"] = candidate_rolls
	if die == "d%":
		event["percentile_faces"] = percentile_faces
	event["detail"] = _roll_detail(
		die,
		rolls,
		modifier,
		percentile_faces,
		roll_mode,
		candidate_rolls
	)

	_append_event(event, true)


func roll_expression_from_sheet(
	label: String,
	expression: String,
	actor: Node3D = null
) -> void:
	var parsed := parse_dice_expression(expression)
	if parsed.is_empty():
		return

	var terms_value: Variant = parsed.get("terms", [])
	if not terms_value is Array:
		return
	var terms: Array = terms_value as Array
	var fixed_modifier := int(parsed.get("modifier", 0))
	var rolled_terms: Array[Dictionary] = []
	var total := fixed_modifier
	var total_dice := 0
	for term_value: Variant in terms:
		if term_value is Dictionary:
			total_dice += clampi(
				int((term_value as Dictionary).get("count", 1)),
				1,
				100
			)
	if total_dice <= 0 or total_dice > 100:
		return

	var roll_mode := _selected_roll_mode(total_dice)
	var candidate_rolls: Array = []
	for term_value: Variant in terms:
		if not term_value is Dictionary:
			continue
		var term: Dictionary = term_value as Dictionary
		var count := clampi(int(term.get("count", 1)), 1, 100)
		var sides := int(term.get("sides", 0))
		var term_sign := -1 if int(term.get("sign", 1)) < 0 else 1
		if sides <= 0:
			continue

		var values: Array[int] = []
		for _index: int in range(count):
			var value := 0
			if roll_mode != "normal":
				var first := rng.randi_range(1, sides)
				var second := rng.randi_range(1, sides)
				candidate_rolls.append([first, second])
				value = choose_d20_pair(first, second, roll_mode)
			else:
				value = rng.randi_range(1, sides)
			values.append(value)
			total += term_sign * value
		rolled_terms.append({
			"count": count,
			"sides": sides,
			"sign": term_sign,
			"rolls": values
		})

	if rolled_terms.is_empty():
		return

	var event := _new_event("roll")
	var resolved_actor: Node3D = actor
	if resolved_actor == null or not is_instance_valid(resolved_actor):
		resolved_actor = _selected_action_actor()
	_attach_actor_combat_context(event, resolved_actor)
	event["die"] = "formula"
	event["count"] = total_dice
	event["modifier"] = fixed_modifier
	var notation := String(parsed.get("notation", expression))
	if roll_mode == "advantage":
		notation += " (vant.)"
	elif roll_mode == "disadvantage":
		notation += " (svant.)"
	event["notation"] = notation
	event["terms"] = rolled_terms
	event["total"] = total
	event["roll_mode"] = roll_mode
	if not candidate_rolls.is_empty():
		event["candidate_rolls"] = candidate_rolls
	event["detail"] = _formula_roll_detail(
		rolled_terms,
		fixed_modifier,
		roll_mode,
		candidate_rolls
	)
	if not label.strip_edges().is_empty():
		event["label"] = label.strip_edges().left(160)
	_append_event(event, true)


static func parse_dice_expression(expression: String) -> Dictionary:
	var normalized := expression.to_lower().replace(" ", "")
	normalized = normalized.replace("−", "-")
	if normalized.is_empty() or normalized == "—":
		return {}

	normalized = normalized.replace("-", "+-")
	var terms: Array[Dictionary] = []
	var modifier := 0
	var total_dice := 0
	var notation_parts := PackedStringArray()

	for raw_term: String in normalized.split("+", false):
		var term := raw_term.strip_edges()
		if term.is_empty():
			continue

		var term_sign := 1
		if term.begins_with("-"):
			term_sign = -1
			term = term.substr(1)
		if term.is_empty():
			return {}

		var d_index := term.find("d")
		if d_index >= 0:
			var count_text := term.substr(0, d_index)
			var sides_text := term.substr(d_index + 1)
			var count := 1 if count_text.is_empty() else int(count_text)
			var sides := int(sides_text)
			if count < 1 or sides < 2 or count > 100:
				return {}
			total_dice += count
			if total_dice > 100:
				return {}
			terms.append({
				"count": count,
				"sides": sides,
				"sign": term_sign
			})
			var dice_text := "%dd%d" % [count, sides]
			if notation_parts.is_empty():
				notation_parts.append(
					("-" if term_sign < 0 else "") + dice_text
				)
			else:
				notation_parts.append(
					("%s %s" % [
						"-" if term_sign < 0 else "+",
						dice_text
					])
				)
		else:
			if not term.is_valid_int():
				return {}
			var value := int(term) * term_sign
			modifier += value
			if notation_parts.is_empty():
				notation_parts.append(str(value))
			else:
				notation_parts.append(
					"%s %d" % [
						"-" if value < 0 else "+",
						absi(value)
					]
				)

	if terms.is_empty():
		return {}
	return {
		"terms": terms,
		"modifier": modifier,
		"notation": " ".join(notation_parts)
	}


static func _formula_roll_detail(
	terms: Array[Dictionary],
	modifier: int,
	roll_mode: String = "normal",
	candidate_rolls: Array = []
) -> String:
	var parts := PackedStringArray()
	for term: Dictionary in terms:
		var values_value: Variant = term.get("rolls", [])
		var value_parts := PackedStringArray()
		if values_value is Array:
			for value: Variant in (values_value as Array):
				value_parts.append(str(int(value)))
		var prefix := "-" if int(term.get("sign", 1)) < 0 else ""
		parts.append(
			"%s%dd%d [%s]"
			% [
				prefix,
				int(term.get("count", 1)),
				int(term.get("sides", 0)),
				", ".join(value_parts)
			]
		)
	if modifier > 0:
		parts.append("+%d" % modifier)
	elif modifier < 0:
		parts.append("-%d" % absi(modifier))
	var detail := " · ".join(parts)
	var mode := normalize_roll_mode(roll_mode)
	if mode != "normal" and candidate_rolls.size() == 1:
		var pair_value: Variant = candidate_rolls[0]
		if pair_value is Array and (pair_value as Array).size() == 2:
			var pair := pair_value as Array
			var kept := (
				maxi(int(pair[0]), int(pair[1]))
				if mode == "advantage"
				else mini(int(pair[0]), int(pair[1]))
			)
			var mode_name := (
				"Vantaggio"
				if mode == "advantage"
				else "Svantaggio"
			)
			detail = "%s [%d/%d → %d] · %s" % [
				mode_name,
				int(pair[0]),
				int(pair[1]),
				kept,
				detail
			]
	return detail


static func _roll_total(rolls: Array[int], modifier: int) -> int:
	var total := modifier
	for value: int in rolls:
		total += value
	return total


static func normalize_roll_mode(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if normalized in ["advantage", "disadvantage"]:
		return normalized
	return "normal"


static func choose_d20_pair(first: int, second: int, roll_mode: String) -> int:
	var mode := normalize_roll_mode(roll_mode)
	if mode == "advantage":
		return maxi(first, second)
	if mode == "disadvantage":
		return mini(first, second)
	return first


func _selected_roll_mode(count: int) -> String:
	if count != 1 or roll_mode_input == null:
		return "normal"
	var selected := roll_mode_input.get_selected_id()
	if selected < 0:
		return "normal"
	return normalize_roll_mode(
		String(roll_mode_input.get_item_metadata(selected))
	)


static func _roll_notation(
	die: String,
	count: int,
	modifier: int,
	roll_mode: String = "normal"
) -> String:
	var notation := "%d%s" % [maxi(1, count), die]
	var mode := normalize_roll_mode(roll_mode)
	if count == 1 and mode == "advantage":
		notation += " (vant.)"
	elif count == 1 and mode == "disadvantage":
		notation += " (svant.)"
	if modifier > 0:
		notation += " + %d" % modifier
	elif modifier < 0:
		notation += " - %d" % absi(modifier)
	return notation


static func _roll_detail(
	die: String,
	rolls: Array[int],
	modifier: int,
	percentile_faces: Array[Dictionary] = [],
	roll_mode: String = "normal",
	candidate_rolls: Array = []
) -> String:
	var result_parts := PackedStringArray()
	for value: int in rolls:
		result_parts.append(str(value))

	var mode := normalize_roll_mode(roll_mode)
	var detail := "[%s]" % ", ".join(result_parts)
	if mode != "normal" and not candidate_rolls.is_empty():
		var pair_parts := PackedStringArray()
		for index: int in range(candidate_rolls.size()):
			var pair_value: Variant = candidate_rolls[index]
			if not pair_value is Array or (pair_value as Array).size() != 2:
				continue
			var pair: Array = pair_value as Array
			var kept := int(rolls[index]) if index < rolls.size() else 0
			pair_parts.append(
				"%d/%d → %d" % [int(pair[0]), int(pair[1]), kept]
			)
		var mode_name := "Vantaggio" if mode == "advantage" else "Svantaggio"
		detail = "%s [%s]" % [mode_name, ", ".join(pair_parts)]
	if die == "d%" and not percentile_faces.is_empty():
		var face_parts := PackedStringArray()
		for face: Dictionary in percentile_faces:
			face_parts.append(
				"%02d+%d=%d"
				% [
					int(face.get("tens", 0)),
					int(face.get("ones", 0)),
					int(face.get("value", 0))
				]
			)
		detail += " · %s" % ", ".join(face_parts)

	if modifier > 0:
		detail += " · +%d" % modifier
	elif modifier < 0:
		detail += " · -%d" % absi(modifier)
	return detail


func _roll_percentile_face() -> Dictionary:
	var tens_face := rng.randi_range(0, 9) * 10
	var ones_face := rng.randi_range(0, 9)
	return {
		"tens": tens_face,
		"ones": ones_face,
		"value": percentile_total(tens_face, ones_face)
	}


static func percentile_total(tens_face: int, ones_face: int) -> int:
	var tens := clampi(tens_face, 0, 90)
	tens -= tens % 10
	var ones := clampi(ones_face, 0, 9)
	var total := tens + ones
	return 100 if total == 0 else total


func _prompt_initial_identity_after_scene_ready() -> void:
	# Il salvataggio della campagna viene applicato in deferred: attendere due
	# frame fa sì che il primo popup veda davvero tutti i token caricati.
	await get_tree().process_frame
	await get_tree().process_frame
	ensure_scene_identity()


func _build_scene_identity_dialog() -> void:
	scene_identity_dialog = ConfirmationDialog.new()
	scene_identity_dialog.name = "SceneChatIdentityDialog"
	scene_identity_dialog.title = "Identità in questa scena"
	scene_identity_dialog.ok_button_text = "Conferma"
	scene_identity_dialog.cancel_button_text = "Annulla"
	scene_identity_dialog.dialog_hide_on_ok = false
	scene_identity_dialog.min_size = Vector2i(600, 560)
	scene_identity_dialog.add_theme_constant_override("buttons_min_width", 110)
	scene_identity_dialog.add_theme_constant_override("buttons_min_height", 36)
	ui_root.add_child(scene_identity_dialog)
	# Su alcuni scaling il footer nativo del ConfirmationDialog finisce fuori
	# dal rettangolo visibile. Le azioni reali vivono quindi nel contenuto.
	scene_identity_dialog.get_ok_button().hide()
	var native_cancel := scene_identity_dialog.get_cancel_button()
	if native_cancel != null:
		native_cancel.hide()

	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(540, 430)
	body.add_theme_constant_override("separation", 10)
	scene_identity_dialog.add_child(body)

	var info := Label.new()
	info.text = (
		"Seleziona un token già in gioco, Nessuno, oppure scegli una "
		+ "miniatura da generare. Se scegli Nessuno apparirai in chat come "
		+ "master (nome dispositivo)."
	)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(info)

	var identity_label := Label.new()
	identity_label.text = "Token associato all'utente"
	body.add_child(identity_label)

	scene_identity_selector = OptionButton.new()
	scene_identity_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_identity_selector.item_selected.connect(
		_on_scene_identity_mode_selected
	)
	body.add_child(scene_identity_selector)

	# Footer esplicito immediatamente sotto la scelta: resta visibile anche
	# quando il popup viene clamped/scalato e non dipende dal footer nativo.
	var actions := HBoxContainer.new()
	actions.name = "SceneIdentityActions"
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	body.add_child(actions)

	var cancel_button := Button.new()
	cancel_button.name = "SceneIdentityCancel"
	cancel_button.text = "Annulla"
	cancel_button.custom_minimum_size = Vector2(120, 40)
	cancel_button.pressed.connect(
		func() -> void:
			scene_identity_dialog.hide()
			_cancel_scene_identity_dialog()
	)
	actions.add_child(cancel_button)

	var confirm_button := Button.new()
	confirm_button.name = "SceneIdentityConfirm"
	confirm_button.text = "Conferma"
	confirm_button.custom_minimum_size = Vector2(140, 40)
	confirm_button.pressed.connect(_confirm_scene_identity)
	actions.add_child(confirm_button)

	scene_identity_miniature_section = VBoxContainer.new()
	scene_identity_miniature_section.add_theme_constant_override(
		"separation",
		6
	)
	body.add_child(scene_identity_miniature_section)

	var miniature_label := Label.new()
	miniature_label.text = "Miniatura da generare"
	scene_identity_miniature_section.add_child(miniature_label)

	scene_identity_miniature_search = LineEdit.new()
	scene_identity_miniature_search.placeholder_text = "Cerca miniatura…"
	scene_identity_miniature_search.clear_button_enabled = true
	scene_identity_miniature_search.text_changed.connect(
		_refresh_scene_identity_miniature_list
	)
	scene_identity_miniature_section.add_child(
		scene_identity_miniature_search
	)

	scene_identity_miniature_list = ItemList.new()
	scene_identity_miniature_list.custom_minimum_size = Vector2(520, 250)
	scene_identity_miniature_list.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	scene_identity_miniature_section.add_child(
		scene_identity_miniature_list
	)

	var miniature_hint := Label.new()
	miniature_hint.text = (
		"Le miniature remote vengono scaricate solo dopo Conferma. "
		+ "Se ne scegli una, il passo successivo obbligatorio è piazzarla "
		+ "sulla mappa."
	)
	miniature_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scene_identity_miniature_section.add_child(miniature_hint)

	scene_identity_dialog.confirmed.connect(_confirm_scene_identity)
	scene_identity_dialog.canceled.connect(_cancel_scene_identity_dialog)
	scene_identity_dialog.close_requested.connect(
		_cancel_scene_identity_dialog
	)


func ensure_scene_identity(on_ready: Callable = Callable()) -> bool:
	if _scene_identity_configured:
		return true
	if _identity_placement_pending:
		return false
	if on_ready.is_valid():
		_pending_identity_callback = on_ready
	_show_scene_identity_dialog()
	return false


func request_change_scene_identity() -> void:
	if _identity_placement_pending:
		return
	_identity_change_mode = true
	_show_scene_identity_dialog()


func _show_scene_identity_dialog() -> void:
	if scene_identity_dialog == null:
		return
	_refresh_scene_identity_options()
	if board_root.has_method("release_camera_control"):
		board_root.call("release_camera_control")
	elif board_root.has_method("_release_mouse"):
		board_root.call("_release_mouse")
	scene_identity_dialog.reset_size()
	scene_identity_dialog.popup_centered_clamped(
		Vector2i(620, 620),
		0.92
	)
	if scene_identity_selector != null:
		scene_identity_selector.call_deferred("grab_focus")


func _refresh_scene_identity_options() -> void:
	if scene_identity_selector == null:
		return
	scene_identity_selector.clear()
	scene_identity_selector.add_item(
		"Nessuno — %s" % _master_author_name()
	)
	scene_identity_selector.set_item_metadata(
		0,
		{"kind": "master", "id": ""}
	)

	var selected_index := 0
	for token: Node3D in _scene_identity_tokens():
		var display_name := _actor_display_name(token)
		if display_name.is_empty():
			display_name = String(token.name)
		var item_index := scene_identity_selector.item_count
		var token_id := _token_stable_id(token)
		scene_identity_selector.add_item(display_name)
		scene_identity_selector.set_item_metadata(
			item_index,
			{"kind": "token", "id": token_id}
		)
		if (
			not _selected_identity_token_id.is_empty()
			and token_id == _selected_identity_token_id
		):
			selected_index = item_index

	scene_identity_selector.add_separator()
	var generate_index := scene_identity_selector.item_count
	scene_identity_selector.add_item("Genera una nuova miniatura…")
	scene_identity_selector.set_item_metadata(
		generate_index,
		{"kind": "generate", "id": ""}
	)
	scene_identity_selector.select(selected_index)

	_identity_profile_choices.clear()
	if (
		board_root != null
		and is_instance_valid(board_root)
		and board_root.has_method("get_token_identity_profiles")
	):
		var profiles_value: Variant = board_root.call(
			"get_token_identity_profiles"
		)
		if profiles_value is Array:
			for value: Variant in profiles_value as Array:
				if value is Dictionary:
					_identity_profile_choices.append(
						(value as Dictionary).duplicate(true)
					)

	_refresh_scene_identity_miniature_list(
		scene_identity_miniature_search.text
		if scene_identity_miniature_search != null
		else ""
	)
	_on_scene_identity_mode_selected(selected_index)


func refresh_scene_identity_profiles() -> void:
	if scene_identity_dialog == null or not scene_identity_dialog.visible:
		return
	var selected_metadata: Variant = (
		scene_identity_selector.get_item_metadata(
			scene_identity_selector.selected
		)
		if scene_identity_selector.selected >= 0
		else {}
	)
	var keep_generate := (
		selected_metadata is Dictionary
		and String((selected_metadata as Dictionary).get("kind", ""))
		== "generate"
	)
	_refresh_scene_identity_options()
	if keep_generate:
		for index: int in range(scene_identity_selector.item_count):
			var metadata: Variant = (
				scene_identity_selector.get_item_metadata(index)
			)
			if (
				metadata is Dictionary
				and String((metadata as Dictionary).get("kind", ""))
				== "generate"
			):
				scene_identity_selector.select(index)
				_on_scene_identity_mode_selected(index)
				break


func _on_scene_identity_mode_selected(index: int) -> void:
	if scene_identity_miniature_section == null:
		return
	var metadata: Variant = scene_identity_selector.get_item_metadata(index)
	var kind := (
		String((metadata as Dictionary).get("kind", ""))
		if metadata is Dictionary
		else ""
	)
	scene_identity_miniature_section.visible = kind == "generate"


func _refresh_scene_identity_miniature_list(query: String) -> void:
	if scene_identity_miniature_list == null:
		return
	var previous_id := ""
	var selected := scene_identity_miniature_list.get_selected_items()
	if not selected.is_empty():
		previous_id = String(
			scene_identity_miniature_list.get_item_metadata(
				int(selected[0])
			)
		)
	scene_identity_miniature_list.clear()
	var normalized := query.strip_edges().to_lower()
	var target_index := -1
	for profile: Dictionary in _identity_profile_choices:
		var profile_id := String(profile.get("id", "")).strip_edges()
		var name := String(profile.get("name", profile_id))
		var size_name := String(profile.get("size_name", "Medium"))
		var status := String(profile.get("status", ""))
		var searchable := (
			name + " " + profile_id + " " + size_name + " " + status
		).to_lower()
		if not normalized.is_empty() and not searchable.contains(normalized):
			continue
		var index := scene_identity_miniature_list.item_count
		scene_identity_miniature_list.add_item(
			"%s · %s · %s" % [name, size_name, status]
		)
		scene_identity_miniature_list.set_item_metadata(index, profile_id)
		if profile_id == previous_id:
			target_index = index
	if target_index < 0 and scene_identity_miniature_list.item_count > 0:
		target_index = 0
	if target_index >= 0:
		scene_identity_miniature_list.select(target_index)


func _confirm_scene_identity() -> void:
	if (
		scene_identity_selector == null
		or scene_identity_selector.selected < 0
	):
		return
	var metadata: Variant = scene_identity_selector.get_item_metadata(
		scene_identity_selector.selected
	)
	if not metadata is Dictionary:
		return
	var choice := metadata as Dictionary
	var kind := String(choice.get("kind", ""))

	if kind == "generate":
		if scene_identity_miniature_list == null:
			return
		var selected := scene_identity_miniature_list.get_selected_items()
		if selected.is_empty():
			return
		var profile_id := String(
			scene_identity_miniature_list.get_item_metadata(
				int(selected[0])
			)
		).strip_edges()
		if profile_id.is_empty():
			return
		if (
			board_root == null
			or not is_instance_valid(board_root)
			or not board_root.has_method(
				"begin_identity_token_placement"
			)
		):
			return
		_identity_placement_pending = true
		_identity_change_mode = false
		scene_identity_dialog.hide()
		var started := bool(
			board_root.call(
				"begin_identity_token_placement",
				profile_id,
				Callable(self, "_on_identity_token_placed"),
				Callable(
					self,
					"_on_identity_token_placement_failed"
				)
			)
		)
		if not started:
			_identity_placement_pending = false
			_show_scene_identity_dialog()
		return

	_selected_identity_token_id = (
		String(choice.get("id", "")).strip_edges()
		if kind == "token"
		else ""
	)
	_scene_identity_configured = true
	_identity_change_mode = false
	_save_scene_identity()
	scene_identity_dialog.hide()
	_resume_after_identity_choice()


func _on_identity_token_placed(token: CharacterBody3D) -> void:
	_identity_placement_pending = false
	if token == null or not is_instance_valid(token):
		_show_scene_identity_dialog()
		return
	_selected_identity_token_id = _token_stable_id(token)
	_scene_identity_configured = true
	_save_scene_identity()
	_resume_after_identity_choice()


func _on_identity_token_placement_failed() -> void:
	_identity_placement_pending = false
	_show_scene_identity_dialog()


func _cancel_scene_identity_dialog() -> void:
	_identity_change_mode = false
	_pending_identity_callback = Callable()
	if board_root.has_method("capture_camera_control"):
		board_root.call("capture_camera_control")
	elif board_root.has_method("_capture_mouse"):
		board_root.call("_capture_mouse")


func _scene_identity_tokens() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if board_root == null or not is_instance_valid(board_root):
		return result
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			node is Node3D
			and is_instance_valid(node)
			and board_root.is_ancestor_of(node)
			and not node.is_queued_for_deletion()
		):
			result.append(node as Node3D)
	result.sort_custom(
		func(a: Node3D, b: Node3D) -> bool:
			return _actor_display_name(a).naturalnocasecmp_to(
				_actor_display_name(b)
			) < 0
	)
	return result


func _resume_after_identity_choice() -> void:
	var callback := _pending_identity_callback
	_pending_identity_callback = Callable()
	if callback.is_valid():
		callback.call_deferred()
	elif board_root.has_method("capture_camera_control"):
		board_root.call("capture_camera_control")


func _scene_identity_section() -> String:
	var scene_path := ""
	if board_root != null and is_instance_valid(board_root):
		scene_path = String(board_root.scene_file_path).strip_edges()
		if scene_path.is_empty():
			scene_path = String(board_root.name)
	if scene_path.is_empty():
		scene_path = "unknown_scene"
	return "scene_%s" % scene_path.md5_text()


func _load_scene_identity() -> void:
	_selected_identity_token_id = ""
	_scene_identity_configured = false
	var config := ConfigFile.new()
	if config.load(PROFILE_PATH) != OK:
		return
	var section := _scene_identity_section()
	_scene_identity_configured = bool(
		config.get_value(section, "configured", false)
	)
	_selected_identity_token_id = String(
		config.get_value(section, "token_id", "")
	).strip_edges()


func _save_scene_identity() -> void:
	var config := ConfigFile.new()
	config.load(PROFILE_PATH)
	var section := _scene_identity_section()
	config.set_value(section, "configured", true)
	config.set_value(
		section,
		"token_id",
		_selected_identity_token_id
	)
	if board_root != null and is_instance_valid(board_root):
		config.set_value(
			section,
			"scene_path",
			String(board_root.scene_file_path)
		)
	config.save(PROFILE_PATH)


func _token_stable_id(token: Node3D) -> String:
	if token == null or not is_instance_valid(token):
		return ""
	if token.has_method("get_token_id"):
		var token_id := String(token.call("get_token_id")).strip_edges()
		if not token_id.is_empty():
			return token_id
	if token.has_meta("sync_id"):
		var sync_id := String(token.get_meta("sync_id")).strip_edges()
		if not sync_id.is_empty():
			return sync_id
	if board_root != null and is_instance_valid(board_root):
		var sync_value: Variant = board_root.get("board_sync")
		if sync_value is Node:
			var board_sync := sync_value as Node
			if (
				board_sync != null
				and is_instance_valid(board_sync)
				and board_sync.has_method("get_sync_id_for_node")
			):
				return String(
					board_sync.call("get_sync_id_for_node", token)
				).strip_edges()
		return "path:" + String(board_root.get_path_to(token))
	return ""


func _identity_token() -> Node3D:
	if _selected_identity_token_id.is_empty():
		return null
	for token: Node3D in _scene_identity_tokens():
		if _token_stable_id(token) == _selected_identity_token_id:
			return token
	return null


func _device_name() -> String:
	for key: String in ["COMPUTERNAME", "HOSTNAME"]:
		var value := OS.get_environment(key).strip_edges()
		if not value.is_empty():
			return value.left(40)
	return "dispositivo"


func _master_author_name() -> String:
	return "master (%s)" % _device_name()


func _send_chat() -> void:
	if chat_input == null:
		return
	var message := chat_input.text.strip_edges()
	if message.is_empty():
		return

	var event := _new_event("chat")
	event["text"] = message
	chat_input.clear()
	_append_event(event, true)


func log_action(
	text: String,
	actor: Node3D = null,
	round_override: int = 0
) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return

	var event := _new_event("action")
	event["text"] = clean_text.left(1000)
	_attach_actor_combat_context(event, actor)
	if round_override > 0:
		event["round"] = round_override
	_append_event(event, true)


func _selected_action_actor() -> Node3D:
	if board_root == null or not is_instance_valid(board_root):
		return null
	var selected_value: Variant = board_root.get("_selected_tokens")
	if not selected_value is Array:
		return null
	var selected: Array = selected_value as Array
	if selected.size() != 1 or not selected[0] is Node3D:
		return null
	var actor := selected[0] as Node3D
	if (
		actor == null
		or not is_instance_valid(actor)
		or not actor.is_in_group("dnd_token")
	):
		return null
	return actor


func _attach_actor_combat_context(
	event: Dictionary,
	actor: Node3D
) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var actor_name := _actor_display_name(actor)
	if not actor_name.is_empty():
		event["actor"] = actor_name.left(120)
	var combat_round := _combat_round_for_actor(actor)
	if combat_round > 0:
		event["round"] = combat_round


func _combat_round_for_actor(actor: Node3D) -> int:
	if (
		actor == null
		or not is_instance_valid(actor)
		or board_root == null
		or not is_instance_valid(board_root)
	):
		return 0
	var tracker_value: Variant = board_root.get("initiative_tracker")
	if not tracker_value is Node:
		return 0
	var tracker := tracker_value as Node
	if (
		tracker == null
		or not is_instance_valid(tracker)
		or not tracker.has_method("combat_round_for_token")
	):
		return 0
	return maxi(
		0,
		int(tracker.call("combat_round_for_token", actor))
	)


func _actor_display_name(actor: Node3D) -> String:
	if actor == null or not is_instance_valid(actor):
		return ""
	if actor.has_method("get_display_name"):
		var display_name := String(actor.call("get_display_name")).strip_edges()
		if not display_name.is_empty():
			return display_name
	if actor.has_meta("player_character_name"):
		var character_name := String(
			actor.get_meta("player_character_name")
		).strip_edges()
		if not character_name.is_empty():
			return character_name
	return String(actor.name).strip_edges()


func _new_event(kind: String) -> Dictionary:
	var stamp := int(Time.get_unix_time_from_system())
	var unique := "%d_%d_%d" % [
		Time.get_ticks_usec(),
		rng.randi(),
		get_instance_id()
	]
	return {
		"id": "%s_%s" % [_author_id(), unique],
		"kind": kind,
		"author": _author_name(),
		"timestamp": stamp
	}


func _append_event(event: Dictionary, broadcast: bool) -> void:
	var event_id := String(event.get("id", "")).strip_edges()
	if event_id.is_empty() or seen_ids.has(event_id):
		return

	seen_ids[event_id] = true
	history.append(event.duplicate(true))
	while history.size() > MAX_HISTORY:
		var removed: Dictionary = history.pop_front()
		seen_ids.erase(String(removed.get("id", "")))

	_save_history()
	_render_history()
	if String(event.get("kind", "")) == "roll":
		_show_quick_roll_result(event)

	if broadcast and sync != null:
		sync.call(
			"broadcast_event",
			event,
			session_key
		)


func _show_quick_roll_result(event: Dictionary) -> void:
	if quick_result_panel == null or quick_result_label == null:
		return

	_quick_result_generation += 1
	var generation := _quick_result_generation
	var total := int(event.get("total", 0))
	var label := String(event.get("label", "")).strip_edges()
	var mode := normalize_roll_mode(String(event.get("roll_mode", "normal")))
	var mode_text := ""
	if mode == "advantage":
		mode_text = "VANTAGGIO · "
	elif mode == "disadvantage":
		mode_text = "SVANTAGGIO · "

	quick_result_label.text = (
		("%s\n" % label if not label.is_empty() else "")
		+ "%s%d" % [mode_text, total]
	)
	quick_result_panel.show()

	var timer := get_tree().create_timer(2.2)
	timer.timeout.connect(_hide_quick_roll_result.bind(generation))


func _hide_quick_roll_result(generation: int) -> void:
	if generation == _quick_result_generation and quick_result_panel != null:
		quick_result_panel.hide()


func _on_remote_event(event: Dictionary) -> void:
	_append_event(event, false)


func _on_sync_status(message: String) -> void:
	if status_label != null:
		status_label.text = message


func _render_history() -> void:
	if history_view == null:
		return

	var lines := PackedStringArray()
	for event: Dictionary in history:
		var author := _escape_bb(
			String(event.get("author", "Giocatore"))
		)
		var kind := String(event.get("kind", ""))
		var event_round := int(event.get("round", 0))
		var round_prefix := ""
		if event_round > 0:
			round_prefix = (
				"[color=#72849a][b]R%d[/b][/color] · "
				% event_round
			)

		if kind == "roll":
			var die_raw := String(event.get("die", "d?"))
			var count := maxi(1, int(event.get("count", 1)))
			var modifier := int(event.get("modifier", 0))
			var raw_notation := (
				String(event.get("notation", ""))
				if die_raw == "formula"
				else _roll_notation(
					die_raw,
					count,
					modifier,
					String(event.get("roll_mode", "normal"))
				)
			)
			var notation := _escape_bb(raw_notation)
			var total := int(event.get("total", 0))
			var detail := String(event.get("detail", "")).strip_edges()
			var label := String(event.get("label", "")).strip_edges()
			var roll_text := round_prefix + (
				"[color=#d5a64a][b]%s[/b][/color]  "
				+ "[color=#8fa8c6]%s[/color] → "
				+ "[font_size=18][b]%d[/b][/font_size]"
			) % [author, notation, total]
			if not label.is_empty():
				roll_text += (
					"\n[color=#9ca8b8]%s[/color]"
					% _escape_bb(label)
				)
			if not detail.is_empty():
				roll_text += (
					"  [color=#78818e](%s)[/color]"
					% _escape_bb(detail)
				)
			lines.append(roll_text)
		elif kind == "chat":
			lines.append(
				round_prefix
				+ "[color=#d5a64a][b]%s[/b][/color]: %s"
				% [
					author,
					_escape_bb(String(event.get("text", "")))
				]
			)
		elif kind == "action":
			var action_text := _escape_bb(
				String(event.get("text", ""))
			)
			var actor_name := _escape_bb(
				String(event.get("actor", "")).strip_edges()
			)
			var action_body := action_text
			if not actor_name.is_empty():
				action_body = "[b]%s[/b] %s" % [
					actor_name,
					action_text
				]
			lines.append(
				round_prefix
				+ "[color=#d5a64a][b]%s[/b][/color] · %s"
				% [author, action_body]
			)

	history_view.text = "\n\n".join(lines)
	history_view.call_deferred(
		"scroll_to_line",
		maxi(0, history_view.get_line_count() - 1)
	)

	if not history.is_empty():
		var last: Dictionary = history.back()
		if String(last.get("kind", "")) == "roll":
			toggle_button.text = str(int(last.get("total", 0)))
			var last_die := String(last.get("die", ""))
			var last_notation := (
				String(last.get("notation", ""))
				if last_die == "formula"
				else _roll_notation(
					last_die,
					maxi(1, int(last.get("count", 1))),
					int(last.get("modifier", 0)),
					String(last.get("roll_mode", "normal"))
				)
			)
			toggle_button.tooltip_text = (
				"Ultimo tiro: %s = %d"
				% [
					last_notation,
					int(last.get("total", 0))
				]
			)
		else:
			toggle_button.text = "CHAT"
	else:
		toggle_button.text = "d20"
		toggle_button.tooltip_text = "Dice roller e chat"


func _history_path() -> String:
	var safe_key := ""
	for character: String in session_key:
		if character.is_valid_int() or character in ["_", "-"]:
			safe_key += character
		else:
			safe_key += "_"
	if safe_key.is_empty():
		safe_key = "1"
	return HISTORY_DIR.path_join("session_%s.json" % safe_key)


func _load_history() -> void:
	history.clear()
	seen_ids.clear()

	var path := _history_path()
	if not FileAccess.file_exists(path):
		_render_history()
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Array:
		return

	for value: Variant in (parsed as Array):
		if not value is Dictionary:
			continue
		var event: Dictionary = value as Dictionary
		if not DiceChatSync.valid_event(event):
			continue
		var event_id := String(event.get("id", ""))
		if event_id.is_empty() or seen_ids.has(event_id):
			continue
		seen_ids[event_id] = true
		history.append(event.duplicate(true))

	while history.size() > MAX_HISTORY:
		var removed: Dictionary = history.pop_front()
		seen_ids.erase(String(removed.get("id", "")))


func _save_history() -> void:
	if session_key.is_empty():
		return
	var file := FileAccess.open(_history_path(), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(history, "  "))
	file.close()


func _author_name() -> String:
	var identity_token := _identity_token()
	if identity_token != null:
		var token_name := _actor_display_name(identity_token)
		if not token_name.is_empty():
			return token_name.left(80)
	return _master_author_name()


func _author_id() -> String:
	var source := _author_name().to_lower()
	var out := ""
	for character: String in source:
		if character.is_valid_identifier() or character.is_valid_int():
			out += character
		elif character in ["-", "_"]:
			out += character
		else:
			out += "_"
	return out if not out.is_empty() else "player"


func _escape_bb(value: String) -> String:
	return value.replace("[", "［").replace("]", "］")


func _exit_tree() -> void:
	_save_history()
