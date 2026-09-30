extends Node

signal turn_changed(entry_id: String, round_number: int, turn_count: int)
signal combat_state_changed(active: bool)

const MAX_ENTRIES := 256

var board_root: Node3D
var ui_root: CanvasLayer
var tokens_root: Node
var board_sync: Node

var panel: PanelContainer
var combat_controls: HBoxContainer
var inactive_controls: VBoxContainer
var list_scroll: ScrollContainer
var list_box: VBoxContainer
var round_label: Label
var active_label: Label
var start_button: Button
var end_button: Button
var add_button: Button
var previous_button: Button
var next_button: Button

var add_dialog: ConfirmationDialog
var participant_name: LineEdit
var participant_token: OptionButton
var token_popup: PopupMenu
var _linking_entry_id: String = ""
var _restore_mouse_mode: int = Input.MOUSE_MODE_CAPTURED

var combat_active: bool = false
var entries: Array[Dictionary] = []
var active_index: int = 0
var round_number: int = 1
var turn_count: int = 0
var _next_entry_id: int = 1


func setup(root: Node3D) -> void:
	board_root = root
	call_deferred("_initialize")


func _initialize() -> void:
	if board_root == null or not is_instance_valid(board_root):
		queue_free()
		return
	ui_root = board_root.get_node_or_null("UI") as CanvasLayer
	tokens_root = board_root.get_node_or_null("Tokens")
	var sync_value: Variant = board_root.get("board_sync")
	if sync_value is Node and is_instance_valid(sync_value):
		board_sync = sync_value as Node
	if ui_root == null:
		queue_free()
		return

	_build_panel()
	_build_add_dialog()
	_build_token_popup()
	_render()


func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "InitiativePanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -338.0
	panel.offset_right = -8.0
	panel.offset_top = 54.0
	panel.offset_bottom = -8.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.hide()
	ui_root.add_child(panel)

	var outer: MarginContainer = MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 10)
	outer.add_theme_constant_override("margin_right", 10)
	outer.add_theme_constant_override("margin_top", 10)
	outer.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(outer)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	outer.add_child(column)

	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)

	var title: Label = Label.new()
	title.text = "INIZIATIVA"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)

	var hide_button: Button = Button.new()
	hide_button.text = "×"
	hide_button.tooltip_text = "Nascondi lista iniziativa"
	hide_button.custom_minimum_size = Vector2(32, 28)
	hide_button.pressed.connect(hide_panel)
	header.add_child(hide_button)

	round_label = Label.new()
	round_label.text = "Fuori dal combattimento"
	round_label.add_theme_font_size_override("font_size", 14)
	column.add_child(round_label)

	active_label = Label.new()
	active_label.text = ""
	active_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	active_label.add_theme_font_size_override("font_size", 13)
	column.add_child(active_label)

	inactive_controls = VBoxContainer.new()
	inactive_controls.add_theme_constant_override("separation", 6)
	column.add_child(inactive_controls)

	var inactive_help: Label = Label.new()
	inactive_help.text = (
		"Avvia il combattimento e inserisci i partecipanti "
		+ "nell'ordine di iniziativa."
	)
	inactive_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inactive_controls.add_child(inactive_help)

	start_button = Button.new()
	start_button.text = "Avvia combattimento"
	start_button.pressed.connect(start_combat)
	inactive_controls.add_child(start_button)

	combat_controls = HBoxContainer.new()
	combat_controls.add_theme_constant_override("separation", 4)
	column.add_child(combat_controls)

	previous_button = Button.new()
	previous_button.text = "◀ Turno"
	previous_button.tooltip_text = "Torna al turno precedente"
	previous_button.pressed.connect(previous_turn)
	combat_controls.add_child(previous_button)

	next_button = Button.new()
	next_button.text = "Turno ▶"
	next_button.tooltip_text = "Passa al turno successivo"
	next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_button.pressed.connect(next_turn)
	combat_controls.add_child(next_button)

	list_scroll = ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(list_scroll)

	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 4)
	list_scroll.add_child(list_box)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 4)
	column.add_child(footer)

	add_button = Button.new()
	add_button.text = "+ Partecipante"
	add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_button.pressed.connect(open_add_dialog)
	footer.add_child(add_button)

	end_button = Button.new()
	end_button.text = "Termina"
	end_button.tooltip_text = "Termina il combattimento e svuota la lista"
	end_button.pressed.connect(end_combat)
	footer.add_child(end_button)


