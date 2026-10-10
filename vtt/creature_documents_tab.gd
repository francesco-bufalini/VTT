extends VBoxContainer

# Documents are homebrew catalog items owned by the creature. Only their
# addition date and preferred display style belong to the live inventory.
const DocumentStore = preload("res://vtt/document_homebrew.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")

var _on_change: Callable
var _on_status: Callable
var _inventory: Array[Dictionary] = []
var _indices: Array[int] = []
var _loading := false
var _dirty := false
var _save_revision := 0
var _active_id := ""

var _list: ItemList
var _remove_button: Button
var _dialog: AcceptDialog
var _style_picker: OptionButton
var _edit_button: Button
var _editor_panel: VBoxContainer
var _title_edit: LineEdit
var _body_edit: TextEdit
var _date_label: Label
var _viewport: SubViewport
var _paper: ColorRect
var _paper_text: Label
var _full_image: TextureRect


func setup(on_change: Callable, on_status: Callable) -> void:
	_on_change = on_change
	_on_status = on_status
	add_theme_constant_override("separation", 8)

	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	var create := Button.new()
	create.text = "+ Nuovo documento"
	create.pressed.connect(_add_document)
	toolbar.add_child(create)
	_remove_button = Button.new()
	_remove_button.text = "Elimina"
	_remove_button.disabled = true
	_remove_button.pressed.connect(_remove_document)
	toolbar.add_child(_remove_button)

	_list = ItemList.new()
	_list.custom_minimum_size.y = 210
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_select_document)
	_list.item_activated.connect(_open_document)
	add_child(_list)

	# Offscreen page canvas: a single live texture is shared with the viewer
	# and remains active even while the Documents tab is not selected.
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(640, 780)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_viewport)
	_paper = ColorRect.new()
	_paper.position = Vector2.ZERO
	_paper.size = Vector2(640, 780)
	_viewport.add_child(_paper)
	_paper_text = Label.new()
	_paper_text.position = Vector2(45, 35)
	_paper_text.size = Vector2(550, 700)
	_paper_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_paper_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_paper_text.add_theme_font_size_override("font_size", 21)
	_paper_text.add_theme_color_override("font_color", Color(0.22, 0.15, 0.10))
	_paper.add_child(_paper_text)

	_dialog = AcceptDialog.new()
	_dialog.title = "Documento"
	_dialog.get_ok_button().text = "Chiudi"
	_dialog.confirmed.connect(_flush_edit)
	_dialog.close_requested.connect(_flush_edit)
	add_child(_dialog)

	var popup_body := VBoxContainer.new()
	popup_body.add_theme_constant_override("separation", 8)
	_dialog.add_child(popup_body)
	var controls := HBoxContainer.new()
	popup_body.add_child(controls)
	var style_title := Label.new()
	style_title.text = "Visualizzazione"
	controls.add_child(style_title)
	_style_picker = OptionButton.new()
	_style_picker.add_item("Pergamena")
	_style_picker.add_item("Lettera")
	_style_picker.item_selected.connect(_on_style_changed)
	controls.add_child(_style_picker)
	_edit_button = Button.new()
	_edit_button.text = "Modifica"
	_edit_button.toggle_mode = true
	_edit_button.toggled.connect(_toggle_editor)
	controls.add_child(_edit_button)
	_date_label = Label.new()
	_date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.add_child(_date_label)

	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	popup_body.add_child(layout)
	_editor_panel = VBoxContainer.new()
	_editor_panel.custom_minimum_size.x = 355
	_editor_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_panel.hide()
	layout.add_child(_editor_panel)
	var name_label := Label.new()
	name_label.text = "Nome"
	_editor_panel.add_child(name_label)
	_title_edit = LineEdit.new()
	_title_edit.placeholder_text = "Titolo del documento"
	_title_edit.max_length = DocumentStore.MAX_TITLE
	_title_edit.text_changed.connect(func(_value: String) -> void: _on_editor_changed())
	_editor_panel.add_child(_title_edit)
	var content_label := Label.new()
	content_label.text = "Testo"
	_editor_panel.add_child(content_label)
	_body_edit = TextEdit.new()
	_body_edit.custom_minimum_size = Vector2(320, 550)
	_body_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_body_edit.placeholder_text = "Scrivi il testo del documento…"
	_body_edit.text_changed.connect(_on_editor_changed)
	_editor_panel.add_child(_body_edit)

	_full_image = TextureRect.new()
	_full_image.custom_minimum_size = Vector2(460, 590)
	_full_image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_full_image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_full_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_full_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_full_image.texture = _viewport.get_texture()
	layout.add_child(_full_image)
	_refresh_list()


func load_inventory(inventory: Array) -> void:
	_loading = true
	_inventory.clear()
	for raw: Variant in inventory:
		if raw is Dictionary:
			_inventory.append((raw as Dictionary).duplicate(true))
	_loading = false
	_refresh_list()


