extends Node

const DiceChatSync = preload("res://network/dice_chat_sync.gd")
const HISTORY_DIR := "user://dice_chat"
const MAX_HISTORY := 300

var board_root: Node3D
var ui_root: CanvasLayer
var sync: Node
var session_key := "1"
var history: Array[Dictionary] = []
var seen_ids: Dictionary = {}
var rng := RandomNumberGenerator.new()

var toggle_button: Button
var panel: PanelContainer
var history_view: RichTextLabel
var chat_input: LineEdit
var status_label: Label
var dice_count_input: SpinBox
var dice_modifier_input: SpinBox


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

	sync = DiceChatSync.new()
	sync.name = "DiceChatSync"
	add_child(sync)
	sync.call("setup", tailscale_peer_provider)
	sync.event_received.connect(_on_remote_event)
	sync.status_changed.connect(_on_sync_status)

	_build_ui()
	set_session_key(initial_session_key)


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
	panel.visible = not panel.visible
	if panel.visible:
		if board_root.has_method("release_camera_control"):
			board_root.call("release_camera_control")
		elif board_root.has_method("_release_mouse"):
			board_root.call("_release_mouse")
		chat_input.call_deferred("grab_focus")
	else:
		if board_root.has_method("capture_camera_control"):
			board_root.call("capture_camera_control")
		elif board_root.has_method("_capture_mouse"):
			board_root.call("_capture_mouse")


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
	panel.offset_top = -520.0
	panel.offset_right = -12.0
	panel.offset_bottom = -82.0
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

	var collapse := Button.new()
	collapse.text = "—"
	collapse.tooltip_text = "Chiudi"
	collapse.pressed.connect(toggle_panel)
	header.add_child(collapse)

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

	var dice_grid := GridContainer.new()
	dice_grid.columns = 4
	dice_grid.add_theme_constant_override("h_separation", 5)
	dice_grid.add_theme_constant_override("v_separation", 5)
	outer.add_child(dice_grid)

	for die: String in [
		"d20", "d12", "d10", "d8",
		"d6", "d4", "d100", "d%"
	]:
		var button := Button.new()
		button.text = die
		button.custom_minimum_size = Vector2(82, 34)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = (
			"Dado percentuale (d100 + d10)"
			if die == "d%"
			else "Lancia %s" % die
		)
		button.pressed.connect(_roll.bind(die))
		dice_grid.add_child(button)

	var chat_row := HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 6)
	outer.add_child(chat_row)

	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Scrivi in chat…"
	chat_input.max_length = 1000
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


func _roll(die: String) -> void:
	var count := 1
	var modifier := 0
	if dice_count_input != null:
		count = clampi(int(dice_count_input.value), 1, 100)
	if dice_modifier_input != null:
		modifier = clampi(int(dice_modifier_input.value), -9999, 9999)
	_roll_specific("", die, count, modifier)


func roll_from_sheet(
	label: String,
	die: String,
	count: int = 1,
	modifier: int = 0
) -> void:
	_roll_specific(
		label.strip_edges(),
		die,
		clampi(count, 1, 100),
		clampi(modifier, -9999, 9999)
	)


func _roll_specific(
	label: String,
	die: String,
	count: int,
	modifier: int
) -> void:
	if die not in [
		"d20", "d12", "d10", "d8",
		"d6", "d4", "d100", "d%"
	]:
		return

	var event := _new_event("roll")
	event["die"] = die
	event["count"] = count
	event["modifier"] = modifier
	if not label.is_empty():
		event["label"] = label.left(160)

	var rolls: Array[int] = []
	var percentile_faces: Array[Dictionary] = []
	for _index: int in range(count):
		if die == "d%":
			var tens_face := rng.randi_range(0, 9) * 10
			var ones_face := rng.randi_range(0, 9)
			var value := percentile_total(tens_face, ones_face)
			rolls.append(value)
			percentile_faces.append({
				"tens": tens_face,
				"ones": ones_face,
				"value": value
			})
		else:
			var sides := int(die.trim_prefix("d"))
			rolls.append(rng.randi_range(1, sides))

	event["rolls"] = rolls
	event["total"] = _roll_total(rolls, modifier)
	if die == "d%":
		event["percentile_faces"] = percentile_faces
	event["detail"] = _roll_detail(
		die,
		rolls,
		modifier,
		percentile_faces
	)

	_append_event(event, true)


