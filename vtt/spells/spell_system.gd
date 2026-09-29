extends Node

const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")
const ALL_COLLISION_LAYERS := 0xFFFFFFFF

var board_root: Node3D
var ui_root: CanvasLayer
var panel: PanelContainer
var search_input: LineEdit
var search_results: ItemList
var class_tree: Tree
var spell_title: Label
var spell_meta: Label
var spell_description: RichTextLabel
var activate_button: Button
var instruction_label: Label

var _selected_spell_id: String = ""
var _pending_spell_id: String = ""
var _targeting_phase: String = ""
var _pending_caster: Node3D = null
var _directional_pitch_degrees: int = 0
var _restore_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func setup(root: Node3D) -> void:
	board_root = root
	call_deferred("_initialize")


func _process(_delta: float) -> void:
	if _pending_spell_id.is_empty():
		_hide_spell_preview()
		_hide_spell_range_preview()
		return
	_update_spell_preview()


func _initialize() -> void:
	if board_root == null or not is_instance_valid(board_root):
		return

	ui_root = board_root.get_node_or_null("UI") as CanvasLayer
	if ui_root == null:
		push_error("SpellSystem: UI CanvasLayer non trovato.")
		return

	_build_panel()
	_build_instruction_label()
	_populate_class_tree()
	_refresh_search_results("")
	_select_spell("burning_hands")


func is_panel_open() -> bool:
	return panel != null and panel.visible


func is_targeting() -> bool:
	return not _pending_spell_id.is_empty()


