extends Node
## The mobile Partita action forms and the cached snapshot viewer.
const SnapshotView = preload("res://vtt/mobile/map_snapshot_view.gd")
const Owner = preload("res://vtt/creature_owner.gd")
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
var _pending_interactions: Dictionary = {}
var _spell_status: Dictionary = {}
var _spell_definition: Dictionary = {}
var _spell_record_id := ""
var _spell_slot_choice := 0
var _movement_buttons: Array[Button] = []
var _target_note := ""
var _aim_pixel := Vector2.INF
var _preview_pixel := Vector2.INF
var _preview_request := ""
var _preview_dirty := false
var _preview_elapsed := 0.0
var _finish_spell_button: Button
var _cancel_spell_button: Button

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
	canvas.map_tapped.connect(_on_map_tapped)
	canvas.map_aimed.connect(_on_map_aimed)
	var movement := HBoxContainer.new()
	body.add_child(movement)
	for spec: Array in [["←", "west", "Ovest"], ["↑", "north", "Nord"], ["↓", "south", "Sud"], ["→", "east", "Est"], ["↥", "up", "Sali"], ["↧", "down", "Scendi"]]:
		var button := Button.new()
		button.text = spec[0]
		button.tooltip_text = spec[2]
		button.custom_minimum_size = Vector2(48, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_send_interaction.bind("move_token", {"direction": spec[1]}))
		movement.add_child(button)
		_movement_buttons.append(button)
	var spell_actions := HBoxContainer.new()
	body.add_child(spell_actions)
	_cancel_spell_button = Button.new()
	_cancel_spell_button.text = "Annulla incantesimo"
	_cancel_spell_button.pressed.connect(_send_interaction.bind("cancel_spell", {}))
	spell_actions.add_child(_cancel_spell_button)
	_finish_spell_button = Button.new()
	_finish_spell_button.text = "Conferma bersagli"
	_finish_spell_button.pressed.connect(_confirm_spell)
	spell_actions.add_child(_finish_spell_button)
	_cancel_spell_button.hide()
	_finish_spell_button.hide()
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
			shell._connection_status.text = "Piazzamento in corso…", "Accanto a quale token?")

func _choose_token(callback: Callable, title: String) -> void:
	_clear_picker(title)
	var data: Dictionary = controller.get_map_data()
	for token: Dictionary in data.get("tokens", []):
		_add_choice(String(token.get("name", "Token")), callback.bind(String(token.id)))
	if data.get("tokens", []).is_empty():
		picker_title.text = "Collega un desktop con una mappa e almeno un token visibile."

func _request_selected_snapshot(token_id: String) -> void:
	picker.hide()
	if bool(_spell_status.get("active", false)) and token_id != _snapshot_token:
		viewer.show()
		caption.text = "Completa o annulla l’incantesimo prima di cambiare token."
		return
	_snapshot_token = token_id
	_snapshot_attack = {}
	_target_note = ""
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
	if bool(_spell_status.get("active", false)):
		viewer.show()
		caption.text = "Completa o annulla prima l’incantesimo nello snapshot."
		return
	_snapshot_token = token_id
	_target_note = ""
	_snapshot_attack = {"range_feet": attack.get("range_feet", 5),
		"long_range_feet": attack.get("long_range_feet", 0), "melee": attack.get("melee", true)}
	_field_feet = clampf(maxf(float(attack.get("range_feet", 5)), float(attack.get("long_range_feet", 0))) * 2.0, 20, 1500)
	_send_snapshot()

func _reopen_snapshot() -> void:
	if not _cached:
		return
	canvas.show()
	var saved: Dictionary = canvas.snapshot
	_snapshot_token = String(saved.get("token_id", _snapshot_token))
	_field_feet = float(saved.get("field_feet", 120))
	_snapshot_attack = saved.get("attack", {}).duplicate(true)
	caption.text = "%s · campo %d ft" % [saved.get("title", "Mappa"), int(_field_feet)]
	viewer.show()
	if bool(_spell_status.get("active", false)) and _pending_snapshot.is_empty():
		_send_snapshot()

