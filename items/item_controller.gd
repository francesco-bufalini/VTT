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

var _dragging: bool = false
var _drag_moved: bool = false
var _drag_valid: bool = false
var _drag_press_position := Vector2.ZERO
var _drag_target_transform := Transform3D.IDENTITY
var _drag_before: Dictionary = {}
var _drag_was_captured: bool = false
var _drag_preview: MeshInstance3D


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
	item_picker.item_selected.connect(_on_item_picker_selected)

	token_picker = OptionButton.new()
	column.add_child(token_picker)

	var actions := HBoxContainer.new()
	column.add_child(actions)
	for entry: Array in [
		["Associa token", _link_selected],
		["Scollega", _unlink_selected],
		["Sposta", _place_selected],
		["Elimina", _delete_selected],
	]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		actions.add_child(button)

	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.text = (
		"Crea un carro dal menu Item. Seleziona qui il token che lo traina."
	)
	column.add_child(notice)

	panel.close_requested.connect(_restore_mouse)
	panel.confirmed.connect(_restore_mouse)

	placement_hint = Label.new()
	placement_hint.text = (
		"Carro romano: clicca una superficie per posizionarlo · Esc per annullare"
	)
	placement_hint.position = Vector2(16, 52)
	placement_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.get_node("UI").add_child(placement_hint)
	placement_hint.hide()

	_build_drag_preview()


func _build_drag_preview() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.15, 0.72, 1.0, 0.28)
	material.emission_enabled = true
	material.emission = Color(0.04, 0.4, 1.0, 1.0)
	material.emission_energy_multiplier = 0.7
	material.no_depth_test = true

	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 0.05, 2.0) * board.cell_size
	mesh.material = material

	_drag_preview = MeshInstance3D.new()
	_drag_preview.name = "ItemDragPreview"
	_drag_preview.mesh = mesh
	_drag_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drag_preview.visible = false
	board.add_child(_drag_preview)


func instance_from_picker(index: int) -> StaticBody3D:
	return items[index] if index >= 0 and index < items.size() else null


func has_selected_item() -> bool:
	return selected_item != null and is_instance_valid(selected_item)


func select_item(item: StaticBody3D) -> void:
	if item != null and (not is_instance_valid(item) or not (item in items)):
		return
	if has_selected_item() and selected_item != item:
		if selected_item.has_method("set_selected"):
			selected_item.call("set_selected", false)
	selected_item = item
	if has_selected_item() and selected_item.has_method("set_selected"):
		selected_item.call("set_selected", true)
	if item_picker != null and has_selected_item():
		var index: int = items.find(selected_item)
		if index >= 0 and index < item_picker.item_count:
			item_picker.select(index)


func clear_selection() -> void:
	if has_selected_item() and selected_item.has_method("set_selected"):
		selected_item.call("set_selected", false)
	selected_item = null


func _on_item_picker_selected(index: int) -> void:
	var item := instance_from_picker(index)
	if item != null:
		board.clear_token_selection()
		select_item(item)


func open_menu() -> void:
	flush_motion()
	item_picker.clear()
	for item in items:
		item_picker.add_item("Carro romano · " + item.item_id.right(6))

	if has_selected_item() and selected_item in items:
		item_picker.select(items.find(selected_item))
	else:
		select_item(instance_from_picker(0))

	token_picker.clear()
	for token in _tokens():
		token_picker.add_item(String(token.call("get_display_name")))
		token_picker.set_item_metadata(
			token_picker.item_count - 1,
			String(token.call("get_token_id"))
		)
		if (
			has_selected_item()
			and selected_item.linked_token_id
			== String(token.call("get_token_id"))
		):
			token_picker.select(token_picker.item_count - 1)

	_was_captured = (
		_was_captured
		or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	)
	board._ui_owns_mouse = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.popup_centered()


func _restore_mouse(force_capture: bool = false) -> void:
	board._ui_owns_mouse = false
	if not placing:
		placement_hint.hide()
	if (force_capture or _was_captured) and not placing:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_was_captured = false


func _resume_game_after_panel_action() -> void:
	panel.hide()
	# Association is a finished game action, not a modal targeting mode.
	# Always return ownership to the board so mouse-look works immediately.
	_restore_mouse(true)


