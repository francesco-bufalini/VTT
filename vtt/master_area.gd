extends Node

const BestiaryClient = preload("res://vtt/bestiary_5etools_client.gd")
const CreatureStore = preload("res://vtt/master_creature_store.gd")
const PDFStatblockImporter = preload("res://vtt/pdf_statblock_importer.gd")

var board_root: Node3D
var ui_root: CanvasLayer
var _client: Node
var _store: RefCounted
var _pdf_importer: RefCounted

var _catalog: Array[Dictionary] = []
var _creatures: Array[Dictionary] = []
var _current_id: String = ""
var _pending_side_by_request: Dictionary = {}
var _loading_form: bool = false

var _panel: PanelContainer
var _status_label: Label
var _bestiary_filter: LineEdit
var _bestiary_list: ItemList
var _enemy_list: ItemList
var _ally_list: ItemList
var _name_edit: LineEdit
var _current_hp: SpinBox
var _max_hp: SpinBox
var _linked_token_label: Label
var _stat_block: RichTextLabel

var _token_dialog: ConfirmationDialog
var _token_selector: OptionButton
var _token_info: Label

var _selected_token_dialog: ConfirmationDialog
var _selected_creature_selector: OptionButton
var _selected_token_info: Label
var _selected_link_token: CharacterBody3D

var _pdf_dialog: FileDialog
var _pending_pdf_side: String = "enemy"


func setup(root: Node3D) -> void:
	board_root = root
	ui_root = board_root.get_node_or_null("UI") as CanvasLayer
	if ui_root == null:
		queue_free()
		return

	_store = CreatureStore.new()
	_store.call("setup", _campaign_manager())
	_pdf_importer = PDFStatblockImporter.new()
	_client = BestiaryClient.new()
	_client.name = "Bestiary5eTools"
	add_child(_client)
	_client.call("setup")
	_client.catalog_ready.connect(_on_catalog_ready)
	_client.catalog_failed.connect(_on_catalog_failed)
	_client.creature_ready.connect(_on_creature_ready)
	_client.creature_failed.connect(_on_creature_failed)

	_build_ui()
	_build_token_dialog()
	_build_selected_token_dialog()
	_build_pdf_dialog()
	_reload_creatures()
	_set_status("Caricamento bestiario 5eTools…")
	_client.call("load_catalog")


func _unhandled_input(event: InputEvent) -> void:
	if _panel == null or not _panel.visible or _modal_visible():
		return
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		hide_panel()
		get_viewport().set_input_as_handled()


func _modal_visible() -> bool:
	for dialog: Window in [
		_token_dialog,
		_selected_token_dialog,
		_pdf_dialog,
	]:
		if dialog != null and is_instance_valid(dialog) and dialog.visible:
			return true
	return false


func toggle_panel() -> void:
	if _panel == null:
		return
	if _panel.visible:
		hide_panel()
	else:
		show_panel()