func _refresh_list() -> void:
	if _list == null:
		return
	var selected_id := _active_id
	var current: PackedInt32Array = _list.get_selected_items()
	if selected_id.is_empty() and not current.is_empty() and current[0] < _indices.size():
		selected_id = String(_inventory[_indices[current[0]]].get("id", ""))
	_indices.clear()
	_list.clear()
	var selected_index := -1
	for i: int in range(_inventory.size()):
		var item: Dictionary = _inventory[i]
		if not DocumentStore.is_document(item):
			continue
		var definition: Dictionary = DocumentStore.definition_for(item)
		var name: String = String(definition.get("name", item.get("name", "Senza titolo")))
		var position := _indices.size()
		_indices.append(i)
		_list.add_item(name)
		var unix_time: int = int(item.get("added_at", 0))
		if unix_time > 0:
			_list.set_item_tooltip(position, "Aggiunto: " + _format_date(unix_time))
		if String(item.get("id", "")) == selected_id:
			selected_index = position
	if selected_index >= 0:
		_list.select(selected_index)
	elif not _indices.is_empty():
		_list.select(0)
	_remove_button.disabled = _selected_inventory_index() < 0


func _selected_inventory_index() -> int:
	if _list == null:
		return -1
	var selected: PackedInt32Array = _list.get_selected_items()
	if selected.is_empty() or selected[0] < 0 or selected[0] >= _indices.size():
		return -1
	return _indices[selected[0]]


func _select_document(_index: int) -> void:
	_remove_button.disabled = _selected_inventory_index() < 0


func _add_document() -> void:
	_flush_edit()
	var item: Dictionary = DocumentStore.create_document()
	if item.is_empty():
		_status("Impossibile creare il file homebrew del documento.")
		return
	_inventory.append(item)
	_active_id = String(item.get("id", ""))
	_refresh_list()
	_publish()
	var selected: PackedInt32Array = _list.get_selected_items()
	if not selected.is_empty():
		_open_document(int(selected[0]))
		_edit_button.set_pressed_no_signal(true)
		_toggle_editor(true)


func _remove_document() -> void:
	_flush_edit()
	var index: int = _selected_inventory_index()
	if index < 0:
		return
	_inventory.remove_at(index)
	_active_id = ""
	_refresh_list()
	_publish()


func _open_document(index: int) -> void:
	if index < 0 or index >= _indices.size():
		return
	_flush_edit()
	_list.select(index)
	var owned_index: int = _indices[index]
	var item: Dictionary = _inventory[owned_index]
	_active_id = String(item.get("id", ""))
	var definition: Dictionary = DocumentStore.definition_for(item)
	_loading = true
	_title_edit.text = String(definition.get("name", item.get("name", "")))
	_body_edit.text = String(definition.get("description", definition.get("text", "")))
	var style: String = String(item.get("display_style", "pergamena"))
	_style_picker.select(1 if style == "lettera" else 0)
	_edit_button.set_pressed_no_signal(false)
	_editor_panel.hide()
	_loading = false
	_dirty = false
	_date_label.text = "Aggiunto: " + _format_date(int(item.get("added_at", 0)))
	_dialog.title = "Documento · " + _title_edit.text
	_update_preview()
	DialogLayout.popup(_dialog, Vector2i(690, 790), 0.90)
	_remove_button.disabled = false


func _toggle_editor(enabled: bool) -> void:
	if enabled and _selected_inventory_index() < 0:
		_edit_button.set_pressed_no_signal(false)
		return
	_editor_panel.visible = enabled
	_edit_button.text = "Termina modifica" if enabled else "Modifica"
	if not enabled:
		_flush_edit()
	if _dialog.visible:
		DialogLayout.popup(_dialog, Vector2i(1110, 830) if enabled else Vector2i(690, 790), 0.92)


func _on_style_changed(index: int) -> void:
	if _loading:
		return
	var owned_index: int = _selected_inventory_index()
	if owned_index < 0:
		return
	_inventory[owned_index]["display_style"] = "lettera" if index == 1 else "pergamena"
	_update_preview()
	_publish()


func _on_editor_changed() -> void:
	if _loading:
		return
	_dirty = true
	_update_preview()
	_save_revision += 1
	_save_later(_save_revision)


func _save_later(revision: int) -> void:
	await get_tree().create_timer(0.45).timeout
	if revision == _save_revision and _dirty and is_inside_tree():
		_flush_edit()


func _flush_edit() -> void:
	if not _dirty:
		return
	var owned_index: int = _selected_inventory_index()
	if owned_index < 0:
		return
	var item: Dictionary = _inventory[owned_index]
	var title := _title_edit.text.strip_edges()
	if title.is_empty():
		title = "Senza titolo"
	if not DocumentStore.update_definition(item, title, _body_edit.text):
		_status("Impossibile salvare la definizione homebrew del documento.")
		return
	_dirty = false
	_save_revision += 1
	_inventory[owned_index]["name"] = title
	_dialog.title = "Documento · " + title
	_refresh_list()
	_publish()


func _update_preview() -> void:
	var is_letter: bool = _style_picker.selected == 1
	_paper.color = Color(0.95, 0.90, 0.78) if is_letter else Color(0.89, 0.78, 0.58)
	# No mail emoji before the text in letter layout.
	var prefix: String = "" if is_letter else "❧  "
	_paper_text.text = prefix + _title_edit.text + "\n\n" + _body_edit.text
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _format_date(unix_time: int) -> String:
	if unix_time <= 0:
		return "Non disponibile"
	var time: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time)
	return "%02d/%02d/%04d" % [int(time.get("day", 1)), int(time.get("month", 1)), int(time.get("year", 2000))]


func _status(message: String) -> void:
	if _on_status.is_valid():
		_on_status.call(message)


func _publish() -> void:
	if not _loading and _on_change.is_valid():
		_on_change.call(_inventory.duplicate(true))