func _build_add_dialog() -> void:
	add_dialog = ConfirmationDialog.new()
	add_dialog.name = "InitiativeAddDialog"
	add_dialog.title = "Aggiungi partecipante"
	add_dialog.ok_button_text = "Aggiungi"
	add_dialog.min_size = Vector2i(460, 260)
	ui_root.add_child(add_dialog)

	var body: VBoxContainer = VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 14.0
	body.offset_right = -14.0
	body.offset_top = 48.0
	body.offset_bottom = -58.0
	body.add_theme_constant_override("separation", 8)
	add_dialog.add_child(body)

	var name_label: Label = Label.new()
	name_label.text = "Nome nell'ordine di iniziativa"
	body.add_child(name_label)

	participant_name = LineEdit.new()
	participant_name.placeholder_text = "Es. Kaos, Goblin 1, Sariel..."
	participant_name.text_submitted.connect(
		func(_value: String) -> void:
			if not participant_name.text.strip_edges().is_empty():
				add_dialog.get_ok_button().emit_signal("pressed")
	)
	body.add_child(participant_name)

	var token_label: Label = Label.new()
	token_label.text = "Token collegato (opzionale)"
	body.add_child(token_label)

	participant_token = OptionButton.new()
	body.add_child(participant_token)

	var info: Label = Label.new()
	info.text = (
		"Il collegamento al token viene salvato con il turno, "
		+ "ma per ora non modifica il token."
	)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 11)
	body.add_child(info)

	add_dialog.confirmed.connect(_on_add_confirmed)
	add_dialog.canceled.connect(_release_dialog_mouse)
	add_dialog.close_requested.connect(_release_dialog_mouse)


func _build_token_popup() -> void:
	token_popup = PopupMenu.new()
	token_popup.name = "InitiativeTokenPopup"
	token_popup.id_pressed.connect(_on_token_popup_selected)
	token_popup.popup_hide.connect(_on_token_popup_hidden)
	ui_root.add_child(token_popup)


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
	panel.show()
	_render()


func hide_panel() -> void:
	if panel != null:
		panel.hide()


func is_panel_visible() -> bool:
	return panel != null and panel.visible


func start_combat() -> void:
	if combat_active:
		show_panel()
		return
	combat_active = true
	entries.clear()
	active_index = 0
	round_number = 1
	turn_count = 0
	_next_entry_id = 1
	show_panel()
	_render()
	combat_state_changed.emit(true)
	open_add_dialog()


func end_combat() -> void:
	combat_active = false
	entries.clear()
	active_index = 0
	round_number = 1
	turn_count = 0
	_next_entry_id = 1
	_render()
	combat_state_changed.emit(false)


func open_add_dialog() -> void:
	if not combat_active or add_dialog == null:
		return
	participant_name.clear()
	_refresh_token_selector()
	_take_dialog_mouse()
	add_dialog.popup_centered(Vector2i(460, 260))
	participant_name.grab_focus()


func _on_add_confirmed() -> void:
	if not combat_active or entries.size() >= MAX_ENTRIES:
		_release_dialog_mouse()
		return

	var name_value: String = participant_name.text.strip_edges()
	var token_id: String = _selected_token_id_from_option()
	if name_value.is_empty():
		name_value = _token_name_by_id(token_id)
	if name_value.is_empty():
		name_value = "Partecipante %d" % (_next_entry_id)

	entries.append({
		"id": "initiative_%d" % _next_entry_id,
		"name": name_value,
		"token_id": token_id
	})
	_next_entry_id += 1
	if entries.size() == 1:
		active_index = 0
		_emit_turn_changed()
	_render()
	_release_dialog_mouse()