func show_panel() -> void:
	if _panel == null:
		return
	_panel.show()
	if board_root.has_method("release_camera_control"):
		board_root.call("release_camera_control")
	else:
		board_root.set("_ui_owns_mouse", true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_panel() -> void:
	if _panel == null:
		return
	_save_current_fields()
	_panel.hide()
	if board_root.has_method("capture_camera_control"):
		board_root.call("capture_camera_control")


func request_link_selected_creature_to_named_token() -> void:
	show_panel()
	var creature := _current_creature()
	if creature.is_empty():
		_set_status("Seleziona prima una creatura in Nemici o Alleati.")
		return

	_save_current_fields()
	_token_selector.clear()
	var selected_index := 0
	var token_count := 0
	for token: CharacterBody3D in _named_scene_tokens():
		var display_name := _display_token_name(token)
		if display_name.is_empty():
			continue
		_token_selector.add_item(display_name)
		var item_index := _token_selector.item_count - 1
		_token_selector.set_item_metadata(item_index, token.get_instance_id())
		token_count += 1
		if (
			token.has_meta("master_creature_id")
			and String(token.get_meta("master_creature_id"))
			== String(creature.get("id", ""))
		):
			selected_index = item_index

	if token_count == 0:
		_set_status("Nello scenario non ci sono token con un nome.")
		return

	_token_selector.select(selected_index)
	_token_info.text = (
		"Creatura: %s\nScegli il token da collegare."
		% String(creature.get("name", "Creatura"))
	)
	_token_dialog.reset_size()
	_token_dialog.popup_centered_clamped(Vector2i(520, 245), 0.92)


func request_link_creature_to_selected_token() -> void:
	show_panel()
	var selected := _selected_tokens()
	if selected.size() != 1:
		_set_status("Seleziona esattamente un token nello scenario.")
		return
	if _creatures.is_empty():
		_set_status("Aggiungi prima una creatura dal bestiario.")
		return

	_selected_link_token = selected[0]
	_selected_creature_selector.clear()
	var selected_index := 0
	for creature: Dictionary in _creatures:
		var label := _roster_label(creature)
		_selected_creature_selector.add_item(label)
		var item_index := _selected_creature_selector.item_count - 1
		_selected_creature_selector.set_item_metadata(
			item_index,
			String(creature.get("id", ""))
		)
		if String(creature.get("id", "")) == _current_id:
			selected_index = item_index
	_selected_creature_selector.select(selected_index)
	_selected_token_info.text = (
		"Token selezionato: %s\nScegli la creatura da collegare."
		% _token_name(_selected_link_token)
	)
	_selected_token_dialog.reset_size()
	_selected_token_dialog.popup_centered_clamped(
		Vector2i(540, 250),
		0.92
	)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "MasterAreaPanel"
	_panel.anchor_left = 0.08
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.985
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 4.0
	_panel.offset_top = 8.0
	_panel.offset_right = -4.0
	_panel.offset_bottom = -8.0
	_panel.clip_contents = true
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.hide()
	ui_root.add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.028, 0.036, 0.98)
	style.border_color = Color(0.62, 0.34, 0.22, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", style)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 7)
	_panel.add_child(outer)

	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := Label.new()
	title.text = "Area Master"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var refresh := Button.new()
	refresh.text = "Aggiorna bestiario"
	refresh.tooltip_text = "Ricarica gli indici di 5eTools dalla rete"
	refresh.pressed.connect(_refresh_catalog)
	header.add_child(refresh)
	var close := Button.new()
	close.text = "Chiudi"
	close.pressed.connect(hide_panel)
	header.add_child(close)

	_status_label = Label.new()
	_status_label.modulate = Color(0.84, 0.79, 0.70, 1.0)
	outer.add_child(_status_label)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 330
	outer.add_child(split)

	var catalog_column := VBoxContainer.new()
	catalog_column.custom_minimum_size = Vector2(310, 0)
	catalog_column.add_theme_constant_override("separation", 6)
	split.add_child(catalog_column)

	var catalog_title := Label.new()
	catalog_title.text = "Bestiario 5eTools"
	catalog_title.add_theme_font_size_override("font_size", 17)
	catalog_column.add_child(catalog_title)

	_bestiary_filter = LineEdit.new()
	_bestiary_filter.placeholder_text = "Cerca creatura o fonte…"
	_bestiary_filter.clear_button_enabled = true
	_bestiary_filter.text_changed.connect(_filter_catalog)
	catalog_column.add_child(_bestiary_filter)

	_bestiary_list = ItemList.new()
	_bestiary_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bestiary_list.select_mode = ItemList.SELECT_SINGLE
	_bestiary_list.item_activated.connect(_add_enemy_from_index)
	catalog_column.add_child(_bestiary_list)

	var catalog_buttons := HBoxContainer.new()
	catalog_column.add_child(catalog_buttons)
	var enemy_add := Button.new()
	enemy_add.text = "+ Nemico"
	enemy_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_add.pressed.connect(_add_selected_bestiary.bind("enemy"))
	catalog_buttons.add_child(enemy_add)
	var ally_add := Button.new()
	ally_add.text = "+ Alleato"
	ally_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ally_add.pressed.connect(_add_selected_bestiary.bind("ally"))
	catalog_buttons.add_child(ally_add)

	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_split.split_offset = 290
	split.add_child(right_split)

	var roster_column := VBoxContainer.new()
	roster_column.custom_minimum_size = Vector2(270, 0)
	roster_column.add_theme_constant_override("separation", 5)
	right_split.add_child(roster_column)

	_add_roster_section(roster_column, "Nemici", "enemy")
	_add_roster_section(roster_column, "Alleati", "ally")

	var roster_buttons := GridContainer.new()
	roster_buttons.columns = 2
	roster_column.add_child(roster_buttons)

	var pdf_enemy := Button.new()
	pdf_enemy.text = "+ PDF nemico…"
	pdf_enemy.tooltip_text = "Importa uno stat block da PDF nei Nemici"
	pdf_enemy.pressed.connect(_request_pdf_import.bind("enemy"))
	roster_buttons.add_child(pdf_enemy)

	var pdf_ally := Button.new()
	pdf_ally.text = "+ PDF alleato…"
	pdf_ally.tooltip_text = "Importa uno stat block da PDF negli Alleati"
	pdf_ally.pressed.connect(_request_pdf_import.bind("ally"))
	roster_buttons.add_child(pdf_ally)

	var link_selected := Button.new()
	link_selected.text = "Token → creatura"
	link_selected.tooltip_text = "Collega il token selezionato a una creatura"
	link_selected.pressed.connect(request_link_creature_to_selected_token)
	roster_buttons.add_child(link_selected)

	var link_named := Button.new()
	link_named.text = "Creatura → token…"
	link_named.tooltip_text = "Collega la creatura corrente a un token con nome"
	link_named.pressed.connect(request_link_selected_creature_to_named_token)
	roster_buttons.add_child(link_named)

	var delete := Button.new()
	delete.text = "Rimuovi"
	delete.pressed.connect(_delete_current_creature)
	roster_buttons.add_child(delete)

	var side_toggle := Button.new()
	side_toggle.text = "Nemico ↔ Alleato"
	side_toggle.pressed.connect(_toggle_current_side)
	roster_buttons.add_child(side_toggle)

	var sheet_column := VBoxContainer.new()
	sheet_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet_column.add_theme_constant_override("separation", 7)
	right_split.add_child(sheet_column)

	var sheet_title := Label.new()
	sheet_title.text = "Scheda creatura"
	sheet_title.add_theme_font_size_override("font_size", 17)
	sheet_column.add_child(sheet_title)

	var identity := GridContainer.new()
	identity.columns = 2
	identity.add_theme_constant_override("h_separation", 8)
	identity.add_theme_constant_override("v_separation", 5)
	sheet_column.add_child(identity)

	_add_label(identity, "Nome")
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Nome / soprannome"
	_name_edit.custom_minimum_size = Vector2(260, 34)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(
		func(_value: String) -> void:
			_save_current_fields()
	)
	_name_edit.focus_exited.connect(_save_current_fields)
	identity.add_child(_name_edit)

	_add_label(identity, "PF attuali")
	_current_hp = _hp_spin()
	_current_hp.value_changed.connect(
		func(_value: float) -> void:
			_save_current_fields()
	)
	identity.add_child(_current_hp)

	_add_label(identity, "PF massimi")
	_max_hp = _hp_spin()
	_max_hp.min_value = 0
	_max_hp.value_changed.connect(
		func(_value: float) -> void:
			_save_current_fields()
	)
	identity.add_child(_max_hp)

	_linked_token_label = Label.new()
	_linked_token_label.text = "Token collegato: nessuno"
	_linked_token_label.modulate = Color(0.76, 0.80, 0.86, 1.0)
	sheet_column.add_child(_linked_token_label)

	_stat_block = RichTextLabel.new()
	_stat_block.bbcode_enabled = true
	_stat_block.fit_content = false
	_stat_block.scroll_active = true
	_stat_block.selection_enabled = true
	_stat_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_block.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stat_block.add_theme_constant_override("line_separation", 5)
	_stat_block.add_theme_font_size_override("normal_font_size", 16)
	_stat_block.add_theme_font_size_override("bold_font_size", 16)

	var stat_style := StyleBoxFlat.new()
	stat_style.bg_color = Color(0.018, 0.021, 0.028, 0.72)
	stat_style.border_color = Color(0.19, 0.21, 0.26, 0.9)
	stat_style.set_border_width_all(1)
	stat_style.set_corner_radius_all(6)
	stat_style.content_margin_left = 14
	stat_style.content_margin_right = 14
	stat_style.content_margin_top = 12
	stat_style.content_margin_bottom = 14
	_stat_block.add_theme_stylebox_override("normal", stat_style)
	sheet_column.add_child(_stat_block)

	_set_form_enabled(false)


func _add_roster_section(parent: VBoxContainer, title_text: String, side: String) -> void:
	var label := Label.new()
	label.text = title_text
	label.add_theme_font_size_override("font_size", 15)
	parent.add_child(label)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 150)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.select_mode = ItemList.SELECT_SINGLE
	list.item_selected.connect(_on_roster_selected.bind(side))
	parent.add_child(list)
	if side == "enemy":
		_enemy_list = list
	else:
		_ally_list = list


