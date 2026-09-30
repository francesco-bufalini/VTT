extends Node3D

const CONTEXT_CREATE_TOKEN := 1
const CONTEXT_DELETE_SELECTED := 2
const CONTEXT_ROTATE_LEFT := 3
const CONTEXT_ROTATE_RIGHT := 4
const CONTEXT_TOGGLE_GRID := 5
const CONTEXT_TOGGLE_VISION_CONES := 6
const CONTEXT_FLYING := 8
const CONTEXT_MAIN_MENU := 9
const CONTEXT_DISSOLVE_AOT := 10
const CONTEXT_SPELLS := 11
const CONTEXT_CAMERA_SETTINGS := 12
const CONTEXT_INITIATIVE := 13
const CONTEXT_TOKEN_DETAILS := 14
const CAMPAIGN_EDITOR_SCENE_PATH := "res://vtt/editor/campaign_editor.tscn"
const TOKEN_LIBRARY_MANIFEST := "res://assets/tokens/token_library.json"

const CAMERA_SPEED_DEFAULT := 5.0
const CAMERA_SENSITIVITY_DEFAULT := 0.002
const ALL_COLLISION_LAYERS := 0xFFFFFFFF
const UNDO_LIMIT := 50

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
var _pending_aoe_index: int = -1
var _context_token: CharacterBody3D = null
var _selected_tokens: Array[CharacterBody3D] = []
var _ui_owns_mouse: bool = false
var _vision_cones_visible: bool = false
var board_sync: Node
var share_dialog: AcceptDialog
var share_host: LineEdit
var share_key: LineEdit
var share_status: Label
var camera_settings_dialog: AcceptDialog
var camera_speed_slider: HSlider
var camera_sensitivity_slider: HSlider
var camera_speed_value_label: Label
var camera_sensitivity_value_label: Label
var token_name_input: LineEdit
var token_state_dialog: ConfirmationDialog
var token_state_name: LineEdit
var token_state_grid: GridContainer
var token_state_checks: Dictionary = {}
var _editing_token: CharacterBody3D
var token_drag: Node
var spell_system: Node
var initiative_tracker: Node
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _undo_restoring: bool = false


func _ready() -> void:
	# Unica griglia tattica: la VolumetricGrid collision-aware.
	# grid_3d_visible_on_start resta come alias di compatibilita per scene
	# create prima della rimozione della SurfaceGrid.
	set_grid_visible(grid_visible_on_start or grid_3d_visible_on_start)
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
	_configure_default_token_size_selector()

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
	_build_camera_settings_dialog()
	_ensure_token_name_input()
	_build_token_state_dialog()

	spell_system = preload("res://vtt/spells/spell_system.gd").new()
	spell_system.name = "SpellSystem"
	add_child(spell_system)
	spell_system.call("setup", self)

	initiative_tracker = preload("res://vtt/initiative_tracker.gd").new()
	initiative_tracker.name = "InitiativeTracker"
	add_child(initiative_tracker)
	initiative_tracker.call("setup", self)

	var runtime_toolbar: Node = (
		preload("res://vtt/runtime_toolbar.gd").new() as Node
	)
	runtime_toolbar.name = "RuntimeToolbarController"
	add_child(runtime_toolbar)
	runtime_toolbar.call("setup", self)

	_capture_mouse()


