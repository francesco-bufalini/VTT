extends Node

signal turn_changed(entry_id: String, round_number: int, turn_count: int)
signal combat_state_changed(active: bool)

const MAX_ENTRIES := 256
const ENVIRONMENT_ENTRY_ID := "initiative_environment"
const ENVIRONMENT_INITIATIVE := 20


func _environment_entry() -> Dictionary:
	return {
		"id": ENVIRONMENT_ENTRY_ID,
		"name": "Turno ambientale",
		"token_id": "",
		"initiative": ENVIRONMENT_INITIATIVE
	}


func _ensure_environment_entry() -> void:
	if not combat_active:
		return
	var active_id: String = _active_entry_id()
	var found: bool = false
	for index: int in range(entries.size() - 1, -1, -1):
		if String(entries[index].get("id", "")) != ENVIRONMENT_ENTRY_ID:
			continue
		if found:
			entries.remove_at(index)
		else:
			entries[index] = _environment_entry()
			found = true
	if not found:
		entries.insert(0, _environment_entry())
	if not active_id.is_empty():
		active_index = maxi(0, _entry_index(active_id))
	else:
		active_index = 0

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
var _restore_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _auto_filled_name: String = ""

var combat_active: bool = false
var entries: Array[Dictionary] = []
var active_index: int = 0
var round_number: int = 1
var turn_count: int = 0
var _next_entry_id: int = 1
var _name_watch_elapsed: float = 0.0
var _last_linked_name_signature: String = ""


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


func _process(delta: float) -> void:
	if panel == null or not panel.visible or entries.is_empty():
		return
	_name_watch_elapsed += delta
	if _name_watch_elapsed < 0.25:
		return
	_name_watch_elapsed = 0.0
	var signature := _linked_name_signature()
	if signature != _last_linked_name_signature:
		_render()


func _linked_name_signature() -> String:
	var parts := PackedStringArray()
	for entry: Dictionary in entries:
		var token_id := String(entry.get("token_id", ""))
		if token_id.is_empty():
			continue
		parts.append("%s:%s" % [token_id, _token_display_name_by_id(token_id)])
	return "|".join(parts)


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
	add_dialog.min_size = Vector2i(460, 300)
	add_dialog.add_theme_constant_override("buttons_min_width", 100)
	add_dialog.add_theme_constant_override("buttons_min_height", 34)
	ui_root.add_child(add_dialog)
	# Non dipendere dal footer nativo: con alcuni scaling può essere fuori
	# dalla finestra al primo popup.
	add_dialog.get_ok_button().hide()
	var native_cancel := add_dialog.get_cancel_button()
	if native_cancel != null:
		native_cancel.text = "Annulla"
		native_cancel.hide()

	# I figli di Accept/ConfirmationDialog partecipano già al layout interno.
	# Ancorarli a PRESET_FULL_RECT può coprire la barra OK/Annulla al primo
	# popup, specialmente con scaling UI elevato.
	var body: VBoxContainer = VBoxContainer.new()
	body.custom_minimum_size = Vector2(420, 175)
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
	participant_token.item_selected.connect(_on_participant_token_selected)
	body.add_child(participant_token)

	var info: Label = Label.new()
	info.text = (
		"Il collegamento al token viene salvato con il turno, "
		+ "ma per ora non modifica il token."
	)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 11)
	body.add_child(info)

	var actions := HBoxContainer.new()
	actions.name = "InitiativeAddActions"
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	body.add_child(actions)

	var cancel_button := Button.new()
	cancel_button.text = "Annulla"
	cancel_button.custom_minimum_size = Vector2(100, 36)
	cancel_button.pressed.connect(
		func() -> void:
			add_dialog.hide()
			_release_dialog_mouse()
	)
	actions.add_child(cancel_button)

	var add_button := Button.new()
	add_button.text = "Aggiungi"
	add_button.custom_minimum_size = Vector2(110, 36)
	add_button.pressed.connect(
		func() -> void:
			_on_add_confirmed()
			add_dialog.hide()
	)
	actions.add_child(add_button)

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
	var roller := _dice_chat()
	if (
		roller != null
		and roller.has_method("ensure_scene_identity")
	):
		roller.call("ensure_scene_identity")


func hide_panel() -> void:
	if panel != null:
		panel.hide()


func is_panel_visible() -> bool:
	return panel != null and panel.visible