func _build_token_dialog() -> void:
	_token_dialog = ConfirmationDialog.new()
	_token_dialog.title = "Collega creatura a token"
	_token_dialog.ok_button_text = "Collega"
	_token_dialog.confirmed.connect(_confirm_named_token_link)
	ui_root.add_child(_token_dialog)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_token_dialog.add_child(box)
	_token_info = Label.new()
	_token_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_token_info)
	_token_selector = OptionButton.new()
	_token_selector.custom_minimum_size = Vector2(430, 34)
	box.add_child(_token_selector)


func _build_selected_token_dialog() -> void:
	_selected_token_dialog = ConfirmationDialog.new()
	_selected_token_dialog.title = "Collega token a creatura"
	_selected_token_dialog.ok_button_text = "Collega"
	_selected_token_dialog.confirmed.connect(_confirm_selected_token_link)
	ui_root.add_child(_selected_token_dialog)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_selected_token_dialog.add_child(box)
	_selected_token_info = Label.new()
	_selected_token_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_selected_token_info)
	_selected_creature_selector = OptionButton.new()
	_selected_creature_selector.custom_minimum_size = Vector2(450, 34)
	box.add_child(_selected_creature_selector)


func _build_pdf_dialog() -> void:
	_pdf_dialog = FileDialog.new()
	_pdf_dialog.name = "MasterPDFStatblockDialog"
	_pdf_dialog.title = "Importa stat block PDF"
	_pdf_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_pdf_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_pdf_dialog.filters = PackedStringArray(["*.pdf ; PDF"])
	_pdf_dialog.use_native_dialog = true
	_pdf_dialog.file_selected.connect(_on_pdf_selected)
	ui_root.add_child(_pdf_dialog)


func _request_pdf_import(side: String) -> void:
	_pending_pdf_side = "ally" if side == "ally" else "enemy"
	_pdf_dialog.title = (
		"Importa PDF come Alleato"
		if _pending_pdf_side == "ally"
		else "Importa PDF come Nemico"
	)
	_pdf_dialog.popup_centered_ratio(0.72)