func toggle_panel() -> void:
	if panel == null:
		return
	if panel.visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	if panel == null:
		return

	_cancel_pending_cast(false)
	_restore_mouse_mode = Input.mouse_mode
	board_root.set("_ui_owns_mouse", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.show()
	search_input.grab_focus()


func close_panel() -> void:
	if panel == null:
		return

	panel.hide()
	_cancel_pending_cast(false)
	board_root.set("_ui_owns_mouse", false)
	Input.mouse_mode = _restore_mouse_mode


func handle_input(event: InputEvent) -> bool:
	if _pending_spell_id.is_empty():
		return false

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_ESCAPE:
				_cancel_pending_cast()
				return true

			if (
				_targeting_phase == "caster"
				and _pending_spell_id == "burning_hands"
				and key_event.keycode in [KEY_UP, KEY_DOWN]
			):
				_adjust_directional_pitch(
					45 if key_event.keycode == KEY_UP else -45
				)
				return true

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if not mouse_event.pressed:
			return false

		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_pending_cast()
			return true

		if _targeting_phase in ["point", "direction_point"]:
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_adjust_point_depth(-1.0)
				return true
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_adjust_point_depth(1.0)
				return true

		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return false

		var screen_position: Vector2 = mouse_event.position
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			screen_position = get_viewport().get_visible_rect().size * 0.5

		match _targeting_phase:
			"caster":
				_try_select_caster(screen_position)
				return true
			"point":
				_try_select_point(screen_position)
				return true
			"target_token":
				_try_select_target_token(screen_position)
				return true
			"direction_point":
				_try_select_direction_point(screen_position)
				return true

	return false


func _try_select_caster(screen_position: Vector2) -> void:
	var hit_value: Variant = board_root.call(
		"_raycast_from_screen",
		screen_position,
		ALL_COLLISION_LAYERS,
		true
	)
	if not hit_value is Dictionary:
		_set_instruction("Seleziona un token come origine dell'incantesimo.")
		return

	var hit: Dictionary = hit_value as Dictionary
	var collider: Node = hit.get("collider") as Node
	if collider == null:
		_set_instruction("Seleziona un token come origine dell'incantesimo.")
		return

	var target_value: Variant = board_root.call(
		"_find_interaction_target",
		collider
	)
	if not target_value is Node:
		_set_instruction("Seleziona un token come origine dell'incantesimo.")
		return

	var target: Node = target_value as Node
	if not target.is_in_group("dnd_token") or not target is Node3D:
		_set_instruction("Seleziona un token come origine dell'incantesimo.")
		return

	var caster: Node3D = target as Node3D
	var spell_data: Dictionary = SpellCatalog.spell(_pending_spell_id)
	if spell_data.is_empty():
		_cancel_pending_cast()
		return

	var target_mode: String = String(spell_data.get("target_mode", ""))
	match target_mode:
		"self_token":
			_cast_spell_from_caster(caster, spell_data)
			_finish_cast()
		"token_then_point":
			_pending_caster = caster
			_targeting_phase = "point"
			_hide_spell_preview()
			var point_range_feet: int = int(spell_data.get("range_feet", 0))
			_set_instruction(
				"%s: mira un punto entro %d ft e clicca · WASD + mouse per muoverti · rotellina per profondità 3D · Esc per annullare"
				% [
					String(spell_data.get("name", "Incantesimo")),
					point_range_feet
				]
			)
		"token_then_token":
			_pending_caster = caster
			_targeting_phase = "target_token"
			_hide_spell_preview()
			var token_range_feet: int = int(spell_data.get("range_feet", 0))
			_set_instruction(
				"%s: mira un altro token entro %d ft e clicca · WASD + mouse per muoverti · Esc per annullare"
				% [
					String(spell_data.get("name", "Incantesimo")),
					token_range_feet
				]
			)
		"token_then_direction":
			_pending_caster = caster
			_targeting_phase = "direction_point"
			_hide_spell_preview()
			var direction_range_feet: int = int(
				spell_data.get("range_feet", 0)
			)
			_set_instruction(
				"%s: mira un punto o un token entro %d ft per scegliere la direzione · la linea arriva sempre a %d ft · clicca per confermare · Esc per annullare"
				% [
					String(spell_data.get("name", "Incantesimo")),
					direction_range_feet,
					direction_range_feet
				]
			)
		_:
			_cancel_pending_cast()


func _try_select_point(screen_position: Vector2) -> void:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		_cancel_pending_cast()
		return

	var spell_data: Dictionary = SpellCatalog.spell(_pending_spell_id)
	if spell_data.is_empty():
		_cancel_pending_cast()
		return

	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		_set_instruction("Impossibile determinare il punto bersaglio.")
		return

	var point_value: Variant = measurement_tool.call(
		"get_spell_target_point",
		screen_position
	)
	if not point_value is Dictionary:
		_set_instruction(
			"Seleziona una superficie o una cella della griglia 3D."
		)
		return

	var point_data: Dictionary = point_value as Dictionary
	if not bool(point_data.get("valid", false)):
		_set_instruction(
			"Seleziona una superficie o una cella della griglia 3D."
		)
		return

	var target_point: Vector3 = point_data.get("point", Vector3.ZERO)
	var cell_size: float = _cell_size()
	var range_feet: float = float(spell_data.get("range_feet", 0.0))
	var max_world_distance: float = (
		range_feet / 5.0 * cell_size
	)
	var actual_world_distance: float = (
		_pending_caster.global_position.distance_to(target_point)
	)
	if actual_world_distance > max_world_distance + cell_size * 0.01:
		var actual_feet: int = int(
			round(actual_world_distance / cell_size * 5.0)
		)
		_set_instruction(
			"Punto fuori range: %d ft / %d ft. Scegli un punto più vicino."
			% [actual_feet, int(range_feet)]
		)
		return

	_cast_spell_at_point(
		_pending_caster,
		target_point,
		spell_data
	)
	_finish_cast()


func _try_select_target_token(screen_position: Vector2) -> void:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		_cancel_pending_cast()
		return

	var spell_data: Dictionary = SpellCatalog.spell(_pending_spell_id)
	if spell_data.is_empty():
		_cancel_pending_cast()
		return

	var target_data: Dictionary = _target_token_data(
		screen_position,
		spell_data
	)
	if not bool(target_data.get("valid", false)):
		if bool(target_data.get("out_of_range", false)):
			_set_instruction(
				"Token fuori range: %d ft / %d ft. Scegli un token più vicino."
				% [
					int(target_data.get("distance_feet", 0)),
					int(spell_data.get("range_feet", 0))
				]
			)
		else:
			_set_instruction(
				"Seleziona un altro token valido come bersaglio."
			)
		return

	var target: Node3D = target_data.get("target") as Node3D
	if target == null:
		return

	_cast_spell_at_token(
		_pending_caster,
		target,
		spell_data
	)
	_finish_cast()


func _try_select_direction_point(screen_position: Vector2) -> void:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		_cancel_pending_cast()
		return

	var spell_data: Dictionary = SpellCatalog.spell(_pending_spell_id)
	if spell_data.is_empty():
		_cancel_pending_cast()
		return

	var direction_data: Dictionary = _direction_target_data(
		screen_position,
		spell_data
	)
	if not bool(direction_data.get("valid", false)):
		if bool(direction_data.get("out_of_range", false)):
			_set_instruction(
				"Punto fuori gittata: %d ft / %d ft. Mira più vicino al caster."
				% [
					int(direction_data.get("distance_feet", 0)),
					int(spell_data.get("range_feet", 0))
				]
			)
		else:
			_set_instruction(
				"Mira una superficie, una cella della griglia 3D o un altro token."
			)
		return

	var target_point: Vector3 = direction_data.get(
		"point",
		Vector3.ZERO
	)
	_cast_directional_spell_to_point(
		_pending_caster,
		target_point,
		spell_data
	)
	_finish_cast()


func _update_spell_preview() -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var spell_data: Dictionary = SpellCatalog.spell(_pending_spell_id)
	if spell_data.is_empty():
		_hide_spell_preview()
		return

	var screen_position: Vector2 = (
		get_viewport().get_visible_rect().size * 0.5
	)

	_update_spell_range_preview(spell_data)

	match _targeting_phase:
		"caster":
			if _pending_spell_id != "burning_hands":
				_hide_spell_preview()
				return

			var hovered_caster: Node3D = _token_at_screen(screen_position)
			if hovered_caster == null:
				_hide_spell_preview()
				return

			var geometry: Dictionary = _directional_spell_geometry(
				hovered_caster,
				spell_data
			)
			if geometry.is_empty():
				_hide_spell_preview()
				return

			measurement_tool.call(
				"show_spell_preview",
				geometry.get("start", Vector3.ZERO),
				geometry.get("end", Vector3.ZERO),
				String(spell_data.get("aoe_shape", "cone")),
				String(spell_data.get("id", "burning_hands"))
			)

		"point":
			if _pending_caster == null or not is_instance_valid(_pending_caster):
				_hide_spell_preview()
				return

			var point_data: Dictionary = _point_target_data(
				screen_position,
				spell_data
			)
			if not bool(point_data.get("valid", false)):
				_hide_spell_preview()
				return

			var target_point: Vector3 = point_data.get(
				"point",
				Vector3.ZERO
			)
			var endpoint: Vector3 = _area_endpoint(
				target_point,
				spell_data
			)
			measurement_tool.call(
				"show_spell_preview",
				target_point,
				endpoint,
				String(spell_data.get("aoe_shape", "sphere")),
				String(spell_data.get("id", ""))
			)

		"target_token":
			var target_data: Dictionary = _target_token_data(
				screen_position,
				spell_data
			)
			if not bool(target_data.get("valid", false)):
				_hide_spell_preview()
				return

			var target: Node3D = target_data.get("target") as Node3D
			if target == null:
				_hide_spell_preview()
				return

			measurement_tool.call(
				"show_spell_preview",
				_token_spell_origin(_pending_caster),
				_token_spell_origin(target),
				"line",
				"chromatic_orb"
			)

		"direction_point":
			var direction_data: Dictionary = _direction_target_data(
				screen_position,
				spell_data
			)
			if not bool(direction_data.get("valid", false)):
				_hide_spell_preview()
				return

			var geometry: Dictionary = _direction_geometry_from_point(
				_pending_caster,
				direction_data.get("point", Vector3.ZERO),
				spell_data
			)
			if geometry.is_empty():
				_hide_spell_preview()
				return

			measurement_tool.call(
				"show_spell_preview",
				geometry.get("start", Vector3.ZERO),
				geometry.get("end", Vector3.ZERO),
				String(spell_data.get("aoe_shape", "line")),
				String(spell_data.get("id", "lightning_bolt"))
			)

		_:
			_hide_spell_preview()


func _token_at_screen(screen_position: Vector2) -> Node3D:
	var hit_value: Variant = board_root.call(
		"_raycast_from_screen",
		screen_position,
		ALL_COLLISION_LAYERS,
		true
	)
	if not hit_value is Dictionary:
		return null

	var hit: Dictionary = hit_value as Dictionary
	var collider: Node = hit.get("collider") as Node
	if collider == null:
		return null

	var target_value: Variant = board_root.call(
		"_find_interaction_target",
		collider
	)
	if not target_value is Node:
		return null

	var target: Node = target_value as Node
	if not target.is_in_group("dnd_token") or not target is Node3D:
		return null

	return target as Node3D


func _update_spell_range_preview(spell_data: Dictionary) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	if (
		_pending_caster == null
		or not is_instance_valid(_pending_caster)
		or _targeting_phase not in [
			"point",
			"target_token",
			"direction_point"
		]
	):
		measurement_tool.call("hide_spell_range_preview")
		return

	var range_feet: float = float(spell_data.get("range_feet", 0.0))
	if range_feet <= 0.0:
		measurement_tool.call("hide_spell_range_preview")
		return

	measurement_tool.call(
		"show_spell_range_preview",
		_pending_caster.global_position,
		range_feet / 5.0 * _cell_size()
	)


func _direction_target_data(
	screen_position: Vector2,
	spell_data: Dictionary
) -> Dictionary:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		return {"valid": false}

	var token_target: Node3D = _token_at_screen(screen_position)
	if token_target != null:
		if token_target == _pending_caster:
			return {"valid": false}
		return _validate_direction_point(
			_token_spell_origin(token_target),
			spell_data
		)

	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return {"valid": false}

	var point_value: Variant = measurement_tool.call(
		"get_spell_target_point",
		screen_position
	)
	if not point_value is Dictionary:
		return {"valid": false}

	var point_data: Dictionary = point_value as Dictionary
	if not bool(point_data.get("valid", false)):
		return {"valid": false}

	return _validate_direction_point(
		point_data.get("point", Vector3.ZERO),
		spell_data
	)


func _validate_direction_point(
	point: Vector3,
	spell_data: Dictionary
) -> Dictionary:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		return {"valid": false}

	var cell_size: float = _cell_size()
	var range_feet: float = float(spell_data.get("range_feet", 0.0))
	var max_world_distance: float = range_feet / 5.0 * cell_size
	var actual_world_distance: float = (
		_pending_caster.global_position.distance_to(point)
	)
	if actual_world_distance > max_world_distance + cell_size * 0.01:
		return {
			"valid": false,
			"out_of_range": true,
			"point": point,
			"distance_feet": int(
				round(actual_world_distance / cell_size * 5.0)
			)
		}

	var origin: Vector3 = _token_spell_origin(_pending_caster)
	if origin.distance_squared_to(point) < 0.0001:
		return {"valid": false}

	return {
		"valid": true,
		"point": point
	}


func _target_token_data(
	screen_position: Vector2,
	spell_data: Dictionary
) -> Dictionary:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		return {"valid": false}

	var target: Node3D = _token_at_screen(screen_position)
	if target == null or target == _pending_caster:
		return {"valid": false}

	var cell_size: float = _cell_size()
	var range_feet: float = float(spell_data.get("range_feet", 0.0))
	var max_world_distance: float = range_feet / 5.0 * cell_size
	var actual_world_distance: float = (
		_pending_caster.global_position.distance_to(target.global_position)
	)
	if actual_world_distance > max_world_distance + cell_size * 0.01:
		return {
			"valid": false,
			"out_of_range": true,
			"target": target,
			"distance_feet": int(
				round(actual_world_distance / cell_size * 5.0)
			)
		}

	return {
		"valid": true,
		"target": target
	}


func _point_target_data(
	screen_position: Vector2,
	spell_data: Dictionary
) -> Dictionary:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		return {"valid": false}

	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return {"valid": false}

	var point_value: Variant = measurement_tool.call(
		"get_spell_target_point",
		screen_position
	)
	if not point_value is Dictionary:
		return {"valid": false}

	var point_data: Dictionary = point_value as Dictionary
	if not bool(point_data.get("valid", false)):
		return {"valid": false}

	var target_point: Vector3 = point_data.get("point", Vector3.ZERO)
	var cell_size: float = _cell_size()
	var range_feet: float = float(spell_data.get("range_feet", 0.0))
	var max_world_distance: float = range_feet / 5.0 * cell_size
	var actual_world_distance: float = (
		_pending_caster.global_position.distance_to(target_point)
	)
	if actual_world_distance > max_world_distance + cell_size * 0.01:
		return {
			"valid": false,
			"out_of_range": true,
			"point": target_point,
			"distance_feet": int(
				round(actual_world_distance / cell_size * 5.0)
			)
		}

	return {
		"valid": true,
		"point": target_point
	}


func _area_endpoint(
	origin: Vector3,
	spell_data: Dictionary
) -> Vector3:
	var shape: String = String(spell_data.get("aoe_shape", "sphere"))
	if shape == "sphere":
		var radius_feet: float = float(
			spell_data.get("aoe_radius_feet", 5.0)
		)
		return (
			origin
			+ Vector3.RIGHT
			* (radius_feet / 5.0 * _cell_size())
		)

	var length_cells: int = int(
		spell_data.get("aoe_length_cells", 1)
	)
	return origin + Vector3.FORWARD * float(length_cells) * _cell_size()


func _directional_spell_geometry(
	caster: Node3D,
	spell_data: Dictionary
) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}

	var direction: Vector3 = -caster.global_transform.basis.z
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()

	var right_axis: Vector3 = direction.cross(Vector3.UP).normalized()
	if right_axis.length_squared() < 0.0001:
		right_axis = Vector3.RIGHT

	direction = (
		Basis(
			right_axis,
			deg_to_rad(float(_directional_pitch_degrees))
		)
		* direction
	).normalized()

	var origin: Vector3 = _token_spell_origin(caster)
	var length_cells: int = int(
		spell_data.get("aoe_length_cells", 3)
	)
	return {
		"start": origin,
		"end": (
			origin
			+ direction * float(length_cells) * _cell_size()
		)
	}