func _dice_chat() -> Node:
	if board_root == null or not is_instance_valid(board_root):
		return null
	var value: Variant = board_root.get("dice_roller_chat")
	if value is Node and is_instance_valid(value):
		return value as Node
	return board_root.get_node_or_null("DiceRollerChat")


func _log_combat_action(
	text: String,
	round_override: int = 0
) -> void:
	var roller := _dice_chat()
	if roller == null or not roller.has_method("log_action"):
		return
	roller.call(
		"log_action",
		text,
		null,
		round_override
	)


func start_combat() -> void:
	if combat_active:
		show_panel()
		return
	var roller := _dice_chat()
	if (
		roller != null
		and roller.has_method("ensure_scene_identity")
		and not bool(
			roller.call(
				"ensure_scene_identity",
				Callable(self, "start_combat")
			)
		)
	):
		return
	_record_undo_state()
	combat_active = true
	entries.clear()
	active_index = 0
	round_number = 1
	turn_count = 0
	_next_entry_id = 1
	_ensure_environment_entry()
	show_panel()
	_render()
	combat_state_changed.emit(true)
	_log_combat_action("Combattimento iniziato", round_number)
	open_add_dialog()


func end_combat() -> void:
	var ending_round := round_number if combat_active else 0
	if combat_active or not entries.is_empty():
		_record_undo_state()
	combat_active = false
	entries.clear()
	active_index = 0
	round_number = 1
	turn_count = 0
	_next_entry_id = 1
	_render()
	combat_state_changed.emit(false)
	if ending_round > 0:
		_log_combat_action("Combattimento terminato", ending_round)


func open_add_dialog() -> void:
	if not combat_active or add_dialog == null:
		return
	participant_name.clear()
	_auto_filled_name = ""
	var preferred_token_id := _selected_board_token_id()
	_refresh_token_selector(preferred_token_id)
	_sync_name_field_to_token(_selected_token_id_from_option())
	_take_dialog_mouse()
	_popup_dialog_safe(add_dialog, Vector2i(460, 300))
	call_deferred("_focus_participant_name")


func _popup_dialog_safe(dialog: Window, preferred_size: Vector2i) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	var viewport_size := board_root.get_viewport().get_visible_rect().size
	var safe_size := Vector2i(
		mini(preferred_size.x, maxi(320, int(viewport_size.x) - 48)),
		mini(preferred_size.y, maxi(200, int(viewport_size.y) - 48))
	)
	dialog.reset_size()
	dialog.popup_centered_clamped(safe_size, 0.92)


func _focus_participant_name() -> void:
	if (
		add_dialog != null
		and add_dialog.visible
		and participant_name != null
	):
		participant_name.grab_focus()


func _on_add_confirmed() -> void:
	if not combat_active or entries.size() >= MAX_ENTRIES:
		_release_dialog_mouse()
		return

	var token_id: String = _selected_token_id_from_option()
	var name_value: String = participant_name.text.strip_edges()
	if not token_id.is_empty():
		name_value = _token_display_name_by_id(token_id)
		if name_value.is_empty():
			name_value = "Token senza nome"
	elif name_value.is_empty():
		name_value = "Partecipante %d" % (_next_entry_id)

	_record_undo_state()
	entries.append({
		"id": "initiative_%d" % _next_entry_id,
		"name": name_value,
		"token_id": token_id
	})
	_next_entry_id += 1
	_log_combat_action(
		"%s entra nel combattimento" % name_value,
		round_number
	)
	if entries.size() == 1:
		active_index = 0
		_emit_turn_changed()
	_render()
	_release_dialog_mouse()


func _refresh_token_selector(preferred_token_id: String = "") -> void:
	participant_token.clear()
	participant_token.add_item("Nessun token")
	participant_token.set_item_metadata(0, "")
	var selected_index := 0
	var unnamed_index := 1
	for token: Node3D in _tokens():
		var index: int = participant_token.item_count
		var visible_name := _token_display_name(token)
		var label := visible_name
		if label.is_empty():
			label = "Token senza nome %d" % unnamed_index
			unnamed_index += 1
		participant_token.add_item(label)
		var token_id := _token_id(token)
		participant_token.set_item_metadata(index, token_id)
		if not preferred_token_id.is_empty() and token_id == preferred_token_id:
			selected_index = index
	participant_token.select(selected_index)


func _on_participant_token_selected(_index: int) -> void:
	_sync_name_field_to_token(_selected_token_id_from_option())


