extends VBoxContainer

# Documents are inventory items with a unique identifier and an image
# rendered locally from their title and text. No image bytes cross the network.
const Inbox = preload("res://vtt/document_inbox.gd")

var _on_change: Callable
var _on_status: Callable
var _send: Callable
var _peers: Callable
var _documents: Array[Dictionary] = []
var _loading := false
var _list: ItemList
var _title_edit: LineEdit
var _body_edit: TextEdit
var _style_picker: OptionButton
var _paper: ColorRect
var _paper_text: Label
var _viewport: SubViewport
var _preview: TextureRect
var _recipients: OptionButton
var _send_button: Button
var _remove_button: Button


func setup(on_change: Callable, on_status: Callable, send: Callable, peers: Callable) -> void:
	_on_change = on_change
	_on_status = on_status
	_send = send
	_peers = peers
	add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	add_child(header)
	var create := Button.new()
	create.text = "+ Nuovo documento"
	create.pressed.connect(_add_document)
	header.add_child(create)
	_remove_button = Button.new()
	_remove_button.text = "Elimina"
	_remove_button.pressed.connect(_remove_document)
	header.add_child(_remove_button)
	_list = ItemList.new()
	_list.custom_minimum_size.y = 132
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_select_document)
	add_child(_list)
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 5)
	add_child(fields)
	_title_edit = LineEdit.new()
	_title_edit.placeholder_text = "Titolo della lettera o del documento"
	_title_edit.max_length = 160
	_title_edit.text_changed.connect(func(_v: String) -> void: _update_document())
	fields.add_child(_title_edit)
	_style_picker = OptionButton.new()
	_style_picker.add_item("📜 Pergamena")
	_style_picker.add_item("✉ Lettera")
	_style_picker.item_selected.connect(func(_i: int) -> void: _update_document())
	fields.add_child(_style_picker)
	_body_edit = TextEdit.new()
	_body_edit.custom_minimum_size.y = 155
	_body_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_body_edit.placeholder_text = "Scrivi il testo del documento…"
	_body_edit.text_changed.connect(_update_document)
	fields.add_child(_body_edit)
	var caption := Label.new()
	caption.text = "🖼 Anteprima generata automaticamente"
	add_child(caption)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(640, 780)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	add_child(_viewport)
	_paper = ColorRect.new()
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paper.color = Color(0.90, 0.81, 0.64)
	_viewport.add_child(_paper)
	_paper_text = Label.new()
	_paper_text.position = Vector2(45, 35)
	_paper_text.size = Vector2(550, 700)
	_paper_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_paper_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_paper_text.add_theme_font_size_override("font_size", 21)
	_paper_text.add_theme_color_override("font_color", Color(0.22, 0.15, 0.10))
	_paper.add_child(_paper_text)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(0, 290)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture = _viewport.get_texture()
	add_child(_preview)
	var send_row := HBoxContainer.new()
	add_child(send_row)
	_recipients = OptionButton.new()
	_recipients.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send_row.add_child(_recipients)
	var refresh := Button.new()
	refresh.text = "↻"
	refresh.tooltip_text = "Aggiorna i giocatori online"
	refresh.pressed.connect(_refresh_peers)
	send_row.add_child(refresh)
	_send_button = Button.new()
	_send_button.text = "Invia"
	_send_button.pressed.connect(_send_document)
	send_row.add_child(_send_button)
	_refresh_peers()
	_refresh_list()


func load_record(record: Dictionary) -> void:
	_loading = true
	_documents.clear()
	var saved: Variant = record.get("documents", [])
	if saved is Array:
		for raw: Variant in saved:
			if raw is Dictionary:
				_documents.append((raw as Dictionary).duplicate(true))
	_loading = false
	_refresh_list()
	_import_inbox()


func _import_inbox() -> void:
	var incoming: Array[Dictionary] = Inbox.take_all()
	if incoming.is_empty():
		return
	for note: Dictionary in incoming:
		var exists := false
		for entry: Dictionary in _documents:
			if String(entry.get("id", "")) == String(note.get("id", "")):
				exists = true
				break
		if not exists:
			_documents.append(note.duplicate(true))
	_refresh_list(_documents.size() - 1)
	# load_record runs while its parent sheet has _loading=true.
	call_deferred("_publish")