func _refresh_token_selector() -> void:
	participant_token.clear()
	participant_token.add_item("Nessun token")
	participant_token.set_item_metadata(0, "")
	for token: Node3D in _tokens():
		var index: int = participant_token.item_count
		participant_token.add_item(String(token.name))
		participant_token.set_item_metadata(index, _token_id(token))
	participant_token.select(0)


func _selected_token_id_from_option() -> String:
	if participant_token == null or participant_token.item_count == 0:
		return ""
	var index: int = participant_token.selected
	if index < 0:
		return ""
	return String(participant_token.get_item_metadata(index))


func next_turn() -> void:
	if not combat_active or entries.is_empty():
		return
	active_index += 1
	turn_count += 1
	if active_index >= entries.size():
		active_index = 0
		round_number += 1
	_render()
	_emit_turn_changed()


func previous_turn() -> void:
	if not combat_active or entries.is_empty() or turn_count <= 0:
		return
	if active_index == 0:
		active_index = entries.size() - 1
		round_number = maxi(1, round_number - 1)
	else:
		active_index -= 1
	turn_count = maxi(0, turn_count - 1)
	_render()
	_emit_turn_changed()


func _render() -> void:
	if panel == null:
		return

	inactive_controls.visible = not combat_active
	combat_controls.visible = combat_active
	list_scroll.visible = combat_active
	add_button.visible = combat_active
	end_button.visible = combat_active
	previous_button.disabled = (
		not combat_active
		or entries.is_empty()
		or turn_count <= 0
	)
	next_button.disabled = not combat_active or entries.is_empty()
	add_button.disabled = entries.size() >= MAX_ENTRIES

	if not combat_active:
		round_label.text = "Fuori dal combattimento"
		active_label.text = ""
		_clear_list_rows()
		return

	round_label.text = "Round %d · %d partecipanti" % [
		round_number,
		entries.size()
	]

	if entries.is_empty():
		active_label.text = "Nessun partecipante. Aggiungili in ordine."
	else:
		var active_entry: Dictionary = entries[active_index]
		active_label.text = "Turno attivo: %s" % String(
			active_entry.get("name", "Partecipante")
		)

	_clear_list_rows()
	if entries.is_empty():
		return

	# The active turn is always rendered first, so advancing or going back
	# visibly scrolls/rotates the initiative list.
	for offset: int in range(entries.size()):
		var real_index: int = (active_index + offset) % entries.size()
		_add_entry_row(entries[real_index], real_index, offset == 0)
	call_deferred("_scroll_active_to_top")


func _clear_list_rows() -> void:
	if list_box == null:
		return
	for child: Node in list_box.get_children():
		child.queue_free()


func _add_entry_row(
	entry: Dictionary,
	real_index: int,
	is_active: bool
) -> void:
	var row_panel: PanelContainer = PanelContainer.new()
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_active:
		var active_style: StyleBoxFlat = StyleBoxFlat.new()
		active_style.bg_color = Color(0.22, 0.31, 0.46, 0.92)
		active_style.border_color = Color(0.82, 0.72, 0.30, 1.0)
		active_style.set_border_width_all(1)
		active_style.corner_radius_top_left = 4
		active_style.corner_radius_top_right = 4
		active_style.corner_radius_bottom_left = 4
		active_style.corner_radius_bottom_right = 4
		row_panel.add_theme_stylebox_override("panel", active_style)
	list_box.add_child(row_panel)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row_panel.add_child(row)

	var marker: Label = Label.new()
	marker.text = "▶" if is_active else " "
	marker.custom_minimum_size = Vector2(18, 0)
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(marker)

	var text_column: VBoxContainer = VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_column)

	var name_label: Label = Label.new()
	name_label.text = String(entry.get("name", "Partecipante"))
	name_label.clip_text = true
	name_label.tooltip_text = name_label.text
	name_label.add_theme_font_size_override(
		"font_size",
		14 if is_active else 13
	)
	text_column.add_child(name_label)

	var token_id: String = String(entry.get("token_id", ""))
	var token_label: Label = Label.new()
	token_label.text = (
		"Token: %s" % _token_name_by_id(token_id)
		if not token_id.is_empty()
		else "Token: —"
	)
	token_label.modulate = Color(0.78, 0.8, 0.84, 1.0)
	token_label.add_theme_font_size_override("font_size", 10)
	text_column.add_child(token_label)

	var link_button: Button = Button.new()
	link_button.text = "Token"
	link_button.tooltip_text = "Collega o scollega un token"
	link_button.custom_minimum_size = Vector2(48, 30)
	var entry_id: String = String(entry.get("id", ""))
	link_button.pressed.connect(
		func() -> void:
			_open_token_popup(entry_id, link_button)
	)
	row.add_child(link_button)

	var up_button: Button = Button.new()
	up_button.text = "↑"
	up_button.tooltip_text = "Sposta prima nell'ordine"
	up_button.disabled = real_index == 0
	up_button.custom_minimum_size = Vector2(28, 30)
	up_button.pressed.connect(
		func() -> void:
			_move_entry(entry_id, -1)
	)
	row.add_child(up_button)

	var down_button: Button = Button.new()
	down_button.text = "↓"
	down_button.tooltip_text = "Sposta dopo nell'ordine"
	down_button.disabled = real_index >= entries.size() - 1
	down_button.custom_minimum_size = Vector2(28, 30)
	down_button.pressed.connect(
		func() -> void:
			_move_entry(entry_id, 1)
	)
	row.add_child(down_button)

	var remove_button: Button = Button.new()
	remove_button.text = "×"
	remove_button.tooltip_text = "Rimuovi dall'iniziativa"
	remove_button.custom_minimum_size = Vector2(28, 30)
	remove_button.pressed.connect(
		func() -> void:
			_remove_entry(entry_id)
	)
	row.add_child(remove_button)