func _sync_name_field_to_token(token_id: String) -> void:
	if token_id.is_empty():
		participant_name.editable = true
		if participant_name.text == _auto_filled_name:
			participant_name.clear()
		_auto_filled_name = ""
		return

	var suggested := _token_display_name_by_id(token_id)
	if suggested.is_empty():
		suggested = "Token senza nome"
	participant_name.text = suggested
	participant_name.editable = false
	_auto_filled_name = suggested


func _selected_board_token_id() -> String:
	if board_root == null or not is_instance_valid(board_root):
		return ""
	var selected_value: Variant = board_root.get("_selected_tokens")
	if not selected_value is Array:
		return ""
	var selected: Array = selected_value as Array
	if selected.size() != 1 or not selected[0] is Node3D:
		return ""
	var token := selected[0] as Node3D
	if not is_instance_valid(token) or not token.is_in_group("dnd_token"):
		return ""
	return _token_id(token)


func _selected_token_id_from_option() -> String:
	if participant_token == null or participant_token.item_count == 0:
		return ""
	var index: int = participant_token.selected
	if index < 0:
		return ""
	return String(participant_token.get_item_metadata(index))


func _record_undo_state() -> void:
	if (
		board_root != null
		and is_instance_valid(board_root)
		and board_root.has_method("push_undo_state")
	):
		board_root.call("push_undo_state")


func next_turn() -> void:
	if not combat_active or entries.is_empty():
		return
	_record_undo_state()
	var previous_round := round_number
	active_index += 1
	turn_count += 1
	if active_index >= entries.size():
		active_index = 0
		round_number += 1
	_render()
	_emit_turn_changed()
	if round_number != previous_round:
		_log_combat_action(
			"Inizia il round %d" % round_number,
			round_number
		)


func previous_turn() -> void:
	if not combat_active or entries.is_empty() or turn_count <= 0:
		return
	_record_undo_state()
	var previous_round := round_number
	if active_index == 0:
		active_index = entries.size() - 1
		round_number = maxi(1, round_number - 1)
	else:
		active_index -= 1
	turn_count = maxi(0, turn_count - 1)
	_render()
	_emit_turn_changed()
	if round_number != previous_round:
		_log_combat_action(
			"Ritorno al round %d" % round_number,
			round_number
		)


func refresh() -> void:
	_render()


func _render() -> void:
	if panel == null:
		return
	_synchronize_linked_entry_names()
	_last_linked_name_signature = _linked_name_signature()

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
		active_label.text = "Turno attivo: %s" % _entry_display_name(
			active_entry
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
		active_style.bg_color = Color(0.39, 0.18, 0.21, 0.95)
		active_style.border_color = Color(0.93, 0.72, 0.37, 1.0)
		active_style.border_width_left = 1
		active_style.border_width_top = 1
		active_style.border_width_right = 1
		active_style.border_width_bottom = 1
		active_style.corner_radius_top_left = 7
		active_style.corner_radius_top_right = 7
		active_style.corner_radius_bottom_left = 7
		active_style.corner_radius_bottom_right = 7
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
	name_label.text = _entry_display_name(entry)
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
		"Iniziativa: 20" if entry_id_is_environment(entry)
		else 
		"Token: %s" % _token_name_by_id(token_id)
		if not token_id.is_empty()
		else "Token: —"
	)
	token_label.modulate = Color(0.78, 0.8, 0.84, 1.0)
	token_label.add_theme_font_size_override("font_size", 10)
	text_column.add_child(token_label)

	var link_button: Button = Button.new()
	link_button.text = "Token"
	link_button.disabled = entry_id_is_environment(entry)
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
	up_button.disabled = real_index == 0 or entry_id_is_environment(entry)
	up_button.custom_minimum_size = Vector2(28, 30)
	up_button.pressed.connect(
		func() -> void:
			_move_entry(entry_id, -1)
	)
	row.add_child(up_button)

	var down_button: Button = Button.new()
	down_button.text = "↓"
	down_button.tooltip_text = "Sposta dopo nell'ordine"
	down_button.disabled = real_index >= entries.size() - 1 or entry_id_is_environment(entry)
	down_button.custom_minimum_size = Vector2(28, 30)
	down_button.pressed.connect(
		func() -> void:
			_move_entry(entry_id, 1)
	)
	row.add_child(down_button)

	var remove_button: Button = Button.new()
	remove_button.text = "×"
	remove_button.disabled = entry_id_is_environment(entry)
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
	if entry_id == ENVIRONMENT_ENTRY_ID:
		return
	var index: int = _entry_index(entry_id)
	if index < 0:
		return
	var destination: int = index + delta
	if destination < 0 or destination >= entries.size():
		return

	_record_undo_state()
	var active_id: String = _active_entry_id()
	var item: Dictionary = entries[index]
	entries.remove_at(index)
	entries.insert(destination, item)
	active_index = maxi(0, _entry_index(active_id))
	_render()