func _direction_geometry_from_point(
	caster: Node3D,
	target_point: Vector3,
	spell_data: Dictionary
) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}

	var origin: Vector3 = _token_spell_origin(caster)
	var direction: Vector3 = target_point - origin
	if direction.length_squared() < 0.0001:
		return {}
	direction = direction.normalized()

	var length_cells: int = int(
		spell_data.get("aoe_length_cells", 1)
	)
	return {
		"start": origin,
		"end": (
			origin
			+ direction * float(length_cells) * _cell_size()
		)
	}


func _token_spell_origin(token: Node3D) -> Vector3:
	if token == null or not is_instance_valid(token):
		return Vector3.ZERO
	if token.has_method("get_spell_origin_position"):
		var origin_value: Variant = token.call("get_spell_origin_position")
		if origin_value is Vector3:
			return origin_value
	return token.global_position


func _hide_spell_preview() -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool != null:
		measurement_tool.call("hide_spell_preview")


func _hide_spell_range_preview() -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool != null:
		measurement_tool.call("hide_spell_range_preview")


func _adjust_point_depth(step_cells: float) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool != null:
		measurement_tool.call(
			"adjust_spell_target_depth",
			step_cells
		)


func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "SpellPanel"
	panel.anchor_left = 0.0
	panel.anchor_top = 0.5
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 8.0
	panel.offset_top = 4.0
	panel.offset_right = -8.0
	panel.offset_bottom = -8.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.hide()
	ui_root.add_child(panel)

	var outer_margin: MarginContainer = MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 12)
	outer_margin.add_theme_constant_override("margin_right", 12)
	outer_margin.add_theme_constant_override("margin_top", 10)
	outer_margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(outer_margin)

	var root_layout: VBoxContainer = VBoxContainer.new()
	root_layout.add_theme_constant_override("separation", 8)
	outer_margin.add_child(root_layout)

	var header: HBoxContainer = HBoxContainer.new()
	root_layout.add_child(header)

	var title: Label = Label.new()
	title.text = "Incantesimi"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_button: Button = Button.new()
	close_button.text = "Chiudi"
	close_button.custom_minimum_size = Vector2(72, 28)
	close_button.pressed.connect(close_panel)
	header.add_child(close_button)

	var body: HSplitContainer = HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 390
	root_layout.add_child(body)

	var browser: VBoxContainer = VBoxContainer.new()
	browser.custom_minimum_size = Vector2(360, 0)
	browser.add_theme_constant_override("separation", 6)
	body.add_child(browser)

	search_input = LineEdit.new()
	search_input.placeholder_text = "Cerca incantesimo..."
	search_input.clear_button_enabled = true
	search_input.text_changed.connect(_refresh_search_results)
	browser.add_child(search_input)

	var search_label: Label = Label.new()
	search_label.text = "Risultati ricerca"
	search_label.add_theme_font_size_override("font_size", 12)
	browser.add_child(search_label)

	search_results = ItemList.new()
	search_results.custom_minimum_size = Vector2(0, 78)
	search_results.select_mode = ItemList.SELECT_SINGLE
	search_results.item_selected.connect(_on_search_item_selected)
	browser.add_child(search_results)

	var class_label: Label = Label.new()
	class_label.text = "Liste incantesimi per classe"
	class_label.add_theme_font_size_override("font_size", 12)
	browser.add_child(class_label)

	class_tree = Tree.new()
	class_tree.hide_root = true
	class_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	class_tree.item_selected.connect(_on_tree_item_selected)
	browser.add_child(class_tree)

	var details: VBoxContainer = VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	body.add_child(details)

	spell_title = Label.new()
	spell_title.text = "Seleziona un incantesimo"
	spell_title.add_theme_font_size_override("font_size", 22)
	details.add_child(spell_title)

	spell_meta = Label.new()
	spell_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spell_meta.modulate = Color(0.76, 0.79, 0.86, 1.0)
	details.add_child(spell_meta)

	spell_description = RichTextLabel.new()
	spell_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spell_description.fit_content = false
	spell_description.scroll_active = true
	spell_description.selection_enabled = true
	details.add_child(spell_description)

	activate_button = Button.new()
	activate_button.text = "Attiva incantesimo"
	activate_button.custom_minimum_size = Vector2(0, 36)
	activate_button.disabled = true
	activate_button.pressed.connect(_activate_selected_spell)
	details.add_child(activate_button)


