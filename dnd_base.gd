extends Node3D

const CONTEXT_CREATE_TOKEN := 1
const CONTEXT_DELETE_SELECTED := 2
const CONTEXT_ROTATE_LEFT := 3
const CONTEXT_ROTATE_RIGHT := 4
const CONTEXT_TOGGLE_GRID := 5
const CONTEXT_TOGGLE_VISION_CONES := 6
const CONTEXT_TOGGLE_GRID_3D := 7
const CONTEXT_FLYING := 8
const CONTEXT_MAIN_MENU := 9
const CAMPAIGN_EDITOR_SCENE_PATH := "res://vtt/editor/campaign_editor.tscn"

const ALL_COLLISION_LAYERS := 0xFFFFFFFF

const TOKEN_SIZES := [
	{"name": "Tiny", "footprint": 0.5},
	{"name": "Small", "footprint": 1.0},
	{"name": "Medium", "footprint": 1.0},
	{"name": "Large", "footprint": 2.0},
	{"name": "Huge", "footprint": 3.0},
	{"name": "Gargantuan", "footprint": 4.0},
]

@export var grid_visible_on_start: bool = false
@export var grid_3d_visible_on_start: bool = false
@export var vision_cones_visible_on_start: bool = false
@export var cell_size: float = 1.0
@export var token_spawn_height: float = 4.0
@export var token_scene: PackedScene

@onready var grid: MeshInstance3D = $Board/Grid
@onready var volumetric_grid: Node3D = $VolumetricGrid
@onready var camera: Camera3D = $Camera3D
@onready var tokens_root: Node3D = $Tokens
@onready var context_menu: PopupMenu = $UI/ContextMenu
@onready var color_dialog: ConfirmationDialog = $UI/TokenColorDialog
@onready var size_selector: OptionButton = $UI/TokenColorDialog/Content/VBox/SizeSelector
@onready var color_picker: ColorPicker = $UI/TokenColorDialog/Content/VBox/ColorPicker
@onready var measurement_tool: Node3D = $MeasurementTool
@onready var measurement_mode_label: Label = $UI/MeasurementModeLabel

var _pending_spawn_position: Vector3 = Vector3.ZERO
var _has_pending_spawn_position: bool = false
var _selected_tokens: Array[CharacterBody3D] = []
var _ui_owns_mouse: bool = false
var _vision_cones_visible: bool = false
var _grid_visible: bool = false
var surface_grid: Node
var board_sync: Node
var share_dialog: AcceptDialog
var share_host: LineEdit
var share_key: LineEdit
var share_status: Label
var token_drag: Node


func _ready() -> void:
	surface_grid = preload("res://surface_grid.gd").new()
	surface_grid.name = "SurfaceGrid"
	add_child(surface_grid)
	surface_grid.setup(self, cell_size)

	# Board/Grid is kept only as a compatibility/style source for older
	# encounter scripts. The visible 2D grid now comes from solid surfaces.
	grid.visible = false

	set_grid_visible(grid_visible_on_start)
	set_grid_3d_visible(grid_3d_visible_on_start)
	set_vision_cones_visible(vision_cones_visible_on_start)

	context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	context_menu.popup_hide.connect(_on_context_menu_hidden)

	color_dialog.confirmed.connect(_on_token_dialog_confirmed)
	color_dialog.canceled.connect(_on_token_dialog_canceled)
	color_dialog.close_requested.connect(_on_token_dialog_canceled)

	size_selector.clear()
	for token_size: Dictionary in TOKEN_SIZES:
		size_selector.add_item(String(token_size.get("name", "Medium")))
	size_selector.select(2)

	volumetric_grid.call("set_camera", camera)
	measurement_tool.call("set_camera", camera)
	measurement_tool.call("set_volumetric_grid", volumetric_grid)
	measurement_tool.call("set_measurement_mode", false)
	measurement_mode_label.visible = false
	token_drag = preload("res://interaction/token_drag.gd").new()
	add_child(token_drag)
	token_drag.setup(self)
	board_sync = preload("res://network/board_sync.gd").new()
	add_child(board_sync)
	board_sync.setup(self, token_scene, tokens_root, measurement_tool)
	_build_share_dialog()

	var runtime_toolbar: Node = (
		preload("res://vtt/runtime_toolbar.gd").new() as Node
	)
	runtime_toolbar.name = "RuntimeToolbarController"
	add_child(runtime_toolbar)
	runtime_toolbar.call("setup", self)

	_capture_mouse()


