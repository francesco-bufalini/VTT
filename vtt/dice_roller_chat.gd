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
	var event := _new_event("roll")
	event["die"] = die

	if die == "d%":
		var tens_face := rng.randi_range(0, 9) * 10
		var ones_face := rng.randi_range(0, 9)
		var total := percentile_total(tens_face, ones_face)
		event["total"] = total
		event["tens"] = tens_face
		event["ones"] = ones_face
		event["detail"] = "%02d + %d" % [tens_face, ones_face]
	else:
		var sides := int(die.trim_prefix("d"))
		event["total"] = rng.randi_range(1, sides)
		event["detail"] = ""

	_append_event(event, true)


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
			var die := _escape_bb(String(event.get("die", "d?")))
			var total := int(event.get("total", 0))
			var detail := String(event.get("detail", "")).strip_edges()
			var roll_text := (
				"[color=#d5a64a][b]%s[/b][/color]  "
				+ "[color=#8fa8c6]%s[/color] → "
				+ "[font_size=18][b]%d[/b][/font_size]"
			) % [author, die, total]
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
			toggle_button.tooltip_text = (
				"Ultimo tiro: %s = %d"
				% [
					String(last.get("die", "")),
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

	for value: Variant in parsed as Array:
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