func _configure_default_token_size_selector() -> void:
	size_selector.disabled = false
	size_selector.tooltip_text = ""

	if not FileAccess.file_exists(TOKEN_LIBRARY_MANIFEST):
		return
	var file := FileAccess.open(TOKEN_LIBRARY_MANIFEST, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return

	var default_value: Variant = (parsed as Dictionary).get("default", {})
	if not default_value is Dictionary:
		return
	var profile := default_value as Dictionary
	if String(profile.get("obj", "")).strip_edges().is_empty():
		return

	var default_size := String(profile.get("size_name", "Medium"))
	for index in range(TOKEN_SIZES.size()):
		if String(TOKEN_SIZES[index].get("name", "")) == default_size:
			size_selector.select(index)
			break

	# Una miniatura fisica mantiene la taglia definita dalla propria base.
	size_selector.disabled = true
	size_selector.tooltip_text = (
		"Taglia determinata automaticamente dalla base della miniatura: "
		+ default_size
	)


func _process(_delta: float) -> void:
	_clean_selection()

	if _ui_owns_mouse and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if (
		spell_system != null
		and is_instance_valid(spell_system)
		and bool(spell_system.call("is_panel_open"))
	):
		return

	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.ctrl_pressed
		and event.keycode == KEY_Z
	):
		if (
			spell_system != null
			and is_instance_valid(spell_system)
			and bool(spell_system.call("is_targeting"))
			and bool(spell_system.call("handle_input", event))
		):
			get_viewport().set_input_as_handled()
			return
		if undo_last_action():
			get_viewport().set_input_as_handled()
			return

	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.ctrl_pressed
		and event.keycode == KEY_Y
	):
		if redo_last_action():
			get_viewport().set_input_as_handled()
			return

	if (
		spell_system != null
		and is_instance_valid(spell_system)
		and bool(spell_system.call("is_targeting"))
		and event is InputEventKey
		and event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
	):
		if bool(spell_system.call("handle_input", event)):
			get_viewport().set_input_as_handled()
		else:
			get_viewport().set_input_as_handled()
		return
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
	if bool(measurement_tool.call("is_movable_aoe_dragging")):
		if event is InputEventMouseMotion:
			measurement_tool.call(
				"update_movable_aoe_drag",
				event.position
			)
			get_viewport().set_input_as_handled()
			return
		if (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and not event.pressed
		):
			measurement_tool.call("finish_movable_aoe_drag", true)
			get_viewport().set_input_as_handled()
			return
		if (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_RIGHT
			and event.pressed
		):
			measurement_tool.call("finish_movable_aoe_drag", false)
			get_viewport().set_input_as_handled()
			return
		if (
			event is InputEventKey
			and event.pressed
			and event.keycode == KEY_ESCAPE
		):
			measurement_tool.call("finish_movable_aoe_drag", false)
			get_viewport().set_input_as_handled()
			return

	if (
		spell_system != null
		and is_instance_valid(spell_system)
		and bool(spell_system.call("handle_input", event))
	):
		get_viewport().set_input_as_handled()
		return

	if _ui_owns_mouse:
		return

	# Le AoE mobili si trascinano come token, pur mantenendo la resa grafica
	# dell'area. Le AoE statiche mantengono il comportamento precedente.
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
		var aoe_index: int = int(
			measurement_tool.call(
				"get_aoe_index_at_screen",
				aoe_screen_position
			)
		)
		if aoe_index >= 0:
			if bool(measurement_tool.call("is_movable_aoe", aoe_index)):
				if bool(
					measurement_tool.call(
						"begin_movable_aoe_drag",
						aoe_index
					)
				):
					get_viewport().set_input_as_handled()
					return
			elif bool(measurement_tool.call("dissolve_aoe", aoe_index)):
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton and measurement_tool.is_measurement_mode():
		if (
			event.pressed
			and event.button_index in [
				MOUSE_BUTTON_WHEEL_UP,
				MOUSE_BUTTON_WHEEL_DOWN
			]
		):
			var wheel_step: int = (
				-1
				if event.button_index == MOUSE_BUTTON_WHEEL_UP
				else 1
			)
			if (
				measurement_tool.is_aoe_mode()
				and measurement_tool.is_dragging()
			):
				measurement_tool.adjust_aoe_color(wheel_step)
			else:
				measurement_tool.adjust_air_depth(float(wheel_step))
			get_viewport().set_input_as_handled()
			return

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
					push_undo_state()
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


