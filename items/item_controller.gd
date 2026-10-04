extends Node

const BoardItem = preload("res://items/board_item.gd")
var board: Node3D
var items: Array[StaticBody3D] = []
var selected_item: StaticBody3D
var panel: AcceptDialog
var item_picker: OptionButton
var token_picker: OptionButton
var notice: Label
var placement_hint: Label
var placing: bool = false
var _last_token_positions: Dictionary = {}
var _was_captured: bool = false

func setup(owner_board: Node3D) -> void:
	board = owner_board
	process_physics_priority = -10
	panel = AcceptDialog.new()
	panel.title = "Item · armature, bauli e veicoli"
	panel.min_size = Vector2i(430, 210)
	board.get_node("UI").add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	item_picker = OptionButton.new()
	column.add_child(item_picker)
	item_picker.item_selected.connect(func(index: int): selected_item = instance_from_picker(index))
	token_picker = OptionButton.new()
	column.add_child(token_picker)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	for entry: Array in [["Associa token", _link_selected], ["Scollega", _unlink_selected], ["Sposta", _place_selected], ["Elimina", _delete_selected]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		actions.add_child(button)
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.text = "Crea un carro dal menu Item. Seleziona qui il token che lo traina."
	column.add_child(notice)
	panel.close_requested.connect(_restore_mouse)
	panel.confirmed.connect(_restore_mouse)
	placement_hint = Label.new()
	placement_hint.text = "Carro romano: clicca una superficie per posizionarlo · Esc per annullare"
	placement_hint.position = Vector2(16, 52)
	placement_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.get_node("UI").add_child(placement_hint)
	placement_hint.hide()

func instance_from_picker(index: int) -> StaticBody3D:
	return items[index] if index >= 0 and index < items.size() else null

func open_menu() -> void:
	flush_motion()
	item_picker.clear()
	for item in items:
		item_picker.add_item("Carro romano · " + item.item_id.right(6))
	if is_instance_valid(selected_item) and selected_item in items:
		item_picker.select(items.find(selected_item))
	else:
		selected_item = instance_from_picker(0)
	token_picker.clear()
	for token in _tokens():
		token_picker.add_item(String(token.call("get_display_name")))
		token_picker.set_item_metadata(token_picker.item_count - 1, String(token.call("get_token_id")))
		if is_instance_valid(selected_item) and selected_item.linked_token_id == String(token.call("get_token_id")):
			token_picker.select(token_picker.item_count - 1)
	_was_captured = _was_captured or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	board._ui_owns_mouse = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.popup_centered()

func _restore_mouse() -> void:
	board._ui_owns_mouse = false
	if not placing:
		placement_hint.hide()
	if _was_captured and not placing:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_was_captured = false

func begin_placement(create_new: bool = true) -> void:
	if create_new:
		selected_item = null
	placing = true
	placement_hint.show()
	board._ui_owns_mouse = false
	panel.hide()
	_was_captured = _was_captured or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _place_selected() -> void:
	if is_instance_valid(selected_item):
		begin_placement(false)

func handle_event(event: InputEvent) -> bool:
	if not placing:
		return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		placing = false
		_restore_mouse()
		return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			placing = false
			_restore_mouse()
			return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			var hit: Dictionary = board._raycast_from_screen(event.position, 1 | 4, false)
			if not hit.is_empty() and Vector3(hit.normal).dot(Vector3.UP) > 0.7:
				var point: Vector3 = hit.position
				point.x = roundf(point.x / board.cell_size) * board.cell_size
				point.z = roundf(point.z / board.cell_size) * board.cell_size
				# Root is at deck level; wheels rest on the picked surface.
				point.y += 0.70 * board.cell_size
				board.push_undo_state()
				if not is_instance_valid(selected_item):
					selected_item = create_item(point)
				else:
					move_item(selected_item, point)
				placing = false
				_restore_mouse()
			return true
	return event is InputEventMouseMotion or event is InputEventKey

func create_item(point: Vector3, identity: String = "") -> StaticBody3D:
	var item := BoardItem.new()
	item.item_id = identity if not identity.is_empty() else "item:" + Crypto.new().generate_random_bytes(16).hex_encode()
	board.add_child(item)
	item.configure(board.cell_size)
	item.global_position = point
	items.append(item)
	return item

func _tokens() -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	for node in get_tree().get_nodes_in_group("dnd_token"):
		if node is CharacterBody3D and board.is_ancestor_of(node) and not node.is_queued_for_deletion():
			result.append(node)
	return result

func find_token(identity: String) -> CharacterBody3D:
	for token in _tokens():
		if String(token.call("get_token_id")) == identity:
			return token
	return null

func link_item(item: StaticBody3D, token: CharacterBody3D) -> void:
	flush_motion()
	item.linked_token_id = String(token.call("get_token_id"))
	item.link_offset = item.global_position - token.global_position
	_last_token_positions[item.linked_token_id] = token.global_position
	# A driver on its own deck moves independently, never as a passenger.
	if token.get("grid_support") == item:
		token.set("grid_support", null)

func _link_selected() -> void:
	if not is_instance_valid(selected_item) or token_picker.item_count == 0:
		return
	var token := find_token(String(token_picker.get_item_metadata(token_picker.selected)))
	if token == null:
		return
	# Cross-cart links through riders would form a transport cycle.
	for other in items:
		if other != selected_item and other.contains_passenger(token, other.global_transform):
			notice.text = "Scegli un token fuori dagli altri carri per evitare legami circolari."
			return
	board.push_undo_state()
	link_item(selected_item, token)
	notice.text = "Associato: il carro mantiene la distanza dal token."

func _unlink_selected() -> void:
	if is_instance_valid(selected_item):
		board.push_undo_state()
		selected_item.linked_token_id = ""
		selected_item.link_offset = Vector3.ZERO
		notice.text = "Carro scollegato."

func _delete_selected() -> void:
	if is_instance_valid(selected_item):
		board.push_undo_state()
		remove_item(selected_item)
		selected_item = null
		open_menu()

func remove_item(item: StaticBody3D) -> void:
	for token in _tokens():
		if token.get("grid_support") == item:
			token.set("grid_support", null)
	items.erase(item)
	item.free()

func _physics_process(_delta: float) -> void:
	flush_motion()

func flush_motion(explicitly_moved: Array = []) -> void:
	var motions: Array[Dictionary] = []
	var driver_ids: Dictionary = {}
	for item in items:
		if item.linked_token_id.is_empty():
			continue
		var token := find_token(item.linked_token_id)
		if token == null:
			item.linked_token_id = ""
			continue
		driver_ids[item.linked_token_id] = true
		var previous: Vector3 = _last_token_positions.get(item.linked_token_id, token.global_position)
		var delta: Vector3 = token.global_position - previous
		if not delta.is_zero_approx():
			motions.append({"item": item, "destination": token.global_position + item.link_offset})
	# Capture all passengers before any cart moves; overlapping decks carry once.
	for motion in motions:
		motion["passengers"] = _passengers(motion.item, driver_ids, explicitly_moved)
	var carried: Dictionary = {}
	for motion in motions:
		_transport(motion.item, motion.destination, carried, motion.passengers)
	_last_token_positions.clear()
	for token in _tokens():
		_last_token_positions[String(token.call("get_token_id"))] = token.global_position

func move_item(item: StaticBody3D, destination: Vector3) -> void:
	flush_motion()
	var drivers: Dictionary = {}
	for other in items:
		drivers[other.linked_token_id] = true
	_transport(item, destination, {}, _passengers(item, drivers, []))
	var token := find_token(item.linked_token_id)
	if token != null:
		item.link_offset = item.global_position - token.global_position

func _passengers(item: StaticBody3D, drivers: Dictionary, explicit: Array) -> Array[CharacterBody3D]:
	var passengers: Array[CharacterBody3D] = []
	for token in _tokens():
		if token in explicit or drivers.has(String(token.call("get_token_id"))):
			continue
		if item.contains_passenger(token, item.global_transform):
			passengers.append(token)
	return passengers

func _transport(item: StaticBody3D, destination: Vector3, carried: Dictionary, passengers: Array) -> void:
	var previous: Transform3D = item.global_transform
	item.global_position = destination
	for token: CharacterBody3D in passengers:
		if carried.has(token):
			continue
		token.global_position = item.global_transform * (previous.affine_inverse() * token.global_position)
		token.set("grid_support", item)
		token.set("_support_transform", item.global_transform)
		token.velocity = Vector3.ZERO
		carried[token] = true
		if token.has_method("refresh_automatic_conditions"):
			token.call_deferred("refresh_automatic_conditions")

func serialize_items() -> Array:
	flush_motion()
	var result: Array = []
	for item in items:
		result.append({
			"id": item.item_id, "catalog_id": "roman_chariot",
			"transform": board.board_sync._transform(item.global_transform),
			"linked_token_id": item.linked_token_id,
			"offset": board.board_sync._v3(item.link_offset)
		})
	return result

func apply_items(values: Array) -> void:
	for item in items.duplicate():
		remove_item(item)
	selected_item = null
	_last_token_positions.clear()
	for value: Dictionary in values:
		var item := create_item(Vector3.ZERO, value.id)
		item.global_transform = board.board_sync._dict_transform(value.transform)
		item.linked_token_id = value.linked_token_id
		item.link_offset = board.board_sync._dv3(value.offset)
	for token in _tokens():
		_last_token_positions[String(token.call("get_token_id"))] = token.global_position

func valid_items(values: Variant, token_ids: Dictionary) -> bool:
	if not values is Array or values.size() > 512:
		return false
	var ids: Dictionary = {}
	for value in values:
		if not value is Dictionary or not value.get("id") is String or not value.id.begins_with("item:") or value.id.length() > 80 or ids.has(value.id) or token_ids.has(value.id):
			return false
		ids[value.id] = true
		if value.get("catalog_id") != "roman_chariot" or not value.get("linked_token_id") is String:
			return false
		if not value.linked_token_id.is_empty() and not token_ids.has(value.linked_token_id):
			return false
		var t: Variant = value.get("transform")
		if not t is Dictionary or not t.get("basis") is Array or t.basis.size() != 3:
			return false
		for vector in t.basis + [t.get("origin"), value.get("offset")]:
			if not vector is Dictionary:
				return false
			for axis in ["x", "y", "z"]:
				var number: Variant = vector.get(axis)
				if not (number is float or number is int) or not is_finite(float(number)) or absf(float(number)) > 100000:
					return false
		# Item footprint/collisions stay in world grid units.
		var basis: Basis = board.board_sync._dict_transform(t).basis
		if not basis.is_equal_approx(Basis.IDENTITY):
			return false
	return true