func _zoom_snapshot(factor: float) -> void:
	if is_equal_approx(factor, 1.0):
		if _pending_snapshot.is_empty():
			_send_snapshot()
	else:
		canvas.zoom_by(1.0 / factor)

func handle_snapshot_input(event: InputEvent) -> bool:
	return viewer.visible and not picker.visible and canvas.handle_screen_input(event)

func begin_mobile_spell(record: Dictionary, spell: Dictionary, level: int, context: Dictionary, choice: int) -> bool:
	var token_id := String(record.get("linked_token_sync_id", ""))
	if token_id.is_empty():
		shell._show_touch_help("Usa Piazza token per collegare questa creatura alla mappa.")
		return false
	_snapshot_token = token_id
	_snapshot_attack = {}
	canvas.hide()
	_spell_definition = spell.duplicate(true)
	_spell_record_id = String(record.get("id", ""))
	_spell_slot_choice = choice
	var payload := {"spell_id": spell.get("id", ""), "name": spell.get("name", ""),
		"source": spell.get("source", ""), "slot_level": level, "context": context}
	_send_interaction("begin_spell", payload)
	viewer.show()
	return not _pending_interactions.is_empty()

func _send_interaction(action: String, extra: Dictionary) -> void:
	var remote: Dictionary = controller.get_map_data()
	if remote.is_empty():
		caption.text = "Collega un desktop e attendi la ricezione della mappa prima di usare i comandi."
		return
	if int(remote.get("mobile_protocol", 0)) < 2:
		caption.text = "Desktop da aggiornare: installa e riavvia anche la nuova versione PC. Lo snapshot da solo non abilita i comandi."
		return
	if not _pending_interactions.is_empty():
		return
	var payload := extra.duplicate(true)
	payload.token_id = _snapshot_token
	payload.owner_id = Owner.local_id()
	var request_id: String = controller.request_action(action, payload)
	if not request_id.is_empty():
		_pending_interactions[request_id] = action
		for button: Button in _movement_buttons:
			button.disabled = true
		caption.text = "Richiesta al desktop…"

func _on_map_tapped(pixel: Vector2, target_id: String) -> void:
	if not _pending_snapshot.is_empty() or not _pending_interactions.is_empty():
		return
	if bool(_spell_status.get("active", false)):
		_send_interaction("target_spell", {"target_id": target_id, "pixel": [pixel.x, pixel.y],
			"snapshot_id": canvas.snapshot.get("snapshot_id", "")})
	elif not _snapshot_attack.is_empty() and not target_id.is_empty():
		_send_interaction("target_attack", {"target_id": target_id, "attack": _snapshot_attack})
	else:
		canvas.selected_ids.assign([target_id] if not target_id.is_empty() else [])
		canvas.queue_redraw()

func _apply_spell_status(status: Dictionary) -> void:
	_spell_status = status
	canvas.aim_mode = bool(status.get("active", false)) and String(status.get("phase", "")) in ["point", "direction_point", "multi_target_points", "wall_start", "wall_segment", "wall_center", "wall_radius", "wall_arc_start", "wall_arc_end", "summon_point", "teleport_destination"]
	if not canvas.aim_mode:
		canvas.area_preview = {}
		_aim_pixel = Vector2.INF
		_preview_dirty = false
	var active := bool(status.get("active", false))
	_cancel_spell_button.visible = active
	_finish_spell_button.visible = active
	_finish_spell_button.text = "Conferma punto / area" if canvas.aim_mode else "Conferma bersagli"
	canvas.selected_ids.assign(status.get("selected_ids", []))
	canvas.queue_redraw()
	if not active and not _spell_definition.is_empty() and String(status.get("outcome", "")) in ["completed", "cancelled"]:
		sheet.finish_mobile_spell(_spell_definition, status.get("outcome") == "completed")
		_spell_definition = {}

func _on_map_aimed(pixel: Vector2) -> void:
	if not canvas.aim_mode or not _pending_snapshot.is_empty():
		return
	_aim_pixel = pixel
	_preview_dirty = true
	canvas.show_local_area(pixel, _spell_status)