func _process(_delta: float) -> void:
	_clean_selection()

	if _ui_owns_mouse and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode in [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT] and not color_dialog.visible:
		_clean_selection()
		if not _selected_tokens.is_empty():
			if event.pressed and not event.echo:
				_unhandled_input(event)
			get_viewport().set_input_as_handled()
			return
	if token_drag != null and token_drag.active and token_drag.handle_event(event):
		get_viewport().set_input_as_handled()
		return
	if not color_dialog.visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_on_token_dialog_confirmed()
			color_dialog.hide()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _ui_owns_mouse:
		return

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		var aoe_screen_position: Vector2 = (
			_screen_center()
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else event.position
		)
		if measurement_tool.remove_aoe_at_screen(aoe_screen_position):
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and measurement_tool.is_measurement_mode():
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				measurement_tool.begin_measurement()
			else:
				measurement_tool.end_measurement()
			get_viewport().set_input_as_handled()
			return
	if token_drag != null and token_drag.handle_event(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_G:
			toggle_grid()
			get_viewport().set_input_as_handled()
			return

		if event.keycode == KEY_3 or event.keycode == KEY_KP_3:
			toggle_grid_3d()
			get_viewport().set_input_as_handled()
			return

		if event.keycode == KEY_R:
			_toggle_measurement_mode()
			get_viewport().set_input_as_handled()
			return

		if event.keycode == KEY_ESCAPE:
			if _ui_owns_mouse:
				return

			if camera.has_method("is_first_person") \
			and bool(camera.call("is_first_person")):
				camera.call("exit_first_person")
				_capture_mouse()
				get_viewport().set_input_as_handled()
				return

			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_release_mouse()
			else:
				_capture_mouse()
			get_viewport().set_input_as_handled()
			return

		_clean_selection()
		if not _selected_tokens.is_empty():
			if event.shift_pressed:
				if event.keycode == KEY_UP or event.keycode == KEY_DOWN:
					for token in _selected_tokens:
						token.nudge_vertical(1 if event.keycode == KEY_UP else -1)
					get_viewport().set_input_as_handled()
					return
				if event.keycode == KEY_LEFT:
					_rotate_selected(-1)
					get_viewport().set_input_as_handled()
					return
				elif event.keycode == KEY_RIGHT:
					_rotate_selected(1)
					get_viewport().set_input_as_handled()
					return

			var direction: Vector2i = Vector2i.ZERO
			match event.keycode:
				KEY_LEFT:
					direction = Vector2i(-1, 0)
				KEY_RIGHT:
					direction = Vector2i(1, 0)
				KEY_UP:
					direction = Vector2i(0, -1)
				KEY_DOWN:
					direction = Vector2i(0, 1)

			if direction != Vector2i.ZERO and not event.shift_pressed:
				_move_selected(direction)
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_interact_or_select_under_mouse(event.position, event.shift_pressed, event.ctrl_pressed)
			elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				_show_context_menu(event.position)
			return

		if bool(measurement_tool.call("is_measurement_mode")):
			if event.pressed \
			and event.button_index == MOUSE_BUTTON_WHEEL_UP:
				measurement_tool.call("adjust_air_depth", -1.0)
				get_viewport().set_input_as_handled()
				return
			elif event.pressed \
			and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				measurement_tool.call("adjust_air_depth", 1.0)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					measurement_tool.call("begin_measurement")
				else:
					measurement_tool.call("end_measurement")
				get_viewport().set_input_as_handled()
				return

		if not event.pressed:
			return

		if event.button_index == MOUSE_BUTTON_RIGHT:
			_show_context_menu(_screen_center())
			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			_interact_or_select_under_mouse(
				_screen_center(),
				event.shift_pressed,
				event.ctrl_pressed
			)
			get_viewport().set_input_as_handled()


func toggle_grid() -> void:
	set_grid_visible(not _grid_visible)


func set_grid_visible(is_visible: bool) -> void:
	_grid_visible = is_visible
	grid.visible = false
	if surface_grid != null and is_instance_valid(surface_grid):
		surface_grid.set_grid_visible(is_visible)


func toggle_grid_3d() -> void:
	set_grid_3d_visible(not volumetric_grid.visible)


func set_grid_3d_visible(is_visible: bool) -> void:
	volumetric_grid.visible = is_visible


func toggle_vision_cones() -> void:
	set_vision_cones_visible(not _vision_cones_visible)


func set_vision_cones_visible(is_visible: bool) -> void:
	_vision_cones_visible = is_visible

	for child_node: Node in tokens_root.get_children():
		if child_node.is_in_group("dnd_token") \
		and child_node.has_method("set_vision_cone_visible"):
			child_node.call("set_vision_cone_visible", is_visible)


func _toggle_measurement_mode() -> void:
	measurement_tool.aoe_mode = false
	var enabled: bool = bool(measurement_tool.call("toggle_measurement_mode"))
	measurement_mode_label.visible = enabled

	if enabled:
		measurement_mode_label.text = "MISURAZIONE  [R per uscire]"
	else:
		measurement_mode_label.text = ""


func _show_context_menu(screen_position: Vector2) -> void:
	_clean_selection()
	_has_pending_spawn_position = false

	var hit: Dictionary = _raycast_from_screen(screen_position, 1 | 4, false)
	if not hit.is_empty():
		var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
		if hit_normal.dot(Vector3.UP) >= 0.5:
			_pending_spawn_position = hit.get("position", Vector3.ZERO)
			_has_pending_spawn_position = true

	context_menu.clear()

	# Area templates are measurement tools, so keep them out of the normal
	# interaction menu. They appear only after entering measurement mode with R.
	if measurement_tool.is_measurement_mode():
		context_menu.add_item("AoE: sfera", 20)
		context_menu.add_item("AoE: cubo", 21)
		context_menu.add_item("AoE: cono", 22)
		context_menu.add_item("AoE: linea", 23)
		context_menu.add_item("Cancella tutte le AoE", 24)
		context_menu.add_separator()

	context_menu.add_item("Condividi mappa / Tailscale", 25)
	if scene_file_path != CAMPAIGN_EDITOR_SCENE_PATH:
		context_menu.add_item("Torna al menu VTT", CONTEXT_MAIN_MENU)
	context_menu.add_separator()

	if _grid_visible:
		context_menu.add_item("Nascondi griglia 2D", CONTEXT_TOGGLE_GRID)
	else:
		context_menu.add_item("Mostra griglia 2D", CONTEXT_TOGGLE_GRID)

	if volumetric_grid.visible:
		context_menu.add_item("Nascondi griglia 3D", CONTEXT_TOGGLE_GRID_3D)
	else:
		context_menu.add_item("Mostra griglia 3D", CONTEXT_TOGGLE_GRID_3D)

	if _vision_cones_visible:
		context_menu.add_item(
			"Nascondi coni visivi dei token",
			CONTEXT_TOGGLE_VISION_CONES
		)
	else:
		context_menu.add_item(
			"Mostra coni visivi dei token",
			CONTEXT_TOGGLE_VISION_CONES
		)

	if _has_pending_spawn_position:
		context_menu.add_separator()
		context_menu.add_item("Genera token", CONTEXT_CREATE_TOKEN)

	if not _selected_tokens.is_empty():
		context_menu.add_separator()

		var count: int = _selected_tokens.size()
		var suffix: String = "" if count == 1 else " (%d)" % count
		context_menu.add_check_item("Volante" + suffix, CONTEXT_FLYING)
		context_menu.set_item_checked(context_menu.get_item_index(CONTEXT_FLYING), _selected_tokens.all(func(token): return token.flying))

		context_menu.add_item(
			"Ruota 90° a sinistra" + suffix,
			CONTEXT_ROTATE_LEFT
		)
		context_menu.add_item(
			"Ruota 90° a destra" + suffix,
			CONTEXT_ROTATE_RIGHT
		)
		context_menu.add_separator()
		context_menu.add_item(
			"Elimina token selezionati" + suffix,
			CONTEXT_DELETE_SELECTED
		)

	_ui_owns_mouse = true
	_release_mouse()
	context_menu.position = Vector2i(screen_position)
	context_menu.popup()
	call_deferred("_release_mouse")


func _on_context_menu_id_pressed(id: int) -> void:
	if id >= 20 and id <= 23:
		measurement_tool.set_aoe_mode(["sphere", "cube", "cone", "line"][id - 20])
		measurement_mode_label.text = "AoE: trascina clic sinistro | R per uscire"
		measurement_mode_label.show()
		_close_context_menu_to_game()
		return
	if id == 24:
		measurement_tool.clear_persistent_aoes()
		_close_context_menu_to_game()
		return
	if id == 25:
		_ui_owns_mouse = true
		share_dialog.popup_centered(Vector2i(580, 330))
		_release_mouse()
		return
	match id:
		CONTEXT_MAIN_MENU:
			_ui_owns_mouse = false
			context_menu.hide()
			var campaign_manager: Node = get_node_or_null("/root/CampaignManager")
			if campaign_manager != null:
				campaign_manager.call("return_to_main_menu")

		CONTEXT_FLYING:
			var enabled := not _selected_tokens.all(func(token): return token.flying)
			for token in _selected_tokens:
				token.set_flying(enabled)
			_close_context_menu_to_game()
		CONTEXT_TOGGLE_GRID:
			toggle_grid()
			_close_context_menu_to_game()

		CONTEXT_TOGGLE_GRID_3D:
			toggle_grid_3d()
			_close_context_menu_to_game()

		CONTEXT_TOGGLE_VISION_CONES:
			toggle_vision_cones()
			_close_context_menu_to_game()

		CONTEXT_CREATE_TOKEN:
			if not _has_pending_spawn_position:
				return
			_ui_owns_mouse = true
			size_selector.select(2)
			color_picker.color = Color.WHITE
			color_dialog.popup_centered_clamped(Vector2i(560, 590), 0.9)
			call_deferred("_release_mouse")

		CONTEXT_DELETE_SELECTED:
			_delete_selected()
			_close_context_menu_to_game()

		CONTEXT_ROTATE_LEFT:
			_rotate_selected(-1)
			_close_context_menu_to_game()

		CONTEXT_ROTATE_RIGHT:
			_rotate_selected(1)
			_close_context_menu_to_game()


func _close_context_menu_to_game() -> void:
	_ui_owns_mouse = false
	_capture_mouse()


func _on_context_menu_hidden() -> void:
	if color_dialog.visible or (is_instance_valid(share_dialog) and share_dialog.visible):
		return
	call_deferred("_finish_context_menu_close")


func _finish_context_menu_close() -> void:
	if color_dialog.visible or (is_instance_valid(share_dialog) and share_dialog.visible):
		return
	_ui_owns_mouse = false
	_capture_mouse()


func _on_token_dialog_confirmed() -> void:
	var selected_index: int = size_selector.selected
	if selected_index < 0 or selected_index >= TOKEN_SIZES.size():
		selected_index = 2

	var selected_size: Dictionary = TOKEN_SIZES[selected_index]
	_spawn_token(
		color_picker.color,
		String(selected_size.get("name", "Medium")),
		float(selected_size.get("footprint", 1.0))
	)

	_ui_owns_mouse = false
	_capture_mouse()


func _on_token_dialog_canceled() -> void:
	_ui_owns_mouse = false
	_capture_mouse()


func _spawn_token(
	token_color: Color,
	size_name: String,
	footprint_cells: float
) -> void:
	if token_scene == null:
		push_error("DnDBase: token_scene non assegnata.")
		return

	var token_instance: Node = token_scene.instantiate()
	if not (token_instance is CharacterBody3D):
		push_error(
			"DnDBase: token_scene deve avere un CharacterBody3D come nodo root."
		)
		token_instance.queue_free()
		return

	var token: CharacterBody3D = token_instance as CharacterBody3D
	tokens_root.add_child(token)

	token.global_position = Vector3(
		_pending_spawn_position.x,
		_pending_spawn_position.y + token_spawn_height,
		_pending_spawn_position.z
	)

	if token.has_method("configure"):
		token.call(
			"configure",
			token_color,
			cell_size,
			size_name,
			footprint_cells
		)

	if token.has_method("set_vision_cone_visible"):
		token.call("set_vision_cone_visible", _vision_cones_visible)

	_replace_selection(token)


func _interact_or_select_under_mouse(
	screen_position: Vector2,
	additive_selection: bool,
	first_person_request: bool
) -> void:
	var hit: Dictionary = _raycast_from_screen(
		screen_position,
		ALL_COLLISION_LAYERS,
		true
	)

	if hit.is_empty():
		if not additive_selection:
			_clear_selection()
		return

	var collider: Node = hit.get("collider") as Node
	if collider == null:
		if not additive_selection:
			_clear_selection()
		return

	var target: Node = _find_interaction_target(collider)

	if target != null and target.is_in_group("dnd_token"):
		var token: CharacterBody3D = target as CharacterBody3D

		if first_person_request:
			_replace_selection(token)
			if camera.has_method("enter_first_person"):
				camera.call("enter_first_person", token)
			return

		if additive_selection:
			_add_to_selection(token)
		else:
			_replace_selection(token)
		return

	if target != null and target.has_method("interact"):
		target.call("interact")
		if not additive_selection:
			_clear_selection()
		return

	if not additive_selection:
		_clear_selection()


func _find_interaction_target(start_node: Node) -> Node:
	var current: Node = start_node

	while current != null and current != self:
		if current.is_in_group("dnd_token") or current.has_method("interact"):
			return current
		current = current.get_parent()

	return null


func _replace_selection(token: CharacterBody3D) -> void:
	_clear_selection()
	_add_to_selection(token)


func _add_to_selection(token: CharacterBody3D) -> void:
	if token == null or not is_instance_valid(token):
		return
	if token in _selected_tokens:
		return

	_selected_tokens.append(token)
	if token.has_method("set_selected"):
		token.call("set_selected", true)


func _clear_selection() -> void:
	for token: CharacterBody3D in _selected_tokens:
		if token != null and is_instance_valid(token):
			if token.has_method("set_selected"):
				token.call("set_selected", false)

	_selected_tokens.clear()


func _clean_selection() -> void:
	var cleaned: Array[CharacterBody3D] = []

	for token: CharacterBody3D in _selected_tokens:
		if token != null and is_instance_valid(token):
			cleaned.append(token)

	_selected_tokens = cleaned


func _move_selected(direction: Vector2i) -> void:
	_clean_selection()

	for token: CharacterBody3D in _selected_tokens:
		if token.has_method("nudge_grid"):
			token.call("nudge_grid", direction)


func _rotate_selected(quarter_turns: int) -> void:
	_clean_selection()

	for token: CharacterBody3D in _selected_tokens:
		if token.has_method("rotate_grid"):
			token.call("rotate_grid", quarter_turns)


func _delete_selected() -> void:
	_clean_selection()

	var deleting: Array[CharacterBody3D] = _selected_tokens.duplicate()
	_selected_tokens.clear()

	if camera.has_method("get_first_person_target"):
		var fp_target: Variant = camera.call("get_first_person_target")
		if fp_target is CharacterBody3D and fp_target in deleting:
			camera.call("exit_first_person")

	for token: CharacterBody3D in deleting:
		if token != null and is_instance_valid(token):
			token.queue_free()


func _raycast_from_screen(
	screen_position: Vector2,
	collision_mask: int,
	collide_with_areas: bool = false
) -> Dictionary:
	if not is_instance_valid(camera):
		return {}

	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	var ray_end: Vector3 = ray_origin + ray_direction * camera.far

	var query: PhysicsRayQueryParameters3D = (
		PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	)
	query.collision_mask = collision_mask
	query.collide_with_areas = collide_with_areas
	query.collide_with_bodies = true

	return get_world_3d().direct_space_state.intersect_ray(query)


func _screen_center() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5


func _capture_mouse() -> void:
	if not _ui_owns_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_share_dialog() -> void:
	share_dialog = AcceptDialog.new()
	share_dialog.title = "Condivisione mappa · Tailscale / LAN"
	$UI.add_child(share_dialog)
	share_dialog.confirmed.connect(_close_context_menu_to_game)
	share_dialog.canceled.connect(_close_context_menu_to_game)
	var layout := VBoxContainer.new()
	share_dialog.add_child(layout)
	var info := Label.new()
	info.text = "Stessa versione e stessa scena su entrambi i computer.\nUsa l'IP Tailscale (100.x.x.x) o il nome MagicDNS."
	layout.add_child(info)
	share_host = LineEdit.new()
	share_host.placeholder_text = "Indirizzo del destinatario"
	layout.add_child(share_host)
	share_key = LineEdit.new()
	share_key.placeholder_text = "Codice sessione uguale sui due computer"
	share_key.secret = true
	layout.add_child(share_key)
	var receive := CheckButton.new()
	receive.text = "Abilita ricezione (sostituisce lo stato della mappa)"
	layout.add_child(receive)
	receive.toggled.connect(func(enabled):
		var error: Error = board_sync.listen(enabled, share_key.text)
		if error != OK: receive.set_pressed_no_signal(false)
		share_key.editable = not receive.button_pressed
	)
	var send := Button.new()
	send.text = "Invia mappa"
	layout.add_child(send)
	send.pressed.connect(func(): board_sync.send_snapshot(share_host.text, share_key.text))
	share_status = Label.new()
	share_status.text = "Ricezione disattivata"
	layout.add_child(share_status)
	board_sync.status_changed.connect(func(message): share_status.text = message)