func _scroll_active_to_top() -> void:
	if list_scroll != null:
		list_scroll.scroll_vertical = 0


func _move_entry(entry_id: String, delta: int) -> void:
	var index: int = _entry_index(entry_id)
	if index < 0:
		return
	var destination: int = index + delta
	if destination < 0 or destination >= entries.size():
		return

	var active_id: String = _active_entry_id()
	var item: Dictionary = entries[index]
	entries.remove_at(index)
	entries.insert(destination, item)
	active_index = maxi(0, _entry_index(active_id))
	_render()


func _remove_entry(entry_id: String) -> void:
	var index: int = _entry_index(entry_id)
	if index < 0:
		return
	var active_id: String = _active_entry_id()
	var removing_active: bool = active_id == entry_id
	entries.remove_at(index)

	if entries.is_empty():
		active_index = 0
	elif removing_active:
		active_index = index if index < entries.size() else 0
	else:
		active_index = maxi(0, _entry_index(active_id))
	_render()
	if removing_active and not entries.is_empty():
		_emit_turn_changed()


func _open_token_popup(entry_id: String, button: Control) -> void:
	if token_popup == null:
		return
	_linking_entry_id = entry_id
	token_popup.clear()
	token_popup.add_item("Nessun token", 0)
	token_popup.set_item_metadata(0, "")

	var item_id: int = 1
	for token: Node3D in _tokens():
		token_popup.add_item(String(token.name), item_id)
		var item_index: int = token_popup.get_item_index(item_id)
		token_popup.set_item_metadata(item_index, _token_id(token))
		item_id += 1

	_take_dialog_mouse()
	token_popup.position = Vector2i(
		int(button.global_position.x),
		int(button.global_position.y + button.size.y)
	)
	token_popup.popup()


func _on_token_popup_selected(id: int) -> void:
	var index: int = token_popup.get_item_index(id)
	if index < 0:
		return
	var token_id: String = String(token_popup.get_item_metadata(index))
	var entry_index: int = _entry_index(_linking_entry_id)
	if entry_index >= 0:
		entries[entry_index]["token_id"] = token_id
	_render()


func _on_token_popup_hidden() -> void:
	_linking_entry_id = ""
	_release_dialog_mouse()