func _aim_payload() -> Dictionary:
	return {"token_id": _snapshot_token, "owner_id": Owner.local_id(), "target_id": "",
		"pixel": [_aim_pixel.x, _aim_pixel.y], "snapshot_id": canvas.snapshot.get("snapshot_id", "")}

func _process(delta: float) -> void:
	_preview_elapsed += delta
	if not _preview_dirty or not _preview_request.is_empty() or _preview_elapsed < 0.12 or not _pending_interactions.is_empty():
		return
	_preview_elapsed = 0
	_preview_dirty = false
	_preview_pixel = _aim_pixel
	_preview_request = controller.request_action("preview_spell", _aim_payload())

func _confirm_spell() -> void:
	if canvas.aim_mode:
		if _aim_pixel == Vector2.INF:
			caption.text = "Trascina un dito per mirare; usa due dita per spostare o ingrandire la mappa."
			return
		_send_interaction("target_spell", _aim_payload())
	else:
		_send_interaction("finish_spell", {})

func _send_snapshot() -> void:
	_preview_dirty = false
	_aim_pixel = Vector2.INF
	canvas.area_preview = {}
	_pending_snapshot = controller.request_action("snapshot", {"token_id": _snapshot_token,
		"field_feet": _field_feet, "attack": _snapshot_attack, "owner_id": Owner.local_id()})
	if _pending_snapshot.is_empty():
		return
	caption.text = "Richiesta snapshot al desktop…"
	viewer.show()

func _on_action_completed(id: String, action: String, result: Dictionary) -> void:
	if action == "preview_spell" and id == _preview_request:
		_preview_request = ""
		if not bool(result.get("ok", false)):
			caption.text = String(result.get("error", "Anteprima non disponibile."))
			canvas.area_preview = {}
			canvas.queue_redraw()
			return
		if _preview_pixel.is_equal_approx(_aim_pixel) and canvas.aim_mode and bool(result.get("ok", false)):
			canvas.area_preview = result.get("preview", {})
			canvas.selected_ids.assign(canvas.area_preview.get("affected_ids", []))
			canvas.queue_redraw()
			caption.text = "Gittata %d ft · %s" % [int(_spell_status.get("range_feet", 0)), "Trascina per mirare · due dita per zoom/spostamento · Conferma per lanciare." if bool(canvas.area_preview.get("valid", false)) else "Punto fuori gittata o non valido."]
		return
	if _pending_interactions.has(id):
		_pending_interactions.erase(id)
		for button: Button in _movement_buttons:
			button.disabled = false
		if not bool(result.get("ok", false)):
			caption.text = String(result.get("error", "Comando non riuscito."))
			if action == "begin_spell":
				sheet.finish_mobile_spell(_spell_definition, false)
				_spell_definition = {}
			return
		if action == "target_attack":
			_target_note = " · bersaglio: %d ft%s" % [int(ceil(float(result.get("distance_feet", 0)))), " · gittata lunga: svantaggio" if bool(result.get("long_range", false)) else ""]
		if action == "begin_spell":
			sheet.accept_mobile_spell_start(_spell_record_id, _spell_slot_choice)
		if result.has("targeting"):
			_apply_spell_status(result.targeting)
		_send_snapshot()
		return
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
			canvas.show()
			_apply_spell_status(result.get("targeting", {}))
			_cached = true
			reopen_button.disabled = false
			caption.text = "%s · campo %d ft" % [result.get("title", "Mappa"), int(result.get("field_feet", 120))]
			if canvas.aim_mode:
				caption.text = "%s · gittata %d ft · trascina per mirare · due dita per zoom/spostamento · Conferma per lanciare" % [result.get("title", "Mappa"), int(_spell_status.get("range_feet", 0))]
			elif bool(_spell_status.get("active", false)):
				caption.text += " · " + String(_spell_status.get("instruction", "Seleziona sulla mappa"))
			if not _snapshot_attack.is_empty():
				caption.text += " · verde: gittata normale · arancio: lunga" + _target_note
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
