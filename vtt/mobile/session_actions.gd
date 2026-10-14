extends Node
## The mobile Partita action forms and the cached snapshot viewer.
const SnapshotView = preload("res://vtt/mobile/map_snapshot_view.gd")
const TouchLayout = preload("res://vtt/mobile/touch_layout.gd")
var shell: Control
var controller: Node
var sheet: Node
var picker: PanelContainer
var picker_title: Label
var picker_rows: VBoxContainer
var viewer: PanelContainer
var canvas: Control
var caption: Label
var reopen_button: Button
var snapshot_button: Button
var place_button: Button
var _pending_place := ""
var _pending_snapshot := ""
var _snapshot_token := ""
var _snapshot_attack: Dictionary = {}
var _field_feet := 120.0
var _cached := false

func setup(host: Control, map_controller: Node, creature_sheet: Node, column: VBoxContainer) -> void:
	shell = host
	controller = map_controller
	sheet = creature_sheet
	place_button = Button.new()
	place_button.name = "PlaceMobileToken"
	place_button.text = "Piazza token"
	place_button.pressed.connect(_choose_creature)
	column.add_child(place_button)
	snapshot_button = Button.new()
	snapshot_button.name = "RequestMapSnapshot"
	snapshot_button.text = "Richiedi snapshot"
	snapshot_button.pressed.connect(func() -> void: _choose_token(_request_selected_snapshot, "Da quale token prendere lo snapshot?"))
	column.add_child(snapshot_button)
	_build_picker()
	_build_viewer()
	reopen_button = Button.new()
	reopen_button.name = "ReopenMapSnapshot"
	reopen_button.text = "▧"
	reopen_button.tooltip_text = "Riapri l’ultimo snapshot"
	reopen_button.custom_minimum_size = Vector2(48, 48)
	reopen_button.z_index = 100
	reopen_button.disabled = true
	reopen_button.pressed.connect(_reopen_snapshot)
	shell.ui_root.add_child(reopen_button)
	controller.action_completed.connect(_on_action_completed)
	TouchLayout.style_control(reopen_button)

func _build_picker() -> void:
	picker = PanelContainer.new()
	picker.name = "MobileSessionActionPicker"
	picker.z_index = 220
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picker.offset_left = 8
	picker.offset_right = -8
	picker.offset_top = 8
	picker.offset_bottom = -8
	shell.ui_root.add_child(picker)
	var body := VBoxContainer.new()
	picker.add_child(body)
	var cancel := Button.new()
	cancel.text = "Annulla · Torna indietro"
	cancel.pressed.connect(picker.hide)
	body.add_child(cancel)
	picker_title = Label.new()
	picker_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(picker_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	picker_rows = VBoxContainer.new()
	picker_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(picker_rows)
	TouchLayout.style_tree(picker)
	picker.hide()

func _build_viewer() -> void:
	viewer = PanelContainer.new()
	viewer.name = "MobileMapSnapshot"
	viewer.z_index = 210
	viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewer.offset_left = 4
	viewer.offset_right = -4
	viewer.offset_top = 4
	viewer.offset_bottom = -4
	shell.ui_root.add_child(viewer)
	var body := VBoxContainer.new()
	viewer.add_child(body)
	var close := Button.new()
	close.text = "Chiudi snapshot"
	close.pressed.connect(viewer.hide)
	body.add_child(close)
	caption = Label.new()
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(caption)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	for spec: Array in [["Zoom +", 0.7], ["Zoom −", 1.4], ["Aggiorna", 1.0]]:
		var button := Button.new()
		button.text = String(spec[0])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_zoom_snapshot.bind(float(spec[1])))
		actions.add_child(button)
	canvas = SnapshotView.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(canvas)
	TouchLayout.style_tree(viewer)
	viewer.hide()

func _clear_picker(title: String) -> void:
	for child: Node in picker_rows.get_children():
		picker_rows.remove_child(child)
		child.queue_free()
	picker_title.text = title
	picker.show()