func roll_expression_from_sheet(
	label: String,
	expression: String
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
		if not term_value is Dictionary:
			continue
		var term: Dictionary = term_value as Dictionary
		var count := clampi(int(term.get("count", 1)), 1, 100)
		var sides := int(term.get("sides", 0))
		var sign := -1 if int(term.get("sign", 1)) < 0 else 1
		if sides <= 0:
			continue

		var values: Array[int] = []
		for _index: int in range(count):
			var value := rng.randi_range(1, sides)
			values.append(value)
			total += sign * value
		total_dice += 1
		rolled_terms.append({
			"count": count,
			"sides": sides,
			"sign": sign,
			"rolls": values
		})

	if rolled_terms.is_empty() or total_dice > 100:
		return

	var event := _new_event("roll")
	event["die"] = "formula"
	event["count"] = total_dice
	event["modifier"] = fixed_modifier
	event["notation"] = String(parsed.get("notation", expression))
	event["terms"] = rolled_terms
	event["total"] = total
	event["detail"] = _formula_roll_detail(
		rolled_terms,
		fixed_modifier
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

		var sign := 1
		if term.begins_with("-"):
			sign = -1
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
				"sign": sign
			})
			var dice_text := "%dd%d" % [count, sides]
			if notation_parts.is_empty():
				notation_parts.append(
					("-" if sign < 0 else "") + dice_text
				)
			else:
				notation_parts.append(
					("%s %s" % [
						"-" if sign < 0 else "+",
						dice_text
					])
				)
		else:
			if not term.is_valid_int():
				return {}
			var value := int(term) * sign
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
	modifier: int
) -> String:
	var parts := PackedStringArray()
	for term: Dictionary in terms:
		var values_value: Variant = term.get("rolls", [])
		var value_parts := PackedStringArray()
		if values_value is Array:
			for value: Variant in values_value as Array:
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
	return " · ".join(parts)


static func _roll_total(rolls: Array[int], modifier: int) -> int:
	var total := modifier
	for value: int in rolls:
		total += value
	return total


static func _roll_notation(
	die: String,
	count: int,
	modifier: int
) -> String:
	var notation := "%d%s" % [maxi(1, count), die]
	if modifier > 0:
		notation += " + %d" % modifier
	elif modifier < 0:
		notation += " - %d" % absi(modifier)
	return notation


static func _roll_detail(
	die: String,
	rolls: Array[int],
	modifier: int,
	percentile_faces: Array[Dictionary] = []
) -> String:
	var result_parts := PackedStringArray()
	for value: int in rolls:
		result_parts.append(str(value))

	var detail := "[%s]" % ", ".join(result_parts)
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


static func percentile_total(tens_face: int, ones_face: int) -> int:
	var tens := clampi(tens_face, 0, 90)
	tens -= tens % 10
	var ones := clampi(ones_face, 0, 9)
	var total := tens + ones
	return 100 if total == 0 else total


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

	if broadcast and sync != null:
		sync.call(
			"broadcast_event",
			event,
			session_key
		)


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

		if kind == "roll":
			var die_raw := String(event.get("die", "d?"))
			var count := maxi(1, int(event.get("count", 1)))
			var modifier := int(event.get("modifier", 0))
			var raw_notation := (
				String(event.get("notation", ""))
				if die_raw == "formula"
				else _roll_notation(die_raw, count, modifier)
			)
			var notation := _escape_bb(raw_notation)
			var total := int(event.get("total", 0))
			var detail := String(event.get("detail", "")).strip_edges()
			var label := String(event.get("label", "")).strip_edges()
			var roll_text := (
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
				"[color=#d5a64a][b]%s[/b][/color]: %s"
				% [
					author,
					_escape_bb(String(event.get("text", "")))
				]
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
					int(last.get("modifier", 0))
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
	for key: String in ["COMPUTERNAME", "HOSTNAME", "USERNAME", "USER"]:
		var value := OS.get_environment(key).strip_edges()
		if not value.is_empty():
			return value.left(40)
	return "Giocatore"


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