func _build_instruction_label() -> void:
	instruction_label = Label.new()
	instruction_label.name = "SpellInstruction"
	instruction_label.anchor_left = 0.2
	instruction_label.anchor_top = 0.0
	instruction_label.anchor_right = 0.8
	instruction_label.anchor_bottom = 0.0
	instruction_label.offset_top = 52.0
	instruction_label.offset_bottom = 86.0
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 18)
	instruction_label.add_theme_color_override(
		"font_outline_color",
		Color(0.0, 0.0, 0.0, 0.9)
	)
	instruction_label.add_theme_constant_override("outline_size", 5)
	instruction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	instruction_label.hide()
	ui_root.add_child(instruction_label)


func _populate_class_tree() -> void:
	class_tree.clear()
	var root: TreeItem = class_tree.create_item()

	for class_label: String in SpellCatalog.CLASS_NAMES:
		var class_item: TreeItem = class_tree.create_item(root)
		class_item.set_text(0, class_label)
		class_item.set_collapsed(true)

		for level: int in range(SpellCatalog.LEVEL_NAMES.size()):
			var level_item: TreeItem = class_tree.create_item(class_item)
			level_item.set_text(
				0,
				SpellCatalog.LEVEL_NAMES[level]
			)
			level_item.set_collapsed(true)

			var spells: Array[Dictionary] = (
				SpellCatalog.spells_for_class_and_level(
					class_label,
					level
				)
			)
			for spell_data: Dictionary in spells:
				var spell_item: TreeItem = class_tree.create_item(level_item)
				spell_item.set_text(
					0,
					String(spell_data.get("name", "Incantesimo"))
				)
				spell_item.set_metadata(
					0,
					String(spell_data.get("id", ""))
				)