func _add_choice(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(callback)
	picker_rows.add_child(button)
	TouchLayout.style_control(button)

func _choose_creature() -> void:
	if not _pending_place.is_empty():
		return
	_clear_picker("Quale creatura vuoi piazzare?")
	var creatures: Array[Dictionary] = sheet.get_mobile_placement_creatures()
	for creature: Dictionary in creatures:
		_add_choice(String(creature.get("name", "Creatura")), _choose_support.bind(creature))
	if creatures.is_empty():
		picker_title.text = "Crea o importa prima una creatura nelle schede locali."

func _choose_support(creature: Dictionary) -> void:
	_choose_token(func(token_id: String) -> void:
		picker.hide()
		_pending_place = controller.request_action("place_token", {"token_id": token_id, "creature": creature})
		place_button.disabled = not _pending_place.is_empty()
		if not _pending_place.is_empty():
			shell._connection_status.text = "Piazzamento in corso…", "Sopra l’hitbox di quale token?")

func _choose_token(callback: Callable, title: String) -> void:
	_clear_picker(title)
	var data: Dictionary = controller.get_map_data()
	for token: Dictionary in data.get("tokens", []):
		_add_choice(String(token.get("name", "Token")), callback.bind(String(token.id)))
	if data.get("tokens", []).is_empty():
		picker_title.text = "Collega un desktop con una mappa e almeno un token visibile."

func _request_selected_snapshot(token_id: String) -> void:
	picker.hide()
	_snapshot_token = token_id
	_snapshot_attack = {}
	_field_feet = 120.0
	_send_snapshot()

func request_attack_snapshot(record: Dictionary, attack: Dictionary) -> void:
	var data: Dictionary = controller.get_map_data()
	var linked := String(record.get("linked_token_sync_id", ""))
	var token_id := linked
	for token: Dictionary in data.get("tokens", []):
		if String(token.id) == linked or (String(token.get("creature_id", "")) == String(record.get("id", "")) and String(token.get("owner_id", "")) == String(record.get("owner_id", ""))):
			token_id = String(token.id)
			break
	if token_id.is_empty():
		shell._show_touch_help("Usa Piazza token nella sezione Partita per collegare questa creatura alla mappa.")
		return
	_snapshot_token = token_id
	_snapshot_attack = {"range_feet": attack.get("range_feet", 5),
		"long_range_feet": attack.get("long_range_feet", 0), "melee": attack.get("melee", true)}
	_field_feet = clampf(float(attack.get("range_feet", 5)) * 2.6 + 20, 40, 1500)
	_send_snapshot()

func _reopen_snapshot() -> void:
	if not _cached:
		return
	var saved: Dictionary = canvas.snapshot
	_snapshot_token = String(saved.get("token_id", _snapshot_token))
	_field_feet = float(saved.get("field_feet", 120))
	_snapshot_attack = saved.get("attack", {}).duplicate(true)
	caption.text = "%s · campo %d ft" % [saved.get("title", "Mappa"), int(_field_feet)]
	viewer.show()

func _zoom_snapshot(factor: float) -> void:
	if not _pending_snapshot.is_empty():
		return
	_field_feet = clampf(_field_feet * factor, 20, 1500)
	_send_snapshot()

func _send_snapshot() -> void:
	_pending_snapshot = controller.request_action("snapshot", {"token_id": _snapshot_token,
		"field_feet": _field_feet, "attack": _snapshot_attack})
	if _pending_snapshot.is_empty():
		return
	caption.text = "Richiesta snapshot al desktop…"
	viewer.show()

func _on_action_completed(id: String, action: String, result: Dictionary) -> void:
	if action == "place_token" and id == _pending_place:
		_pending_place = ""
		place_button.disabled = false
		if bool(result.get("ok", false)):
			sheet.link_mobile_token(String(result.get("creature_id", "")), String(result.get("token_id", "")))
			shell._connection_status.text = "Token piazzato: " + String(result.get("name", ""))
		else:
			shell._show_touch_help(String(result.get("error", "Piazzamento non riuscito.")))
	elif action == "snapshot" and id == _pending_snapshot:
		_pending_snapshot = ""
		if bool(result.get("ok", false)) and canvas.load_snapshot(result):
			_cached = true
			reopen_button.disabled = false
			caption.text = "%s · campo %d ft" % [result.get("title", "Mappa"), int(result.get("field_feet", 120))]
			if not _snapshot_attack.is_empty():
				caption.text += " · verde: gittata normale · arancio: lunga"
		else:
			caption.text = String(result.get("error", "Snapshot non disponibile."))

func close_overlay() -> bool:
	if picker.visible:
		picker.hide()
		return true
	if viewer.visible:
		viewer.hide()
		return true
	return false