func _remove_entry(entry_id: String) -> void:
	if entry_id == ENVIRONMENT_ENTRY_ID:
		return
	var index: int = _entry_index(entry_id)
	if index < 0:
		return
	_record_undo_state()
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
	if entry_id == ENVIRONMENT_ENTRY_ID:
		return
	if token_popup == null:
		return
	_linking_entry_id = entry_id
	token_popup.clear()
	token_popup.add_item("Nessun token", 0)
	token_popup.set_item_metadata(0, "")

	var item_id: int = 1
	var unnamed_index := 1
	for token: Node3D in _tokens():
		var token_label := _token_display_name(token)
		if token_label.is_empty():
			token_label = "Token senza nome %d" % unnamed_index
			unnamed_index += 1
		token_popup.add_item(token_label, item_id)
		var item_index: int = token_popup.get_item_index(item_id)
		token_popup.set_item_metadata(item_index, _token_id(token))
		item_id += 1

	_take_dialog_mouse()
	var viewport_size: Vector2 = board_root.get_viewport().get_visible_rect().size
	token_popup.max_size = Vector2i(
		maxi(180, int(viewport_size.x) - 24),
		maxi(160, int(viewport_size.y) - 24)
	)
	token_popup.position = Vector2i(
		clampi(
			int(button.global_position.x),
			8,
			maxi(8, int(viewport_size.x) - 8)
		),
		clampi(
			int(button.global_position.y + button.size.y),
			8,
			maxi(8, int(viewport_size.y) - 8)
		)
	)
	token_popup.popup()


func _on_token_popup_selected(id: int) -> void:
	var index: int = token_popup.get_item_index(id)
	if index < 0:
		return
	var token_id: String = String(token_popup.get_item_metadata(index))
	var entry_index: int = _entry_index(_linking_entry_id)
	if entry_index >= 0:
		var current_token_id := String(entries[entry_index].get("token_id", ""))
		if current_token_id != token_id:
			_record_undo_state()
			entries[entry_index]["token_id"] = token_id
			if not token_id.is_empty():
				var linked_name := _token_display_name_by_id(token_id)
				if not linked_name.is_empty():
					entries[entry_index]["name"] = linked_name
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
			var name_a := _token_display_name(a)
			var name_b := _token_display_name(b)
			if name_a.is_empty():
				name_a = String(a.name)
			if name_b.is_empty():
				name_b = String(b.name)
			return name_a.naturalnocasecmp_to(name_b) < 0
	)
	return result


func _token_id(token: Node3D) -> String:
	if token.has_method("get_token_id"):
		var stable_id := String(token.call("get_token_id")).strip_edges()
		if not stable_id.is_empty():
			return stable_id
	if token.has_meta("sync_id"):
		return String(token.get_meta("sync_id"))
	if board_sync != null and is_instance_valid(board_sync):
		var value: Variant = board_sync.call("_sync_id", token)
		if value != null:
			return String(value)
	var fallback: String = "path:" + String(board_root.get_path_to(token))
	token.set_meta("sync_id", fallback)
	return fallback


func _token_display_name(token: Node3D) -> String:
	if token != null and token.has_method("get_display_name"):
		return String(token.call("get_display_name")).strip_edges()
	return ""


func _token_by_id(token_id: String) -> Node3D:
	if token_id.is_empty():
		return null
	for token: Node3D in _tokens():
		if _token_id(token) == token_id:
			return token
	return null


func _token_display_name_by_id(token_id: String) -> String:
	var token := _token_by_id(token_id)
	if token == null:
		return ""
	return _token_display_name(token)


func _token_name_by_id(token_id: String) -> String:
	if token_id.is_empty():
		return ""
	for token: Node3D in _tokens():
		if _token_id(token) == token_id:
			var display_name := _token_display_name(token)
			return display_name if not display_name.is_empty() else "senza nome"
	return "mancante"


func entry_id_is_environment(entry: Dictionary) -> bool:
	return String(entry.get("id", "")) == ENVIRONMENT_ENTRY_ID