func begin_placement(create_new: bool = true) -> void:
	if create_new:
		clear_selection()
	placing = true
	placement_hint.show()
	board._ui_owns_mouse = false
	panel.hide()
	_was_captured = (
		_was_captured
		or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _place_selected() -> void:
	if has_selected_item():
		begin_placement(false)


func handle_event(event: InputEvent) -> bool:
	if placing:
		return _handle_placement_event(event)
	if _dragging:
		return _handle_drag_event(event)
	return _try_begin_item_drag(event)


func _handle_placement_event(event: InputEvent) -> bool:
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
			var hit: Dictionary = board._raycast_from_screen(
				event.position,
				1 | 4,
				false
			)
			if (
				not hit.is_empty()
				and Vector3(hit.normal).dot(Vector3.UP) > 0.7
			):
				var point: Vector3 = hit.position
				point.x = roundf(point.x / board.cell_size) * board.cell_size
				point.z = roundf(point.z / board.cell_size) * board.cell_size
				# Root is at deck level; wheels rest on the picked surface.
				point.y += 0.70 * board.cell_size
				board.push_undo_state()
				if not has_selected_item():
					select_item(create_item(point))
				else:
					move_item(selected_item, point)
				placing = false
				_restore_mouse()
			return true

	return event is InputEventMouseMotion or event is InputEventKey


func _try_begin_item_drag(event: InputEvent) -> bool:
	if (
		not event is InputEventMouseButton
		or not event.pressed
		or event.button_index != MOUSE_BUTTON_LEFT
		or event.ctrl_pressed
	):
		return false
	if (
		board._ui_owns_mouse
		or board.color_dialog.visible
		or board.measurement_tool.is_measurement_mode()
	):
		return false

	var point: Vector2 = (
		board._screen_center()
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		else event.position
	)
	var hit: Dictionary = board._raycast_from_screen(point, 0xFFFFFFFF, true)
	if hit.is_empty():
		return false
	var collider := hit.get("collider") as Node
	if collider == null:
		return false
	var target: Node = board._find_interaction_target(collider)
	if (
		target == null
		or not target.is_in_group("dnd_item")
		or not target is StaticBody3D
	):
		return false

	board.clear_token_selection()
	select_item(target as StaticBody3D)
	_begin_drag(point)
	return true


func _begin_drag(screen_point: Vector2) -> void:
	if not has_selected_item():
		return
	_dragging = true
	_drag_moved = false
	_drag_valid = false
	_drag_press_position = screen_point
	_drag_target_transform = selected_item.global_transform
	_drag_before = board.begin_undo_transaction()
	_drag_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _drag_was_captured:
		board.get_viewport().warp_mouse(screen_point)


func _handle_drag_event(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		if event.position.distance_to(_drag_press_position) > 4.0:
			_drag_moved = true
		_update_drag_preview(event.position)
		return true

	if (
		event is InputEventKey
		and event.pressed
		and event.keycode == KEY_ESCAPE
	):
		_finish_drag(false)
		return true

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
	):
		_finish_drag(false)
		return true

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		_finish_drag(_drag_moved and _drag_valid)
		return true

	return event is InputEventKey or event is InputEventMouseButton


func _update_drag_preview(screen_point: Vector2) -> void:
	_drag_valid = false
	_drag_preview.visible = false
	if not has_selected_item():
		return

	var exclusions: Array[RID] = [selected_item.get_rid()]
	var hit: Dictionary = board._raycast_from_screen_excluding(
		screen_point,
		1,
		exclusions,
		false
	)
	if hit.is_empty() or Vector3(hit.normal).dot(Vector3.UP) <= 0.7:
		return

	var point: Vector3 = hit.position
	point.x = roundf(point.x / board.cell_size) * board.cell_size
	point.z = roundf(point.z / board.cell_size) * board.cell_size
	point.y += 0.70 * board.cell_size

	_drag_target_transform = selected_item.global_transform
	_drag_target_transform.origin = point
	_drag_preview.global_transform = _drag_target_transform
	_drag_preview.visible = true
	_drag_valid = true


func _finish_drag(commit: bool) -> void:
	var should_commit := (
		commit
		and _drag_valid
		and has_selected_item()
		and not selected_item.global_transform.is_equal_approx(
			_drag_target_transform
		)
	)
	if should_commit:
		move_item_transform(selected_item, _drag_target_transform)
		board.commit_undo_transaction(_drag_before)

	_dragging = false
	_drag_moved = false
	_drag_valid = false
	_drag_before = {}
	_drag_preview.visible = false

	if _drag_was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_drag_was_captured = false


func create_item(
	point: Vector3,
	identity: String = ""
) -> StaticBody3D:
	var item := BoardItem.new()
	item.item_id = (
		identity
		if not identity.is_empty()
		else "item:" + Crypto.new().generate_random_bytes(16).hex_encode()
	)
	board.add_child(item)
	item.configure(board.cell_size)
	item.global_position = point
	items.append(item)
	return item


func _tokens() -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	for node in get_tree().get_nodes_in_group("dnd_token"):
		if (
			node is CharacterBody3D
			and board.is_ancestor_of(node)
			and not node.is_queued_for_deletion()
		):
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
	if not has_selected_item() or token_picker.item_count == 0:
		return
	var token := find_token(
		String(token_picker.get_item_metadata(token_picker.selected))
	)
	if token == null:
		return

	# Cross-cart links through riders would form a transport cycle.
	for other in items:
		if (
			other != selected_item
			and other.contains_passenger(
				token,
				other.global_transform
			)
		):
			notice.text = (
				"Scegli un token fuori dagli altri carri "
				+ "per evitare legami circolari."
			)
			return

	board.push_undo_state()
	link_item(selected_item, token)
	notice.text = "Associato: il carro mantiene la distanza dal token."
	_resume_game_after_panel_action()


func _unlink_selected() -> void:
	if has_selected_item():
		board.push_undo_state()
		selected_item.linked_token_id = ""
		selected_item.link_offset = Vector3.ZERO
		notice.text = "Carro scollegato."


func _delete_selected() -> void:
	if has_selected_item():
		board.push_undo_state()
		var deleting := selected_item
		clear_selection()
		remove_item(deleting)
		open_menu()


func remove_item(item: StaticBody3D) -> void:
	for token in _tokens():
		if token.get("grid_support") == item:
			token.set("grid_support", null)
	if item == selected_item:
		clear_selection()
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
		var previous: Vector3 = _last_token_positions.get(
			item.linked_token_id,
			token.global_position
		)
		var delta: Vector3 = token.global_position - previous
		if not delta.is_zero_approx():
			motions.append({
				"item": item,
				"destination": token.global_position + item.link_offset,
			})

	# Capture all passengers before any cart moves; overlapping decks carry once.
	for motion in motions:
		motion["passengers"] = _passengers(
			motion.item,
			driver_ids,
			explicitly_moved
		)

	var carried: Dictionary = {}
	for motion in motions:
		_transport(
			motion.item,
			motion.destination,
			carried,
			motion.passengers
		)

	_last_token_positions.clear()
	for token in _tokens():
		_last_token_positions[
			String(token.call("get_token_id"))
		] = token.global_position


func move_item(item: StaticBody3D, destination: Vector3) -> void:
	var next_transform := item.global_transform
	next_transform.origin = destination
	move_item_transform(item, next_transform)


func move_item_transform(
	item: StaticBody3D,
	destination: Transform3D
) -> void:
	flush_motion()
	var drivers: Dictionary = {}
	for other in items:
		if not other.linked_token_id.is_empty():
			drivers[other.linked_token_id] = true
	_transport_transform(
		item,
		destination,
		{},
		_passengers(item, drivers, [])
	)
	var token := find_token(item.linked_token_id)
	if token != null:
		item.link_offset = item.global_position - token.global_position
	_refresh_grid_after_item_motion()


func move_selected_grid(direction: Vector2i) -> void:
	if not has_selected_item() or direction == Vector2i.ZERO:
		return
	board.push_undo_state()

	var local_step := Vector3(
		float(direction.x),
		0.0,
		float(direction.y)
	)
	var world_step: Vector3 = selected_item.global_transform.basis * local_step
	world_step.y = 0.0
	world_step.x = roundf(world_step.x)
	world_step.z = roundf(world_step.z)
	if absf(world_step.x) < 0.5 and absf(world_step.z) < 0.5:
		world_step = local_step

	move_item(
		selected_item,
		selected_item.global_position
		+ Vector3(world_step.x, 0.0, world_step.z) * board.cell_size
	)


func move_selected_vertical(steps: int) -> void:
	if not has_selected_item() or steps == 0:
		return
	board.push_undo_state()
	move_item(
		selected_item,
		selected_item.global_position
		+ Vector3.UP * board.cell_size * float(steps)
	)


func rotate_selected_yaw(steps: int) -> void:
	if not has_selected_item() or steps == 0:
		return
	board.push_undo_state()
	var angles: Vector3 = selected_item.global_rotation
	angles.y = snappedf(
		angles.y + deg_to_rad(45.0 * float(steps)),
		PI / 4.0
	)
	var destination := selected_item.global_transform
	destination.basis = Basis.from_euler(angles)
	move_item_transform(selected_item, destination)


func rotate_selected_vertical(steps: int) -> void:
	if not has_selected_item() or steps == 0:
		return
	board.push_undo_state()
	var angles: Vector3 = selected_item.global_rotation
	var pitch_degrees := clampf(
		rad_to_deg(angles.x) + 30.0 * float(steps),
		-90.0,
		90.0
	)
	angles.x = deg_to_rad(snappedf(pitch_degrees, 30.0))
	var destination := selected_item.global_transform
	destination.basis = Basis.from_euler(angles)
	move_item_transform(selected_item, destination)


func _passengers(
	item: StaticBody3D,
	drivers: Dictionary,
	explicit: Array
) -> Array[CharacterBody3D]:
	var passengers: Array[CharacterBody3D] = []
	for token in _tokens():
		if token in explicit or drivers.has(String(token.call("get_token_id"))):
			continue
		if item.contains_passenger(token, item.global_transform):
			passengers.append(token)
	return passengers


func _transport(
	item: StaticBody3D,
	destination: Vector3,
	carried: Dictionary,
	passengers: Array
) -> void:
	var next_transform := item.global_transform
	next_transform.origin = destination
	_transport_transform(item, next_transform, carried, passengers)


func _transport_transform(
	item: StaticBody3D,
	destination: Transform3D,
	carried: Dictionary,
	passengers: Array
) -> void:
	var previous: Transform3D = item.global_transform
	item.global_transform = destination
	for token: CharacterBody3D in passengers:
		if carried.has(token):
			continue
		token.global_position = (
			item.global_transform
			* (previous.affine_inverse() * token.global_position)
		)
		token.set("grid_support", item)
		token.set("_support_transform", item.global_transform)
		token.velocity = Vector3.ZERO
		carried[token] = true
		if token.has_method("refresh_automatic_conditions"):
			token.call_deferred("refresh_automatic_conditions")


func _refresh_grid_after_item_motion() -> void:
	var grid := board.get_node_or_null("VolumetricGrid")
	if grid != null and grid.has_method("refresh"):
		grid.call_deferred("refresh")


func serialize_items() -> Array:
	flush_motion()
	var result: Array = []
	for item in items:
		result.append({
			"id": item.item_id,
			"catalog_id": "roman_chariot",
			"transform": board.board_sync._transform(item.global_transform),
			"linked_token_id": item.linked_token_id,
			"offset": board.board_sync._v3(item.link_offset),
		})
	return result


func apply_items(values: Array) -> void:
	for item in items.duplicate():
		remove_item(item)
	clear_selection()
	_last_token_positions.clear()

	for value: Dictionary in values:
		var item := create_item(Vector3.ZERO, value.id)
		item.global_transform = board.board_sync._dict_transform(value.transform)
		item.linked_token_id = value.linked_token_id
		item.link_offset = board.board_sync._dv3(value.offset)

	for token in _tokens():
		_last_token_positions[
			String(token.call("get_token_id"))
		] = token.global_position


func valid_items(values: Variant, token_ids: Dictionary) -> bool:
	if not values is Array or values.size() > 512:
		return false
	var ids: Dictionary = {}

	for value in values:
		if (
			not value is Dictionary
			or not value.get("id") is String
			or not value.id.begins_with("item:")
			or value.id.length() > 80
			or ids.has(value.id)
			or token_ids.has(value.id)
		):
			return false
		ids[value.id] = true

		if (
			value.get("catalog_id") != "roman_chariot"
			or not value.get("linked_token_id") is String
		):
			return false
		if (
			not value.linked_token_id.is_empty()
			and not token_ids.has(value.linked_token_id)
		):
			return false

		var transform_value: Variant = value.get("transform")
		if (
			not transform_value is Dictionary
			or not transform_value.get("basis") is Array
			or transform_value.basis.size() != 3
		):
			return false

		for vector in (
			transform_value.basis
			+ [transform_value.get("origin"), value.get("offset")]
		):
			if not vector is Dictionary:
				return false
			for axis in ["x", "y", "z"]:
				var number: Variant = vector.get(axis)
				if (
					not (number is float or number is int)
					or not is_finite(float(number))
					or absf(float(number)) > 100000
				):
					return false

		# Items may rotate, but never carry scale/shear/reflection in snapshots.
		var basis: Basis = board.board_sync._dict_transform(
			transform_value
		).basis
		if (
			absf(basis.x.length() - 1.0) > 0.01
			or absf(basis.y.length() - 1.0) > 0.01
			or absf(basis.z.length() - 1.0) > 0.01
			or absf(basis.x.dot(basis.y)) > 0.01
			or absf(basis.x.dot(basis.z)) > 0.01
			or absf(basis.y.dot(basis.z)) > 0.01
			or absf(basis.determinant() - 1.0) > 0.02
		):
			return false

	return true