func _on_pdf_selected(path: String) -> void:
	if _pdf_importer == null:
		_set_status("Importatore PDF non disponibile.")
		return

	var destination := (
		"Alleati" if _pending_pdf_side == "ally" else "Nemici"
	)
	_set_status("Lettura dello stat block PDF…")
	# Give the native dialog one frame to close before the blocking extractor
	# runs. Normal text PDFs finish almost immediately; OCR may take longer.
	await get_tree().process_frame

	var result: Dictionary = _pdf_importer.call("import_pdf", path)
	if not bool(result.get("ok", false)):
		_set_status(
			"Importazione PDF fallita: "
			+ String(result.get("message", "errore sconosciuto"))
		)
		return

	var stat_value: Variant = result.get("stat_block", {})
	if not stat_value is Dictionary:
		_set_status("Il PDF non ha prodotto una scheda valida.")
		return

	var stat := (stat_value as Dictionary).duplicate(true)
	stat["_pdf_filename"] = path.get_file()
	_append_stat_block_creature(stat, _pending_pdf_side)

	var method := String(result.get("method", "")).strip_edges()
	var warning := String(result.get("warning", "")).strip_edges()
	var message := "%s importato in %s" % [
		String(stat.get("name", "Creatura")),
		destination,
	]
	if not method.is_empty():
		message += " · " + method
	if not warning.is_empty():
		message += " · " + warning
	_set_status(message)


func _refresh_catalog() -> void:
	_set_status("Aggiornamento bestiario 5eTools…")
	_client.call("load_catalog", true)


func _on_catalog_ready(entries: Array[Dictionary]) -> void:
	_catalog = entries
	_filter_catalog(_bestiary_filter.text if _bestiary_filter != null else "")
	_set_status("%d creature disponibili nel bestiario 5eTools." % _catalog.size())


func _on_catalog_failed(message: String) -> void:
	_set_status(message)


func _filter_catalog(query: String) -> void:
	if _bestiary_list == null:
		return
	_bestiary_list.clear()
	var needle := query.strip_edges().to_lower()
	for entry: Dictionary in _catalog:
		var entry_name := String(entry.get("name", ""))
		var source := String(entry.get("source", ""))
		if (
			not needle.is_empty()
			and needle not in entry_name.to_lower()
			and needle not in source.to_lower()
		):
			continue
		_bestiary_list.add_item("%s  ·  %s" % [entry_name, source])
		_bestiary_list.set_item_metadata(
			_bestiary_list.item_count - 1,
			entry.duplicate(true)
		)


func _add_enemy_from_index(index: int) -> void:
	_bestiary_list.select(index)
	_add_selected_bestiary("enemy")


func _add_selected_bestiary(side: String) -> void:
	var selected := _bestiary_list.get_selected_items()
	if selected.is_empty():
		_set_status("Seleziona prima una creatura nel bestiario.")
		return
	var metadata: Variant = _bestiary_list.get_item_metadata(selected[0])
	if not metadata is Dictionary:
		return
	var entry: Dictionary = metadata as Dictionary
	var request_key := "add_%d" % Time.get_ticks_usec()
	_pending_side_by_request[request_key] = side
	_set_status(
		"Caricamento scheda di %s…"
		% String(entry.get("name", "Creatura"))
	)
	_client.call(
		"request_creature",
		String(entry.get("name", "")),
		String(entry.get("source", "")),
		request_key
	)


func _on_creature_ready(request_key: String, stat: Dictionary) -> void:
	var side := String(_pending_side_by_request.get(request_key, "enemy"))
	_pending_side_by_request.erase(request_key)
	var creature := _append_stat_block_creature(stat, side)
	_set_status(
		"%s aggiunto a %s."
		% [
			String(creature.get("name", "Creatura")),
			"Alleati" if side == "ally" else "Nemici"
		]
	)


func _append_stat_block_creature(
	stat: Dictionary,
	side: String
) -> Dictionary:
	var creature: Dictionary = _store.call(
		"create_creature",
		stat,
		side
	)
	_creatures.append(creature)
	_store.call("save_creatures", _creatures)
	_current_id = String(creature.get("id", ""))
	_refresh_rosters()
	_load_current_form()
	return creature


func _on_creature_failed(request_key: String, message: String) -> void:
	_pending_side_by_request.erase(request_key)
	_set_status(message)


func _reload_creatures() -> void:
	_creatures.clear()
	var raw: Variant = _store.call("list_creatures")
	if raw is Array:
		for item: Variant in (raw as Array):
			if item is Dictionary:
				_creatures.append(item as Dictionary)
	_refresh_rosters()
	call_deferred("_sync_all_linked_health_bars")


func _refresh_rosters() -> void:
	_enemy_list.clear()
	_ally_list.clear()
	for creature: Dictionary in _creatures:
		var target: ItemList = (
			_ally_list
			if String(creature.get("side", "enemy")) == "ally"
			else _enemy_list
		)
		target.add_item(_roster_label(creature))
		target.set_item_metadata(
			target.item_count - 1,
			String(creature.get("id", ""))
		)

	if _current_id.is_empty():
		_clear_form()
		return
	_select_roster_id(_current_id)


func _roster_label(creature: Dictionary) -> String:
	var label := String(creature.get("name", "Creatura")).strip_edges()
	if label.is_empty():
		label = "Creatura senza nome"
	var hp := "%d/%d PF" % [
		int(creature.get("current_hp", 0)),
		int(creature.get("max_hp", 0))
	]
	label += "  ·  " + hp
	var token_name := String(creature.get("linked_token_name", "")).strip_edges()
	if not token_name.is_empty():
		label += "  [↔ %s]" % token_name
	return label