func _refresh_search_results(query: String) -> void:
	search_results.clear()
	var normalized_query: String = query.strip_edges().to_lower()

	for spell_data: Dictionary in SpellCatalog.all_spells():
		var spell_name: String = String(spell_data.get("name", ""))
		if (
			not normalized_query.is_empty()
			and normalized_query not in spell_name.to_lower()
		):
			continue

		var index: int = search_results.add_item(spell_name)
		search_results.set_item_metadata(
			index,
			String(spell_data.get("id", ""))
		)


func _on_search_item_selected(index: int) -> void:
	var spell_id: String = String(search_results.get_item_metadata(index))
	_select_spell(spell_id)


func _on_tree_item_selected() -> void:
	var item: TreeItem = class_tree.get_selected()
	if item == null:
		return

	var metadata: Variant = item.get_metadata(0)
	if metadata == null:
		return

	var spell_id: String = String(metadata)
	if spell_id.is_empty():
		return
	_select_spell(spell_id)


func _select_spell(spell_id: String) -> void:
	var spell_data: Dictionary = SpellCatalog.spell(spell_id)
	if spell_data.is_empty():
		return

	_selected_spell_id = spell_id
	spell_title.text = String(spell_data.get("name", "Incantesimo"))

	var classes_value: Variant = spell_data.get("classes", [])
	var classes_text: String = ""
	if classes_value is Array:
		var class_names: PackedStringArray = PackedStringArray()
		for class_value: Variant in classes_value:
			class_names.append(String(class_value))
		classes_text = ", ".join(class_names)

	var target_text: String = String(
		spell_data.get("target", "Self")
	)
	var area_text: String = String(
		spell_data.get("area", "")
	)
	if area_text.is_empty():
		if String(spell_data.get("aoe_shape", "")) == "cone":
			area_text = "%d-foot cone" % (
				int(spell_data.get("aoe_length_cells", 0)) * 5
			)

	spell_meta.text = (
		"%s · %s\n"
		+ "Tempo di lancio: %s | Range: %s\n"
		+ "Bersaglio: %s | Area: %s\n"
		+ "Componenti: %s | Durata: %s\n"
		+ "Classi: %s"
	) % [
		SpellCatalog.LEVEL_NAMES[int(spell_data.get("level", 0))],
		String(spell_data.get("school", "")),
		String(spell_data.get("casting_time", "")),
		String(spell_data.get("range", "")),
		target_text,
		area_text,
		String(spell_data.get("components", "")),
		String(spell_data.get("duration", "")),
		classes_text
	]

	spell_description.text = (
		String(spell_data.get("description", ""))
		+ "\n\nAi livelli superiori: "
		+ String(spell_data.get("higher_levels", ""))
	)
	activate_button.disabled = false