func _capture_history_state() -> Dictionary:
	if board_sync == null or not is_instance_valid(board_sync):
		return {}

	var snapshot_value: Variant = board_sync.call("create_snapshot")
	if not snapshot_value is Dictionary:
		return {}
	var snapshot: Dictionary = snapshot_value as Dictionary
	if snapshot.is_empty():
		return {}

	return {
		"snapshot": snapshot.duplicate(true),
		"grid_visible": volumetric_grid.visible,
		"vision_visible": _vision_cones_visible
	}


func _append_history_state(
	stack: Array[Dictionary],
	state: Dictionary
) -> void:
	if state.is_empty():
		return
	stack.append(state.duplicate(true))
	if stack.size() > UNDO_LIMIT:
		stack.pop_front()


func push_undo_state() -> void:
	if _undo_restoring:
		return
	var state: Dictionary = _capture_history_state()
	if state.is_empty():
		return
	_append_history_state(_undo_stack, state)
	# Una nuova azione crea una nuova linea temporale: il redo precedente
	# non e' piu' applicabile.
	_redo_stack.clear()


func _apply_history_state(state: Dictionary) -> bool:
	var snapshot_value: Variant = state.get("snapshot", {})
	if not snapshot_value is Dictionary:
		return false

	_undo_restoring = true
	var applied: bool = bool(
		board_sync.call(
			"apply_snapshot",
			snapshot_value as Dictionary
		)
	)
	if applied:
		set_grid_visible(
			bool(state.get("grid_visible", volumetric_grid.visible))
		)
		set_vision_cones_visible(
			bool(state.get("vision_visible", _vision_cones_visible))
		)
	_undo_restoring = false
	return applied


func undo_last_action() -> bool:
	if _undo_stack.is_empty():
		return false
	if board_sync == null or not is_instance_valid(board_sync):
		return false

	var current_state: Dictionary = _capture_history_state()
	if current_state.is_empty():
		return false
	var target_state: Dictionary = _undo_stack.pop_back()

	if not _apply_history_state(target_state):
		_append_history_state(_undo_stack, target_state)
		return false

	_append_history_state(_redo_stack, current_state)
	return true


func redo_last_action() -> bool:
	if _redo_stack.is_empty():
		return false
	if board_sync == null or not is_instance_valid(board_sync):
		return false

	var current_state: Dictionary = _capture_history_state()
	if current_state.is_empty():
		return false
	var target_state: Dictionary = _redo_stack.pop_back()

	if not _apply_history_state(target_state):
		_append_history_state(_redo_stack, target_state)
		return false

	_append_history_state(_undo_stack, current_state)
	return true

func toggle_spell_menu() -> void:
	if spell_system == null or not is_instance_valid(spell_system):
		return
	spell_system.call("toggle_panel")


func toggle_initiative_panel() -> void:
	if (
		initiative_tracker == null
		or not is_instance_valid(initiative_tracker)
	):
		return
	initiative_tracker.call("toggle_panel")


func show_initiative_panel() -> void:
	if (
		initiative_tracker == null
		or not is_instance_valid(initiative_tracker)
	):
		return
	initiative_tracker.call("show_panel")


func toggle_grid() -> void:
	push_undo_state()
	set_grid_visible(not volumetric_grid.visible)


func set_grid_visible(is_visible: bool) -> void:
	volumetric_grid.visible = is_visible


# Alias di compatibilita: ora esiste una sola griglia volumetrica.
func toggle_grid_3d() -> void:
	toggle_grid()


func set_grid_3d_visible(is_visible: bool) -> void:
	set_grid_visible(is_visible)