func _on_roster_selected(index: int, side: String) -> void:
	var list := _ally_list if side == "ally" else _enemy_list
	if index < 0 or index >= list.item_count:
		return
	_save_current_fields()
	_current_id = String(list.get_item_metadata(index))
	if side == "ally":
		_enemy_list.deselect_all()
	else:
		_ally_list.deselect_all()
	_load_current_form()


func _select_roster_id(creature_id: String) -> void:
	for list: ItemList in [_enemy_list, _ally_list]:
		for index: int in range(list.item_count):
			if String(list.get_item_metadata(index)) == creature_id:
				list.select(index)
				if list == _enemy_list:
					_ally_list.deselect_all()
				else:
					_enemy_list.deselect_all()
				return


func _current_creature() -> Dictionary:
	var index := _index_by_id(_current_id)
	if index < 0:
		return {}
	return _creatures[index]


func _load_current_form() -> void:
	var creature := _current_creature()
	if creature.is_empty():
		_clear_form()
		return
	_loading_form = true
	_set_form_enabled(true)
	_name_edit.text = String(creature.get("name", ""))
	_current_hp.value = int(creature.get("current_hp", 0))
	_max_hp.value = int(creature.get("max_hp", 0))
	var token_name := String(creature.get("linked_token_name", "")).strip_edges()
	_linked_token_label.text = (
		"Token collegato: " + token_name
		if not token_name.is_empty()
		else "Token collegato: nessuno"
	)
	var stat_value: Variant = creature.get("stat_block", {})
	_stat_block.text = (
		_build_stat_block_text(stat_value as Dictionary)
		if stat_value is Dictionary
		else "Scheda 5eTools non disponibile."
	)
	_stat_block.call_deferred("scroll_to_line", 0)
	_loading_form = false


func _save_current_fields() -> void:
	if _loading_form:
		return
	var index := _index_by_id(_current_id)
	if index < 0:
		return
	var creature: Dictionary = _creatures[index].duplicate(true)
	creature["name"] = _name_edit.text.strip_edges()
	if String(creature["name"]).is_empty():
		creature["name"] = String(creature.get("base_name", "Creatura"))
	creature["current_hp"] = int(_current_hp.value)
	creature["max_hp"] = int(_max_hp.value)
	_creatures[index] = creature
	_store.call("save_creatures", _creatures)
	_sync_creature_token(String(creature.get("id", "")))
	_refresh_roster_labels_only()


func _refresh_roster_labels_only() -> void:
	for list: ItemList in [_enemy_list, _ally_list]:
		for item_index: int in range(list.item_count):
			var creature_id := String(list.get_item_metadata(item_index))
			var creature_index := _index_by_id(creature_id)
			if creature_index >= 0:
				list.set_item_text(
					item_index,
					_roster_label(_creatures[creature_index])
				)


func _toggle_current_side() -> void:
	var index := _index_by_id(_current_id)
	if index < 0:
		return
	_save_current_fields()
	var creature := _creatures[index].duplicate(true)
	creature["side"] = (
		"ally"
		if String(creature.get("side", "enemy")) == "enemy"
		else "enemy"
	)
	_creatures[index] = creature
	_store.call("save_creatures", _creatures)
	_sync_creature_token(_current_id)
	_refresh_rosters()
	_load_current_form()


func _delete_current_creature() -> void:
	var index := _index_by_id(_current_id)
	if index < 0:
		return
	var creature_id := _current_id
	_unlink_creature_tokens(creature_id)
	_creatures.remove_at(index)
	_current_id = ""
	_store.call("save_creatures", _creatures)
	_refresh_rosters()
	_clear_form()
	_set_status("Creatura rimossa dall'Area Master.")


func _confirm_named_token_link() -> void:
	var creature := _current_creature()
	if creature.is_empty() or _token_selector.selected < 0:
		return
	var instance_id := int(
		_token_selector.get_item_metadata(_token_selector.selected)
	)
	var token_value: Object = instance_from_id(instance_id)
	if not token_value is CharacterBody3D:
		_set_status("Il token scelto non è più disponibile.")
		return
	_link_creature_to_token(
		String(creature.get("id", "")),
		token_value as CharacterBody3D
	)


func _confirm_selected_token_link() -> void:
	if (
		_selected_link_token == null
		or not is_instance_valid(_selected_link_token)
		or _selected_creature_selector.selected < 0
	):
		_set_status("Il token selezionato non è più disponibile.")
		return
	var creature_id := String(
		_selected_creature_selector.get_item_metadata(
			_selected_creature_selector.selected
		)
	)
	_link_creature_to_token(creature_id, _selected_link_token)
	_selected_link_token = null