func _take_dialog_mouse() -> void:
	if board_root == null:
		return
	_restore_mouse_mode = Input.mouse_mode
	board_root.set("_ui_owns_mouse", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _release_dialog_mouse() -> void:
	if board_root == null:
		return
	board_root.set("_ui_owns_mouse", false)
	Input.mouse_mode = _restore_mouse_mode


func _tokens() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if board_root == null:
		return result
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			node is Node3D
			and board_root.is_ancestor_of(node)
			and not node.is_queued_for_deletion()
		):
			result.append(node as Node3D)
	result.sort_custom(
		func(a: Node3D, b: Node3D) -> bool:
			return String(a.name).naturalnocasecmp_to(String(b.name)) < 0
	)
	return result


func _token_id(token: Node3D) -> String:
	if token.has_meta("sync_id"):
		return String(token.get_meta("sync_id"))
	if board_sync != null and is_instance_valid(board_sync):
		var value: Variant = board_sync.call("_sync_id", token)
		if value != null:
			return String(value)
	var fallback: String = "path:" + String(board_root.get_path_to(token))
	token.set_meta("sync_id", fallback)
	return fallback


func _token_name_by_id(token_id: String) -> String:
	if token_id.is_empty():
		return ""
	for token: Node3D in _tokens():
		if _token_id(token) == token_id:
			return String(token.name)
	return "mancante"


func _entry_index(entry_id: String) -> int:
	for index: int in range(entries.size()):
		if String(entries[index].get("id", "")) == entry_id:
			return index
	return -1


func _active_entry_id() -> String:
	if entries.is_empty() or active_index < 0 or active_index >= entries.size():
		return ""
	return String(entries[active_index].get("id", ""))


func _emit_turn_changed() -> void:
	var entry_id: String = _active_entry_id()
	turn_changed.emit(entry_id, round_number, turn_count)


func get_save_state() -> Dictionary:
	return {
		"version": 1,
		"active": combat_active,
		"entries": entries.duplicate(true),
		"active_index": active_index,
		"round": round_number,
		"turn_count": turn_count,
		"next_entry_id": _next_entry_id
	}


func valid_state(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var state: Dictionary = value as Dictionary
	if int(state.get("version", 1)) != 1:
		return false
	if not state.get("active", false) is bool:
		return false

	var entries_value: Variant = state.get("entries", [])
	if not entries_value is Array:
		return false
	var state_entries: Array = entries_value as Array
	if state_entries.size() > MAX_ENTRIES:
		return false

	var seen_ids: Dictionary = {}
	for item: Variant in state_entries:
		if not item is Dictionary:
			return false
		var entry: Dictionary = item as Dictionary
		var entry_id: Variant = entry.get("id", "")
		var entry_name: Variant = entry.get("name", "")
		var token_id: Variant = entry.get("token_id", "")
		if not entry_id is String or String(entry_id).is_empty():
			return false
		if seen_ids.has(String(entry_id)):
			return false
		seen_ids[String(entry_id)] = true
		if not entry_name is String or String(entry_name).strip_edges().is_empty():
			return false
		if not token_id is String:
			return false

	var index_value: Variant = state.get("active_index", 0)
	var round_value: Variant = state.get("round", 1)
	var turns_value: Variant = state.get("turn_count", 0)
	var next_id_value: Variant = state.get("next_entry_id", 1)
	if not index_value is int or not round_value is int:
		return false
	if not turns_value is int or not next_id_value is int:
		return false
	if int(round_value) < 1 or int(turns_value) < 0 or int(next_id_value) < 1:
		return false
	if state_entries.is_empty():
		return int(index_value) == 0
	return int(index_value) >= 0 and int(index_value) < state_entries.size()


func load_state(value: Variant) -> bool:
	if not valid_state(value):
		return false
	var state: Dictionary = value as Dictionary
	combat_active = bool(state.get("active", false))
	entries = (state.get("entries", []) as Array).duplicate(true)
	active_index = int(state.get("active_index", 0))
	round_number = int(state.get("round", 1))
	turn_count = int(state.get("turn_count", 0))
	_next_entry_id = int(state.get("next_entry_id", 1))
	if not combat_active:
		entries.clear()
		active_index = 0
		round_number = 1
		turn_count = 0
	_render()
	return true


func clear_state() -> void:
	combat_active = false
	entries.clear()
	active_index = 0
	round_number = 1
	turn_count = 0
	_next_entry_id = 1
	_render()