func toggle_vision_cones() -> void:
	push_undo_state()
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
	_pending_aoe_index = int(
		measurement_tool.call("get_aoe_index_at_screen", screen_position)
	)

	if _pending_aoe_index >= 0:
		context_menu.clear()
		context_menu.add_item("Dissolvi AoT", CONTEXT_DISSOLVE_AOT)
		_ui_owns_mouse = true
		_release_mouse()
		context_menu.position = Vector2i(screen_position)
		context_menu.popup()
		call_deferred("_release_mouse")
		return

	_context_token = null
	var token_hit: Dictionary = _raycast_from_screen(
		screen_position,
		ALL_COLLISION_LAYERS,
		true
	)
	if not token_hit.is_empty():
		var token_collider: Node = token_hit.get("collider") as Node
		if token_collider != null:
			var token_target: Node = _find_interaction_target(token_collider)
			if (
				token_target != null
				and token_target.is_in_group("dnd_token")
				and token_target is CharacterBody3D
			):
				_context_token = token_target as CharacterBody3D
				_replace_selection(_context_token)

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

	var initiative_visible: bool = (
		initiative_tracker != null
		and is_instance_valid(initiative_tracker)
		and bool(initiative_tracker.call("is_panel_visible"))
	)
	context_menu.add_item(
		"Nascondi iniziativa" if initiative_visible else "Mostra iniziativa",
		CONTEXT_INITIATIVE
	)
	context_menu.add_item("Condividi mappa / Tailscale", 25)
	if scene_file_path != CAMPAIGN_EDITOR_SCENE_PATH:
		context_menu.add_item("Torna al menu VTT", CONTEXT_MAIN_MENU)
	context_menu.add_separator()

	if volumetric_grid.visible:
		context_menu.add_item("Nascondi griglia", CONTEXT_TOGGLE_GRID)
	else:
		context_menu.add_item("Mostra griglia", CONTEXT_TOGGLE_GRID)

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

	context_menu.add_separator()
	context_menu.add_item("Velocità camera…", CONTEXT_CAMERA_SETTINGS)

	if _has_pending_spawn_position:
		context_menu.add_separator()
		context_menu.add_item("Genera token", CONTEXT_CREATE_TOKEN)

	if not _selected_tokens.is_empty():
		context_menu.add_separator()

		if _selected_tokens.size() == 1:
			context_menu.add_item("Nome e stati…", CONTEXT_TOKEN_DETAILS)

		if _context_token != null and is_instance_valid(_context_token):
			context_menu.add_item("Incantesimi", CONTEXT_SPELLS)
			context_menu.add_separator()

		var count: int = _selected_tokens.size()
		var suffix: String = "" if count == 1 else " (%d)" % count
		context_menu.add_check_item("Volante" + suffix, CONTEXT_FLYING)
		context_menu.set_item_checked(context_menu.get_item_index(CONTEXT_FLYING), _selected_tokens.all(func(token): return token.flying))

		context_menu.add_item(
			"Ruota 45° a sinistra" + suffix,
			CONTEXT_ROTATE_LEFT
		)
		context_menu.add_item(
			"Ruota 45° a destra" + suffix,
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
	if id == CONTEXT_INITIATIVE:
		toggle_initiative_panel()
		_close_context_menu_to_game()
		return

	if id == CONTEXT_SPELLS:
		if spell_system != null and is_instance_valid(spell_system):
			spell_system.call("open_panel")
		context_menu.hide()
		return

	if id == CONTEXT_TOKEN_DETAILS:
		open_selected_token_state_editor()
		return

	if id == CONTEXT_DISSOLVE_AOT:
		measurement_tool.call("dissolve_aoe", _pending_aoe_index)
		_pending_aoe_index = -1
		_close_context_menu_to_game()
		return
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
			push_undo_state()
			var enabled: bool = not _selected_tokens.all(func(token): return token.flying)
			for token in _selected_tokens:
				token.set_flying(enabled)
			_close_context_menu_to_game()
		CONTEXT_TOGGLE_GRID:
			toggle_grid()
			_close_context_menu_to_game()

		CONTEXT_TOGGLE_VISION_CONES:
			toggle_vision_cones()
			_close_context_menu_to_game()

		CONTEXT_CAMERA_SETTINGS:
			open_camera_settings()

		CONTEXT_CREATE_TOKEN:
			if not _has_pending_spawn_position:
				return
			_ui_owns_mouse = true
			size_selector.select(2)
			color_picker.color = Color.WHITE
			if token_name_input != null:
				token_name_input.clear()
			color_dialog.popup_centered_clamped(Vector2i(560, 640), 0.9)
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


func _get_camera_speed() -> float:
	if camera.has_method("get_move_speed"):
		return float(camera.call("get_move_speed"))
	return CAMERA_SPEED_DEFAULT


func _set_camera_speed(value: float) -> void:
	if camera.has_method("set_move_speed"):
		camera.call("set_move_speed", value)


func _get_camera_sensitivity() -> float:
	if camera.has_method("get_mouse_sensitivity"):
		return float(camera.call("get_mouse_sensitivity"))
	return CAMERA_SENSITIVITY_DEFAULT


func _set_camera_sensitivity(value: float) -> void:
	if camera.has_method("set_mouse_sensitivity"):
		camera.call("set_mouse_sensitivity", value)


func open_camera_settings() -> void:
	if camera_settings_dialog == null or not is_instance_valid(camera_settings_dialog):
		return

	camera_speed_slider.set_value_no_signal(_get_camera_speed())
	camera_sensitivity_slider.set_value_no_signal(_get_camera_sensitivity())
	_update_camera_settings_labels()

	_ui_owns_mouse = true
	if context_menu.visible:
		context_menu.hide()
	_release_mouse()
	camera_settings_dialog.popup_centered(Vector2i(460, 240))
	call_deferred("_release_mouse")


func _update_camera_settings_labels() -> void:
	if camera_speed_value_label != null:
		camera_speed_value_label.text = "Velocità: %.1f" % camera_speed_slider.value
	if camera_sensitivity_value_label != null:
		camera_sensitivity_value_label.text = (
			"Sensibilità: %.4f" % camera_sensitivity_slider.value
		)


func _on_camera_speed_slider_changed(value: float) -> void:
	_set_camera_speed(value)
	_update_camera_settings_labels()


func _on_camera_sensitivity_slider_changed(value: float) -> void:
	_set_camera_sensitivity(value)
	_update_camera_settings_labels()


func _close_camera_settings_to_game() -> void:
	_ui_owns_mouse = false
	_capture_mouse()


func _build_camera_settings_dialog() -> void:
	camera_settings_dialog = AcceptDialog.new()
	camera_settings_dialog.title = "Velocità camera"
	$UI.add_child(camera_settings_dialog)
	camera_settings_dialog.confirmed.connect(_close_camera_settings_to_game)
	camera_settings_dialog.canceled.connect(_close_camera_settings_to_game)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	camera_settings_dialog.add_child(layout)

	camera_speed_value_label = Label.new()
	layout.add_child(camera_speed_value_label)
	camera_speed_slider = HSlider.new()
	camera_speed_slider.min_value = 1.0
	camera_speed_slider.max_value = 100.0
	camera_speed_slider.step = 0.5
	camera_speed_slider.custom_minimum_size = Vector2(400, 24)
	camera_speed_slider.value_changed.connect(_on_camera_speed_slider_changed)
	layout.add_child(camera_speed_slider)

	camera_sensitivity_value_label = Label.new()
	layout.add_child(camera_sensitivity_value_label)
	camera_sensitivity_slider = HSlider.new()
	camera_sensitivity_slider.min_value = 0.0002
	camera_sensitivity_slider.max_value = 0.01
	camera_sensitivity_slider.step = 0.0001
	camera_sensitivity_slider.custom_minimum_size = Vector2(400, 24)
	camera_sensitivity_slider.value_changed.connect(
		_on_camera_sensitivity_slider_changed
	)
	layout.add_child(camera_sensitivity_slider)

	var defaults := Button.new()
	defaults.text = "Ripristina valori predefiniti"
	defaults.pressed.connect(
		func() -> void:
			camera_speed_slider.value = CAMERA_SPEED_DEFAULT
			camera_sensitivity_slider.value = CAMERA_SENSITIVITY_DEFAULT
	)
	layout.add_child(defaults)

	camera_speed_slider.set_value_no_signal(_get_camera_speed())
	camera_sensitivity_slider.set_value_no_signal(_get_camera_sensitivity())
	_update_camera_settings_labels()


func _ensure_token_name_input() -> void:
	var content_box: VBoxContainer = (
		color_dialog.get_node_or_null("Content/VBox") as VBoxContainer
	)
	if content_box == null:
		return

	token_name_input = content_box.get_node_or_null("TokenName") as LineEdit
	if token_name_input != null:
		return

	var label := Label.new()
	label.name = "TokenNameLabel"
	label.text = "Nome del token (opzionale)"
	content_box.add_child(label)
	content_box.move_child(label, 0)

	token_name_input = LineEdit.new()
	token_name_input.name = "TokenName"
	token_name_input.placeholder_text = "Es. Sariel, Guardia 1…"
	token_name_input.max_length = 80
	content_box.add_child(token_name_input)
	content_box.move_child(token_name_input, 1)


func _build_token_state_dialog() -> void:
	token_state_dialog = ConfirmationDialog.new()
	token_state_dialog.name = "TokenStateDialog"
	token_state_dialog.title = "Nome e stati del token"
	token_state_dialog.ok_button_text = "Applica"
	token_state_dialog.min_size = Vector2i(500, 610)
	$UI.add_child(token_state_dialog)

	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 14.0
	outer.offset_right = -14.0
	outer.offset_top = 48.0
	outer.offset_bottom = -58.0
	outer.add_theme_constant_override("separation", 8)
	token_state_dialog.add_child(outer)

	var name_label := Label.new()
	name_label.text = "Nome visualizzato sopra il token"
	outer.add_child(name_label)

	token_state_name = LineEdit.new()
	token_state_name.placeholder_text = "Lascia vuoto per non mostrare alcun nome"
	token_state_name.max_length = 80
	outer.add_child(token_state_name)

	var states_label := Label.new()
	states_label.text = "Condizioni D&D 5e"
	states_label.add_theme_font_size_override("font_size", 14)
	outer.add_child(states_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	token_state_grid = GridContainer.new()
	token_state_grid.columns = 2
	token_state_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	token_state_grid.add_theme_constant_override("h_separation", 16)
	token_state_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(token_state_grid)

	var help := Label.new()
	help.text = (
		"I pittogrammi degli stati attivi vengono mostrati sotto al nome. "
		+ "Il nome dell'iniziativa resta modificabile separatamente."
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 11)
	outer.add_child(help)

	token_state_dialog.confirmed.connect(_apply_token_state_editor)
	token_state_dialog.canceled.connect(_close_token_state_editor)
	token_state_dialog.close_requested.connect(_close_token_state_editor)


func open_selected_token_state_editor() -> void:
	_clean_selection()
	if _selected_tokens.size() != 1:
		_close_context_menu_to_game()
		return
	_open_token_state_editor(_selected_tokens[0])


func _open_token_state_editor(token: CharacterBody3D) -> void:
	if token_state_dialog == null or token == null or not is_instance_valid(token):
		return
	_editing_token = token
	token_state_name.text = (
		String(token.call("get_display_name"))
		if token.has_method("get_display_name")
		else ""
	)

	for child: Node in token_state_grid.get_children():
		child.queue_free()
	token_state_checks.clear()

	var current: Array = []
	if token.has_method("get_conditions"):
		var current_value: Variant = token.call("get_conditions")
		if current_value is Array:
			current = current_value as Array

	var definitions: Array = []
	if token.has_method("get_condition_definitions"):
		var definitions_value: Variant = token.call("get_condition_definitions")
		if definitions_value is Array:
			definitions = definitions_value as Array

	for value: Variant in definitions:
		if not value is Dictionary:
			continue
		var definition := value as Dictionary
		var condition_id := String(definition.get("id", ""))
		if condition_id.is_empty():
			continue
		var check := CheckButton.new()
		check.text = "%s  %s" % [
			String(definition.get("icon", "•")),
			String(definition.get("name", condition_id))
		]
		check.button_pressed = condition_id in current
		token_state_grid.add_child(check)
		token_state_checks[condition_id] = check

	_ui_owns_mouse = true
	if context_menu.visible:
		context_menu.hide()
	_release_mouse()
	token_state_dialog.popup_centered(Vector2i(500, 610))
	call_deferred("_release_mouse")


func _apply_token_state_editor() -> void:
	if _editing_token == null or not is_instance_valid(_editing_token):
		_close_token_state_editor()
		return

	push_undo_state()
	if _editing_token.has_method("set_display_name"):
		_editing_token.call("set_display_name", token_state_name.text)

	var active_conditions: Array[String] = []
	for condition_id: Variant in token_state_checks.keys():
		var check: CheckButton = token_state_checks[condition_id] as CheckButton
		if check != null and check.button_pressed:
			active_conditions.append(String(condition_id))
	if _editing_token.has_method("set_conditions"):
		_editing_token.call("set_conditions", active_conditions)

	_close_token_state_editor()


func _close_token_state_editor() -> void:
	_editing_token = null
	_ui_owns_mouse = false
	_capture_mouse()


func _close_context_menu_to_game() -> void:
	_ui_owns_mouse = false
	_capture_mouse()


func _on_context_menu_hidden() -> void:
	if (
		color_dialog.visible
		or (is_instance_valid(share_dialog) and share_dialog.visible)
		or (is_instance_valid(token_state_dialog) and token_state_dialog.visible)
		or (
			is_instance_valid(camera_settings_dialog)
			and camera_settings_dialog.visible
		)
	):
		return
	call_deferred("_finish_context_menu_close")


func _finish_context_menu_close() -> void:
	if (
		color_dialog.visible
		or (is_instance_valid(share_dialog) and share_dialog.visible)
		or (is_instance_valid(token_state_dialog) and token_state_dialog.visible)
		or (
			is_instance_valid(camera_settings_dialog)
			and camera_settings_dialog.visible
		)
	):
		return
	if (
		spell_system != null
		and is_instance_valid(spell_system)
		and bool(spell_system.call("is_panel_open"))
	):
		_pending_aoe_index = -1
		_context_token = null
		_ui_owns_mouse = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	_pending_aoe_index = -1
	_context_token = null
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
		float(selected_size.get("footprint", 1.0)),
		token_name_input.text if token_name_input != null else ""
	)

	_ui_owns_mouse = false
	_capture_mouse()


func _on_token_dialog_canceled() -> void:
	_ui_owns_mouse = false
	_capture_mouse()


func _spawn_token(
	token_color: Color,
	size_name: String,
	footprint_cells: float,
	display_name: String = ""
) -> void:
	if token_scene == null:
		push_error("DnDBase: token_scene non assegnata.")
		return

	push_undo_state()
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

	if token.has_method("set_display_name"):
		token.call("set_display_name", display_name)

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
		if not (target is CharacterBody3D):
			if not additive_selection:
				_clear_selection()
			return
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
	if not _selected_tokens.is_empty():
		push_undo_state()

	for token: CharacterBody3D in _selected_tokens:
		if token.has_method("nudge_grid"):
			token.call("nudge_grid", direction)


func _rotate_selected(quarter_turns: int) -> void:
	_clean_selection()
	if not _selected_tokens.is_empty():
		push_undo_state()

	for token: CharacterBody3D in _selected_tokens:
		if token.has_method("rotate_grid"):
			token.call("rotate_grid", quarter_turns)


func _delete_selected() -> void:
	_clean_selection()
	if not _selected_tokens.is_empty():
		push_undo_state()

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
