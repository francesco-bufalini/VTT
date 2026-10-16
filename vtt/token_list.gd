extends Node

const EYE_ICON := preload("res://vtt/icons/eye.svg")

var board_root: Node3D
var ui_root: CanvasLayer
var panel: PanelContainer
var list_box: VBoxContainer
var count_label: Label
var export_dialog: FileDialog
var delete_dialog: ConfirmationDialog
var bulk_export: Button
var bulk_delete: Button
var select_all_button: Button
var clear_button: Button
var _row_checks: Dictionary = {}
var _signature: String = ""
var _refresh_accumulator: float = 0.0


func setup(root: Node3D) -> void:
	board_root = root
	call_deferred("_initialize")


func _initialize() -> void:
	if board_root == null or not is_instance_valid(board_root):
		queue_free()
		return
	ui_root = board_root.get_node_or_null("UI") as CanvasLayer
	if ui_root == null:
		queue_free()
		return
	_build_panel()
	refresh()


func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "TokenListPanel"
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 8.0
	panel.offset_right = 332.0
	panel.offset_top = 54.0
	panel.offset_bottom = -8.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.hide()
	ui_root.add_child(panel)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 10)
	outer.add_theme_constant_override("margin_right", 10)
	outer.add_theme_constant_override("margin_top", 10)
	outer.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(outer)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	outer.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)

	var title := Label.new()
	title.text = "LISTA TOKEN"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)

	var close_button := Button.new()
	close_button.text = "x"
	close_button.tooltip_text = "Chiudi lista token"
	close_button.custom_minimum_size = Vector2(32, 28)
	close_button.pressed.connect(hide_panel)
	header.add_child(close_button)

	count_label = Label.new()
	count_label.add_theme_font_size_override("font_size", 11)
	column.add_child(count_label)

	var help := Label.new()
	help.text = (
		"Le caselle permettono una selezione multipla. "
		+ "Il pulsante con l'occhio porta la camera davanti al token."
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 11)
	column.add_child(help)

	var select_row := HBoxContainer.new()
	column.add_child(select_row)
	select_all_button = Button.new()
	select_all_button.text = "Seleziona tutti"
	select_all_button.pressed.connect(_select_all_tokens.bind(true))
	select_row.add_child(select_all_button)
	clear_button = Button.new()
	clear_button.text = "Deseleziona tutti"
	clear_button.pressed.connect(_select_all_tokens.bind(false))
	select_row.add_child(clear_button)

	var operations := HBoxContainer.new()
	column.add_child(operations)
	bulk_export = Button.new()
	bulk_export.text = "Esporta selezionati…"
	bulk_export.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bulk_export.pressed.connect(open_export_dialog)
	operations.add_child(bulk_export)
	bulk_delete = Button.new()
	bulk_delete.text = "Elimina selezionati…"
	bulk_delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bulk_delete.pressed.connect(_confirm_delete)
	operations.add_child(bulk_delete)

	export_dialog = FileDialog.new()
	export_dialog.title = "Esporta token selezionati"
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.filters = PackedStringArray(["*.vtttokens ; Gruppo token VTT"])
	export_dialog.current_file = "token_selezionati.vtttokens"
	export_dialog.file_selected.connect(_export_selection_to_path)
	ui_root.add_child(export_dialog)

	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "Elimina i token selezionati?"
	delete_dialog.confirmed.connect(_delete_confirmed)
	ui_root.add_child(delete_dialog)

	var scroll := ScrollContainer.new()
	scroll.mouse_force_pass_scroll_events = false
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 3)
	scroll.add_child(list_box)


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
	refresh()
	board_root.set("_ui_owns_mouse", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_panel() -> void:
	if panel == null:
		return
	panel.hide()
	if board_root != null and is_instance_valid(board_root):
		board_root.set("_ui_owns_mouse", false)
		if board_root.has_method("_capture_mouse"):
			board_root.call_deferred("_capture_mouse")


func is_panel_visible() -> bool:
	return panel != null and panel.visible


func refresh() -> void:
	_signature = ""
	if panel != null and panel.visible:
		_refresh_rows_if_needed(true)


func _process(delta: float) -> void:
	if panel == null or not panel.visible:
		return

	_refresh_accumulator += delta
	if _refresh_accumulator >= 0.20:
		_refresh_accumulator = 0.0
		_refresh_rows_if_needed(false)
	_sync_selection_checks()
	_update_bulk_buttons()


func _update_bulk_buttons() -> void:
	if bulk_export == null:
		return
	var count := _selection().size()
	bulk_export.disabled = count == 0
	bulk_delete.disabled = count == 0
	select_all_button.disabled = _tokens().is_empty()
	clear_button.disabled = count == 0


func _refresh_rows_if_needed(force: bool) -> void:
	var tokens := _tokens()
	var new_signature := _token_signature(tokens)
	if not force and new_signature == _signature:
		return
	_signature = new_signature

	for child: Node in list_box.get_children():
		child.queue_free()
	_row_checks.clear()

	count_label.text = "%d token in gioco" % tokens.size()
	if tokens.is_empty():
		var empty := Label.new()
		empty.text = "Nessun token presente."
		list_box.add_child(empty)
		return

	for token: CharacterBody3D in tokens:
		_add_token_row(token)


func _add_token_row(token: CharacterBody3D) -> void:
	var row_panel := PanelContainer.new()
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_child(row_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row_panel.add_child(row)

	var select_button := CheckButton.new()
	select_button.button_pressed = token.is_selected() if token.has_method("is_selected") else false
	select_button.custom_minimum_size = Vector2(30, 30)
	select_button.tooltip_text = "Seleziona / deseleziona token"
	select_button.toggled.connect(_on_token_toggled.bind(token))
	row.add_child(select_button)
	_row_checks[token.get_instance_id()] = select_button

	var name_label := Label.new()
	var display_name := _display_name(token)
	var party_id := _party_id(token)
	var row_name := display_name if not display_name.is_empty() else "(senza nome)"
	if not party_id.is_empty():
		row_name += "  ·  [%s]" % party_id
	name_label.text = row_name
	name_label.tooltip_text = row_name
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var focus_button := Button.new()
	focus_button.icon = EYE_ICON
	focus_button.expand_icon = false
	focus_button.custom_minimum_size = Vector2(38, 34)
	focus_button.tooltip_text = "Porta la camera davanti al token"
	focus_button.pressed.connect(_focus_token.bind(token))
	row.add_child(focus_button)


func _selection() -> Array[CharacterBody3D]:
	if board_root == null or not is_instance_valid(board_root):
		return []
	if board_root.has_method("get_selected_tokens_for_creatures"):
		return board_root.call("get_selected_tokens_for_creatures")
	return []


func _select_all_tokens(selected: bool) -> void:
	if board_root == null or not is_instance_valid(board_root):
		return
	if not selected:
		board_root.call("clear_token_selection")
	else:
		for token: CharacterBody3D in _tokens():
			board_root.call("set_token_selected_from_ui", token, true)
	_sync_selection_checks()


func open_export_dialog() -> void:
	var chosen := _selection()
	if chosen.is_empty():
		return
	export_dialog.current_file = "token_selezionati.vtttokens"
	export_dialog.popup_centered_clamped(Vector2i(800, 560), 0.92)


func _export_selection_to_path(path: String) -> void:
	var sync: Node = board_root.get("board_sync") as Node
	if sync != null and sync.has_method("export_selected_tokens_to_file"):
		sync.call("export_selected_tokens_to_file", path, _selection())


func _confirm_delete() -> void:
	var selected := _selection()
	if selected.is_empty():
		return
	delete_dialog.dialog_text = "Eliminare %d token dalla mappa?\nLe schede creature nell'archivio non vengono cancellate.\nPuoi usare Annulla (Ctrl+Z) per ripristinare." % selected.size()
	delete_dialog.popup_centered_clamped(Vector2i(470, 260), 0.92)


func _delete_confirmed() -> void:
	if board_root != null and is_instance_valid(board_root):
		board_root.call("_delete_selected")
		call_deferred("refresh")


func _on_token_toggled(selected: bool, token: CharacterBody3D) -> void:
	if token == null or not is_instance_valid(token):
		refresh()
		return
	if board_root.has_method("set_token_selected_from_ui"):
		board_root.call("set_token_selected_from_ui", token, selected)
	_update_bulk_buttons()


func _focus_token(token: CharacterBody3D) -> void:
	if token == null or not is_instance_valid(token):
		refresh()
		return
	if board_root.has_method("focus_camera_on_token"):
		board_root.call("focus_camera_on_token", token)


func _sync_selection_checks() -> void:
	for token: CharacterBody3D in _tokens():
		var instance_id := token.get_instance_id()
		var check: CheckButton = _row_checks.get(instance_id) as CheckButton
		if check == null:
			continue
		var selected: bool = false
		if token.has_method("is_selected"):
			selected = bool(token.call("is_selected"))
		check.set_pressed_no_signal(selected)


func _tokens() -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	if board_root == null:
		return result
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			node is CharacterBody3D
			and board_root.is_ancestor_of(node)
			and not node.is_queued_for_deletion()
		):
			result.append(node as CharacterBody3D)
	result.sort_custom(
		func(a: CharacterBody3D, b: CharacterBody3D) -> bool:
			var name_a := _display_name(a)
			var name_b := _display_name(b)
			if name_a.is_empty():
				name_a = String(a.name)
			if name_b.is_empty():
				name_b = String(b.name)
			return name_a.naturalnocasecmp_to(name_b) < 0
	)
	return result


func _display_name(token: Node3D) -> String:
	if token.has_method("get_display_name"):
		return String(token.call("get_display_name")).strip_edges()
	return ""


func _party_id(token: Node3D) -> String:
	if token.has_method("get_effective_party_id"):
		return String(token.call("get_effective_party_id")).strip_edges()
	if token.has_method("get_party_id"):
		var raw := String(token.call("get_party_id")).strip_edges()
		return raw if not raw.is_empty() else "Default"
	var metadata := String(token.get_meta("party_id", "")).strip_edges()
	return metadata if not metadata.is_empty() else "Default"


func _token_signature(tokens: Array[CharacterBody3D]) -> String:
	var parts := PackedStringArray()
	for token: CharacterBody3D in tokens:
		parts.append(
			"%d:%s:%s"
			% [
				token.get_instance_id(),
				_display_name(token),
				_party_id(token)
			]
		)
	return "|".join(parts)