func _link_creature_to_token(
	creature_id: String,
	token: CharacterBody3D
) -> void:
	var index := _index_by_id(creature_id)
	if index < 0 or token == null or not is_instance_valid(token):
		return
	if token.has_meta("player_character_id"):
		_set_status(
			"Questo token è già collegato a un personaggio dell'Area Player."
		)
		return

	_save_current_fields()
	_unlink_creature_tokens(creature_id)

	if token.has_meta("master_creature_id"):
		var old_id := String(token.get_meta("master_creature_id"))
		var old_index := _index_by_id(old_id)
		if old_index >= 0 and old_id != creature_id:
			_creatures[old_index]["linked_token_sync_id"] = ""
			_creatures[old_index]["linked_token_name"] = ""

	var creature: Dictionary = _creatures[index].duplicate(true)
	token.set_meta("master_creature_id", creature_id)
	token.set_meta("master_creature_name", String(creature.get("name", "")))
	token.set_meta("master_creature_side", String(creature.get("side", "enemy")))

	var sync_id := ""
	var sync: Node = board_root.get("board_sync") as Node
	if sync != null and is_instance_valid(sync):
		if sync.has_method("get_sync_id_for_node"):
			sync_id = String(sync.call("get_sync_id_for_node", token))

	creature["linked_token_sync_id"] = sync_id
	creature["linked_token_name"] = _token_name(token)
	_creatures[index] = creature
	_store.call("save_creatures", _creatures)
	_current_id = creature_id
	_sync_creature_token(creature_id)
	_refresh_rosters()
	_load_current_form()
	_set_status(
		"%s collegato a %s."
		% [String(creature.get("name", "Creatura")), _token_name(token)]
	)


func _unlink_creature_tokens(creature_id: String) -> void:
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			node.has_meta("master_creature_id")
			and String(node.get_meta("master_creature_id")) == creature_id
		):
			node.remove_meta("master_creature_id")
			node.remove_meta("master_creature_name")
			node.remove_meta("master_creature_side")
			if node.has_method("clear_master_hit_points"):
				node.call("clear_master_hit_points")


func _sync_creature_token(creature_id: String) -> void:
	var index := _index_by_id(creature_id)
	if index < 0:
		return
	var creature: Dictionary = _creatures[index]
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			node.has_meta("master_creature_id")
			and String(node.get_meta("master_creature_id")) == creature_id
		):
			node.set_meta(
				"master_creature_name",
				String(creature.get("name", ""))
			)
			node.set_meta(
				"master_creature_side",
				String(creature.get("side", "enemy"))
			)
			if node.has_method("set_master_hit_points"):
				node.call(
					"set_master_hit_points",
					int(creature.get("current_hp", 0)),
					int(creature.get("max_hp", 0))
				)


func _sync_all_linked_health_bars() -> void:
	for creature: Dictionary in _creatures:
		_sync_creature_token(String(creature.get("id", "")))


func get_owned_health_bar_sync_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for creature: Dictionary in _creatures:
		var token_id := String(
			creature.get("linked_token_sync_id", "")
		).strip_edges()
		if token_id.is_empty():
			continue
		var max_hp := maxi(0, int(creature.get("max_hp", 0)))
		if max_hp <= 0:
			continue
		var current_hp := clampi(
			int(creature.get("current_hp", 0)),
			0,
			max_hp
		)
		entries.append({
			"token_id": token_id,
			"percent": clampi(
				roundi(float(current_hp) / float(max_hp) * 100.0),
				0,
				100
			)
		})
	return entries


func _clear_form() -> void:
	_loading_form = true
	_name_edit.clear()
	_current_hp.value = 0
	_max_hp.value = 0
	_linked_token_label.text = "Token collegato: nessuno"
	_stat_block.text = "Seleziona una creatura da Nemici o Alleati."
	_set_form_enabled(false)
	_loading_form = false


func _set_form_enabled(enabled: bool) -> void:
	if _name_edit != null:
		_name_edit.editable = enabled
	if _current_hp != null:
		_current_hp.editable = enabled
	if _max_hp != null:
		_max_hp.editable = enabled


func _index_by_id(creature_id: String) -> int:
	for index: int in range(_creatures.size()):
		if String(_creatures[index].get("id", "")) == creature_id:
			return index
	return -1


func _selected_tokens() -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	if board_root.has_method("get_selected_tokens_for_master_area"):
		var value: Variant = board_root.call(
			"get_selected_tokens_for_master_area"
		)
		if value is Array:
			for item: Variant in (value as Array):
				if item is CharacterBody3D:
					result.append(item as CharacterBody3D)
	return result


func _named_scene_tokens() -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			node is CharacterBody3D
			and board_root.is_ancestor_of(node)
			and not _display_token_name(node as CharacterBody3D).is_empty()
		):
			result.append(node as CharacterBody3D)
	result.sort_custom(
		func(a: CharacterBody3D, b: CharacterBody3D) -> bool:
			return _display_token_name(a).naturalnocasecmp_to(
				_display_token_name(b)
			) < 0
	)
	return result


func _display_token_name(token: CharacterBody3D) -> String:
	if token != null and is_instance_valid(token):
		if token.has_method("get_display_name"):
			return String(token.call("get_display_name")).strip_edges()
	return ""


func _token_name(token: CharacterBody3D) -> String:
	var display := _display_token_name(token)
	return display if not display.is_empty() else "Token senza nome"