func _entry_display_name(entry: Dictionary) -> String:
	var token_id := String(entry.get("token_id", ""))
	if not token_id.is_empty():
		var token_name := _token_display_name_by_id(token_id)
		if not token_name.is_empty():
			return token_name
		if _token_name_by_id(token_id) != "mancante":
			return "Token senza nome"
	return String(entry.get("name", "Partecipante"))


func _synchronize_linked_entry_names() -> void:
	for entry: Dictionary in entries:
		var token_id := String(entry.get("token_id", ""))
		if token_id.is_empty():
			continue
		var token_name := _token_display_name_by_id(token_id)
		if not token_name.is_empty():
			entry["name"] = token_name


func _entry_index(entry_id: String) -> int:
	for index: int in range(entries.size()):
		if String(entries[index].get("id", "")) == entry_id:
			return index
	return -1


func _active_entry_id() -> String:
	if entries.is_empty() or active_index < 0 or active_index >= entries.size():
		return ""
	return String(entries[active_index].get("id", ""))


func _emit_turn_changed(focus_camera: bool = true) -> void:
	var entry_id: String = _active_entry_id()
	if focus_camera:
		_focus_camera_on_active_token()
	turn_changed.emit(entry_id, round_number, turn_count)


func _focus_camera_on_active_token() -> void:
	if (
		entries.is_empty()
		or active_index < 0
		or active_index >= entries.size()
		or board_root == null
		or not is_instance_valid(board_root)
		or not board_root.has_method("focus_camera_on_token")
	):
		return
	var token_id := String(
		entries[active_index].get("token_id", "")
	).strip_edges()
	var token := _token_by_id(token_id)
	if token == null or not token is CharacterBody3D:
		return
	# Stessa azione del pulsante con l'occhio nella lista token.
	board_root.call("focus_camera_on_token", token)


func get_active_entry() -> Dictionary:
	if entries.is_empty() or active_index < 0 or active_index >= entries.size():
		return {}
	_synchronize_linked_entry_names()
	return entries[active_index].duplicate(true)


func combat_round_for_token(token: Node3D) -> int:
	if (
		not combat_active
		or token == null
		or not is_instance_valid(token)
	):
		return 0
	var token_id := _token_id(token)
	if token_id.is_empty():
		return 0
	for entry: Dictionary in entries:
		if String(entry.get("token_id", "")) == token_id:
			return maxi(1, round_number)
	return 0


func get_save_state() -> Dictionary:
	_synchronize_linked_entry_names()
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
		if String(entry_id) == ENVIRONMENT_ENTRY_ID:
			if String(entry_name) != "Turno ambientale" or String(token_id) != "":
				return false
		if not entry_name is String or String(entry_name).strip_edges().is_empty():
			return false
		if not token_id is String:
			return false

	var index_value: Variant = state.get("active_index", 0)
	var round_value: Variant = state.get("round", 1)
	var turns_value: Variant = state.get("turn_count", 0)
	var next_id_value: Variant = state.get("next_entry_id", 1)
	for numeric_value: Variant in [
		index_value,
		round_value,
		turns_value,
		next_id_value
	]:
		# JSON has a single numeric type. After a network round-trip Godot
		# parses integer-looking JSON values as floats, so accept either type
		# but still require a finite whole number.
		if not (numeric_value is int or numeric_value is float):
			return false
		var numeric_float := float(numeric_value)
		if not is_finite(numeric_float) or numeric_float != floor(numeric_float):
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
	entries.clear()
	var loaded_entries: Array = state.get("entries", []) as Array
	for item: Variant in loaded_entries:
		if item is Dictionary:
			entries.append((item as Dictionary).duplicate(true))
	active_index = int(state.get("active_index", 0))
	round_number = int(state.get("round", 1))
	turn_count = int(state.get("turn_count", 0))
	_next_entry_id = int(state.get("next_entry_id", 1))
	_ensure_environment_entry()
	if not combat_active:
		entries.clear()
		active_index = 0
		round_number = 1
		turn_count = 0
	_render()
	combat_state_changed.emit(combat_active)
	if combat_active and not entries.is_empty():
		# Restoring shared/saved state must preserve the local view. Only
		# explicit local turn actions should focus the active token.
		_emit_turn_changed(false)
	return true


func clear_state() -> void:
	combat_active = false
	entries.clear()
	active_index = 0
	round_number = 1
	turn_count = 0
	_next_entry_id = 1
	_render()
	combat_state_changed.emit(false)