func receive_document() -> void:
	_import_inbox()


func _add_document() -> void:
	_documents.append({
		"id": "document_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()],
		"title": "Nuovo documento", "text": "", "style": "pergamena",
		"item_type": "document"
	})
	_refresh_list(_documents.size() - 1)
	_publish()


func _remove_document() -> void:
	var index: int = _selected_index()
	if index < 0:
		return
	_documents.remove_at(index)
	_refresh_list()
	_publish()


func _selected_index() -> int:
	var selected: PackedInt32Array = _list.get_selected_items()
	return selected[0] if not selected.is_empty() else -1


func _select_document(index: int) -> void:
	if index < 0 or index >= _documents.size():
		return
	_loading = true
	var document: Dictionary = _documents[index]
	_title_edit.text = String(document.get("title", ""))
	_body_edit.text = String(document.get("text", ""))
	_style_picker.select(1 if String(document.get("style", "pergamena")) == "lettera" else 0)
	_loading = false
	_update_preview()
	_refresh_peers()
	_remove_button.disabled = false


func _refresh_list(selected_index: int = -1) -> void:
	_loading = true
	_list.clear()
	for note: Dictionary in _documents:
		_list.add_item("🖼  " + String(note.get("title", "Senza titolo")))
	if selected_index < 0 or selected_index >= _documents.size():
		selected_index = 0 if not _documents.is_empty() else -1
	if selected_index >= 0:
		_list.select(selected_index)
		_select_document(selected_index)
	else:
		_title_edit.text = ""
		_body_edit.text = ""
		_paper_text.text = ""
		_remove_button.disabled = true
	_title_edit.editable = selected_index >= 0
	_body_edit.editable = selected_index >= 0
	_style_picker.disabled = selected_index < 0
	_send_button.disabled = selected_index < 0
	_loading = false


func _update_document() -> void:
	if _loading:
		return
	var index: int = _selected_index()
	if index < 0:
		return
	_documents[index]["title"] = _title_edit.text.substr(0, 160)
	_documents[index]["text"] = _body_edit.text.substr(0, 3500)
	_documents[index]["style"] = "lettera" if _style_picker.selected == 1 else "pergamena"
	_list.set_item_text(index, "🖼  " + String(_documents[index]["title"]))
	_update_preview()
	_publish()


func _update_preview() -> void:
	var is_letter: bool = _style_picker.selected == 1
	_paper.color = Color(0.95, 0.90, 0.78) if is_letter else Color(0.89, 0.78, 0.58)
	_paper_text.text = (
		("✉  " if is_letter else "❧  ") + _title_edit.text
		+ "\n\n" + _body_edit.text
	)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _refresh_peers() -> void:
	_recipients.clear()
	if _peers.is_valid():
		var value: Variant = _peers.call()
		if value is Array:
			for candidate: Variant in value:
				if candidate is Dictionary:
					var peer: Dictionary = candidate as Dictionary
					_recipients.add_item(String(peer.get("label", "Giocatore online")))
					_recipients.set_item_metadata(_recipients.item_count - 1, String(peer.get("id", "")))
	if _recipients.item_count == 0:
		_recipients.add_item("Nessun giocatore online")
		_recipients.set_item_disabled(0, true)
		_send_button.disabled = true
	elif _selected_index() >= 0:
		_send_button.disabled = false


func _send_document() -> void:
	var index: int = _selected_index()
	if index < 0 or _recipients.selected < 0 or _recipients.is_item_disabled(_recipients.selected):
		return
	if not _send.is_valid():
		return
	var recipient_id: String = String(_recipients.get_item_metadata(_recipients.selected))
	var id: String = String(_send.call(recipient_id, _documents[index]))
	if _on_status.is_valid():
		_on_status.call(
			"Documento in spedizione · conferma di consegna in attesa"
			if not id.is_empty() else
			"Invio non riuscito: destinatario assente o documento troppo grande"
		)


func _publish() -> void:
	if not _loading and _on_change.is_valid():
		_on_change.call(_documents.duplicate(true))