func _activate_selected_spell() -> void:
	if _selected_spell_id.is_empty():
		return

	var spell_data: Dictionary = SpellCatalog.spell(_selected_spell_id)
	if spell_data.is_empty():
		return

	var target_mode: String = String(
		spell_data.get("target_mode", "")
	)
	if target_mode not in [
		"self_token",
		"token_then_point",
		"token_then_token",
		"token_then_direction"
	]:
		return

	_pending_spell_id = _selected_spell_id
	_targeting_phase = "caster"
	_pending_caster = null
	_directional_pitch_degrees = 0

	var measurement_tool: Node = _measurement_tool()
	if measurement_tool != null:
		measurement_tool.call("set_measurement_mode", false)
	var measurement_label: Label = board_root.get_node_or_null(
		"UI/MeasurementModeLabel"
	) as Label
	if measurement_label != null:
		measurement_label.hide()

	var camera: Camera3D = board_root.get_node_or_null("Camera3D") as Camera3D
	if (
		camera != null
		and camera.has_method("is_first_person")
		and bool(camera.call("is_first_person"))
		and camera.has_method("exit_first_person")
	):
		camera.call("exit_first_person")

	panel.hide()
	board_root.set("_ui_owns_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if _selected_spell_id == "burning_hands":
		_update_directional_instruction(spell_data)
	else:
		_set_instruction(
			"%s: mira un token e clicca per scegliere il caster · WASD + mouse per muoverti · Esc per annullare"
			% String(spell_data.get("name", "Incantesimo"))
		)


func _cast_spell_from_caster(
	caster: Node3D,
	spell_data: Dictionary
) -> void:
	var spell_id: String = String(spell_data.get("id", ""))
	if spell_id == "burning_hands":
		_cast_directional_aoe(caster, spell_data)


func _cast_spell_at_point(
	_caster: Node3D,
	target_point: Vector3,
	spell_data: Dictionary
) -> void:
	var spell_id: String = String(spell_data.get("id", ""))
	if spell_id == "fireball":
		_cast_fireball(target_point, spell_data)
	elif spell_id == "darkness":
		_cast_persistent_sphere(target_point, spell_data)


func _cast_directional_aoe(
	caster: Node3D,
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var geometry: Dictionary = _directional_spell_geometry(
		caster,
		spell_data
	)
	if geometry.is_empty():
		return

	var duration: float = float(
		spell_data.get("transient_seconds", 5.0)
	)

	measurement_tool.call(
		"show_transient_aoe",
		geometry.get("start", Vector3.ZERO),
		geometry.get("end", Vector3.ZERO),
		String(spell_data.get("aoe_shape", "cone")),
		duration,
		String(spell_data.get("id", ""))
	)


func _cast_directional_spell_to_point(
	caster: Node3D,
	target_point: Vector3,
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var geometry: Dictionary = _direction_geometry_from_point(
		caster,
		target_point,
		spell_data
	)
	if geometry.is_empty():
		return

	measurement_tool.call(
		"show_transient_aoe",
		geometry.get("start", Vector3.ZERO),
		geometry.get("end", Vector3.ZERO),
		String(spell_data.get("aoe_shape", "line")),
		float(spell_data.get("transient_seconds", 5.0)),
		String(spell_data.get("id", "lightning_bolt"))
	)


func _cast_spell_at_token(
	caster: Node3D,
	target: Node3D,
	spell_data: Dictionary
) -> void:
	if String(spell_data.get("id", "")) != "chromatic_orb":
		return

	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	measurement_tool.call(
		"show_spell_projectile",
		_token_spell_origin(caster),
		_token_spell_origin(target),
		String(spell_data.get("projectile_style", "chromatic_orb")),
		float(spell_data.get("transient_seconds", 5.0))
	)


func _cast_fireball(
	target_point: Vector3,
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var radius_feet: float = float(
		spell_data.get("aoe_radius_feet", 20.0)
	)
	var radius_world: float = (
		radius_feet / 5.0 * _cell_size()
	)
	var endpoint: Vector3 = (
		target_point + Vector3.RIGHT * radius_world
	)
	var duration: float = float(
		spell_data.get("transient_seconds", 5.0)
	)

	measurement_tool.call(
		"show_transient_aoe",
		target_point,
		endpoint,
		String(spell_data.get("aoe_shape", "sphere")),
		duration,
		String(spell_data.get("id", "fireball"))
	)


func _cast_persistent_sphere(
	target_point: Vector3,
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var radius_feet: float = float(
		spell_data.get("aoe_radius_feet", 15.0)
	)
	var radius_world: float = (
		radius_feet / 5.0 * _cell_size()
	)
	var endpoint: Vector3 = (
		target_point + Vector3.RIGHT * radius_world
	)

	measurement_tool.call(
		"add_aoe",
		target_point,
		endpoint,
		String(spell_data.get("aoe_shape", "sphere")),
		String(spell_data.get("id", ""))
	)


func _finish_cast() -> void:
	_hide_spell_preview()
	_hide_spell_range_preview()
	_pending_spell_id = ""
	_targeting_phase = ""
	_pending_caster = null
	_directional_pitch_degrees = 0
	instruction_label.hide()
	Input.mouse_mode = _restore_mouse_mode


func _cancel_pending_cast(restore_mouse: bool = true) -> void:
	_hide_spell_preview()
	_hide_spell_range_preview()
	_pending_spell_id = ""
	_targeting_phase = ""
	_pending_caster = null
	_directional_pitch_degrees = 0
	if instruction_label != null:
		instruction_label.hide()
	if restore_mouse:
		Input.mouse_mode = _restore_mouse_mode


func _adjust_directional_pitch(delta_degrees: int) -> void:
	_directional_pitch_degrees = clampi(
		_directional_pitch_degrees + delta_degrees,
		-90,
		90
	)
	var spell_data: Dictionary = SpellCatalog.spell(_pending_spell_id)
	_update_directional_instruction(spell_data)


func _update_directional_instruction(spell_data: Dictionary) -> void:
	var pitch_label: String = "frontale"
	if _directional_pitch_degrees > 0:
		pitch_label = "+%d° verso l'alto" % _directional_pitch_degrees
	elif _directional_pitch_degrees < 0:
		pitch_label = "%d° verso il basso" % abs(_directional_pitch_degrees)

	_set_instruction(
		"%s: mira un token e clicca · ↑/↓ inclinazione: %s · WASD + mouse per muoverti · Esc per annullare"
		% [
			String(spell_data.get("name", "Incantesimo")),
			pitch_label
		]
	)




func _measurement_tool() -> Node:
	if board_root == null or not is_instance_valid(board_root):
		return null
	return board_root.get_node_or_null("MeasurementTool")


func _cell_size() -> float:
	return maxf(float(board_root.get("cell_size")), 0.001)


func _set_instruction(message: String) -> void:
	instruction_label.text = message
	instruction_label.show()