func _build_stat_block_text(stat: Dictionary) -> String:
	if stat.is_empty():
		return "Scheda 5eTools non disponibile."

	var out := PackedStringArray()
	var source := String(stat.get("source", ""))
	var base_name := String(stat.get("name", "Creatura"))
	var imported_pdf := bool(stat.get("_imported_pdf", false))
	out.append("[font_size=22][b]%s[/b][/font_size]" % _escape_bb(base_name))
	if imported_pdf:
		var pdf_filename := String(
			stat.get(
				"_pdf_filename",
				stat.get("_pdf_name", "stat block.pdf")
			)
		)
		out.append(
			"[color=#c89b4a]PDF importato · %s[/color]"
			% _escape_bb(pdf_filename)
		)
	else:
		out.append(
			"[color=#c89b4a]%s · pagina %d[/color]"
			% [_escape_bb(source), int(stat.get("page", 0))]
		)

	var size := _size_text(stat.get("size", ""))
	var type := _type_text(stat.get("type", ""))
	var alignment := _plain_value(stat.get("alignment", ""))
	out.append(
		"[i]%s %s%s[/i]"
		% [
			_escape_bb(size),
			_escape_bb(type),
			", " + _escape_bb(alignment) if not alignment.is_empty() else ""
		]
	)
	out.append("")

	out.append(
		"[color=#aeb7c5][b]CA[/b][/color] %s"
		% _escape_bb(_plain_value(stat.get("ac", "")))
	)
	out.append(
		"[color=#aeb7c5][b]PF[/b][/color] %s"
		% _escape_bb(_hp_text(stat.get("hp", {})))
	)
	out.append(
		"[color=#aeb7c5][b]Velocità[/b][/color] %s"
		% _escape_bb(_plain_value(stat.get("speed", "")))
	)
	out.append("")

	var ability_line := PackedStringArray()
	for ability: String in ["str", "dex", "con", "int", "wis", "cha"]:
		if stat.has(ability):
			var score := int(stat.get(ability, 10))
			var mod := int(floor((score - 10) / 2.0))
			ability_line.append(
				"%s %d (%s%d)"
				% [
					ability.to_upper(),
					score,
					"+" if mod >= 0 else "",
					mod
				]
			)
	out.append("[b]%s[/b]" % "   ".join(ability_line))
	out.append("")

	_append_field(out, "Tiri salvezza", stat, "save")
	_append_field(out, "Abilità", stat, "skill")
	_append_field(out, "Vulnerabilità", stat, "vulnerable")
	_append_field(out, "Resistenze", stat, "resist")
	_append_field(out, "Immunità ai danni", stat, "immune")
	_append_field(out, "Immunità condizioni", stat, "conditionImmune")
	_append_field(out, "Sensi", stat, "senses")
	if stat.has("passive"):
		out.append("[b]Percezione passiva[/b] %s" % stat.get("passive"))
	_append_field(out, "Linguaggi", stat, "languages")
	_append_field(out, "GS", stat, "cr")
	if stat.has("pbNote"):
		out.append("[b]Bonus competenza[/b] %s" % _escape_bb(
			_plain_value(stat.get("pbNote"))
		))
	out.append("")

	var section_map := [
		["Tratti", "trait"],
		["Incantesimi", "spellcasting"],
		["Azioni", "action"],
		["Azioni bonus", "bonus"],
		["Reazioni", "reaction"],
		["Azioni leggendarie", "legendary"],
		["Azioni mitiche", "mythic"],
		["Azioni di tana", "lairActions"],
		["Effetti regionali", "regionalEffects"],
		["Varianti", "variant"]
	]
	for section: Array in section_map:
		var key := String(section[1])
		if stat.has(key):
			_append_stat_section(
				out,
				String(section[0]),
				stat.get(key)
			)

	var consumed := {
		"name": true, "source": true, "page": true, "size": true,
		"type": true, "alignment": true, "ac": true, "hp": true,
		"speed": true, "str": true, "dex": true, "con": true,
		"int": true, "wis": true, "cha": true, "save": true,
		"skill": true, "vulnerable": true, "resist": true,
		"immune": true, "conditionImmune": true, "senses": true,
		"passive": true, "languages": true, "cr": true, "pbNote": true,
		"trait": true, "spellcasting": true, "action": true,
		"bonus": true, "reaction": true, "legendary": true,
		"mythic": true, "lairActions": true, "regionalEffects": true,
		"variant": true, "raw_text": true
	}
	var extras := PackedStringArray()
	for key_value: Variant in stat.keys():
		var key := String(key_value)
		if consumed.has(key) or key.begins_with("_"):
			continue
		var text := _plain_value(stat.get(key_value))
		if not text.is_empty():
			extras.append("[b]%s[/b] %s" % [
				_escape_bb(key),
				_escape_bb(text)
			])
	if stat.has("_copy"):
		extras.append(
			"[b]Ereditarietà 5eTools[/b] %s"
			% _escape_bb(_plain_value(stat.get("_copy")))
		)
	if not extras.is_empty():
		out.append(
			"[font_size=16][color=#a8a8a8][b]Dati aggiuntivi[/b][/color][/font_size]"
		)
		out.append("\n".join(extras))

	return "\n".join(out)


func _append_stat_section(
	out: PackedStringArray,
	label: String,
	value: Variant
) -> void:
	if _plain_value(value).is_empty():
		return

	out.append("")
	out.append(
		"[font_size=18][color=#d49b42][b]%s[/b][/color][/font_size]"
		% _escape_bb(label)
	)

	if value is Array:
		var entries: Array = value as Array
		for item: Variant in entries:
			var rendered := _render_stat_section_entry(item)
			if rendered.is_empty():
				continue
			out.append(rendered)
			out.append("")
		return

	var rendered_single := _render_stat_section_entry(value)
	if not rendered_single.is_empty():
		out.append(rendered_single)
		out.append("")


func _render_stat_section_entry(value: Variant) -> String:
	if value is Dictionary:
		var data: Dictionary = value as Dictionary
		var entry_name := _plain_value(data.get("name", "")).strip_edges()
		var body := _section_entry_body(data)
		if not entry_name.is_empty():
			var heading := "[b]%s[/b]" % _escape_bb(entry_name)
			if not heading.ends_with("."):
				heading += "."
			if body.is_empty():
				return heading
			return "%s  %s" % [heading, _escape_bb(body)]
		return _escape_bb(body)

	if value is Array:
		var blocks := PackedStringArray()
		for nested: Variant in value as Array:
			var rendered := _render_stat_section_entry(nested)
			if not rendered.is_empty():
				blocks.append(rendered)
		return "\n\n".join(blocks)

	return _escape_bb(_plain_value(value))


func _section_entry_body(data: Dictionary) -> String:
	var entries_value: Variant = data.get("entries", null)
	if entries_value == null:
		return _plain_value(data)

	if entries_value is Array:
		var paragraphs := PackedStringArray()
		for entry_value: Variant in entries_value as Array:
			var paragraph := _plain_value(entry_value).strip_edges()
			if not paragraph.is_empty():
				paragraphs.append(paragraph)
		return "\n".join(paragraphs)

	return _plain_value(entries_value).strip_edges()


func _append_field(
	out: PackedStringArray,
	label: String,
	stat: Dictionary,
	key: String
) -> void:
	if not stat.has(key):
		return
	var text := _plain_value(stat.get(key))
	if text.is_empty():
		return
	out.append("[b]%s[/b] %s" % [_escape_bb(label), _escape_bb(text)])


func _hp_text(value: Variant) -> String:
	if not value is Dictionary:
		return _plain_value(value)
	var hp: Dictionary = value as Dictionary
	if hp.has("average"):
		var text := str(hp.get("average"))
		if hp.has("formula"):
			text += " (" + String(hp.get("formula")) + ")"
		return text
	return _plain_value(hp)


func _size_text(value: Variant) -> String:
	var code := _plain_value(value)
	var map := {
		"T": "Tiny", "S": "Small", "M": "Medium",
		"L": "Large", "H": "Huge", "G": "Gargantuan"
	}
	return String(map.get(code, code))


func _type_text(value: Variant) -> String:
	if value is String:
		return String(value)
	if value is Dictionary:
		var data: Dictionary = value as Dictionary
		var base := String(data.get("type", ""))
		var tags := _plain_value(data.get("tags", []))
		return base + (" (" + tags + ")" if not tags.is_empty() else "")
	return _plain_value(value)


func _plain_value(value: Variant) -> String:
	if value == null:
		return ""
	if value is String:
		return _strip_5etools_tags(String(value))
	if value is bool or value is int or value is float:
		return str(value)
	if value is Array:
		var parts := PackedStringArray()
		for item: Variant in (value as Array):
			var text := _plain_value(item)
			if not text.is_empty():
				parts.append(text)
		return "; ".join(parts)
	if value is Dictionary:
		var data: Dictionary = value as Dictionary
		if data.has("name") and data.has("entries"):
			var heading := _plain_value(data.get("name"))
			var entries := _plain_value(data.get("entries"))
			return heading + (": " + entries if not entries.is_empty() else "")
		if data.has("entries"):
			return _plain_value(data.get("entries"))
		var parts := PackedStringArray()
		for key_value: Variant in data.keys():
			var key := String(key_value)
			if key.begins_with("_"):
				continue
			var text := _plain_value(data.get(key_value))
			if not text.is_empty():
				parts.append("%s: %s" % [key, text])
		return ", ".join(parts)
	return str(value)


func _strip_5etools_tags(text: String) -> String:
	var result := text.replace("{@h}", "Hit: ")
	var regex := RegEx.new()
	if regex.compile("\\{@([A-Za-z]+) ([^{}]+)\\}") != OK:
		return result
	for _iteration: int in range(12):
		var hit := regex.search(result)
		if hit == null:
			break
		var tag := hit.get_string(1).to_lower()
		var payload := hit.get_string(2)
		var first := payload.split("|", false)[0]
		var replacement := String(first)
		match tag:
			"hit":
				replacement = (
					replacement
					if replacement.begins_with("-")
					else "+" + replacement
				)
			"dc":
				replacement = "DC " + replacement
			"recharge":
				replacement = "Recharge " + replacement
			"atk":
				var attacks := {
					"mw": "Melee Weapon Attack",
					"rw": "Ranged Weapon Attack",
					"ms": "Melee Spell Attack",
					"rs": "Ranged Spell Attack",
					"mw,rw": "Melee or Ranged Weapon Attack"
				}
				replacement = String(attacks.get(replacement, replacement))
		result = (
			result.substr(0, hit.get_start())
			+ replacement
			+ result.substr(hit.get_end())
		)
	return result


func _escape_bb(text: String) -> String:
	return text.replace("[", "［").replace("]", "］")


func _hp_spin() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -9999
	spin.max_value = 99999
	spin.step = 1
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.custom_minimum_size = Vector2(130, 32)
	return spin


func _add_label(parent: Control, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	parent.add_child(label)


func _campaign_manager() -> Node:
	return get_node_or_null("/root/CampaignManager")


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
