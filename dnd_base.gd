extends Node3D

const CONTEXT_CREATE_TOKEN := 1
const CONTEXT_DELETE_SELECTED := 2
const CONTEXT_ROTATE_LEFT := 3
const CONTEXT_ROTATE_RIGHT := 4
const CONTEXT_TOGGLE_GRID := 5
const CONTEXT_TOGGLE_VISION_CONES := 6
const CONTEXT_TOGGLE_REACH_SPHERES := 7
const CONTEXT_FLYING := 8
const CONTEXT_MAIN_MENU := 9
const CONTEXT_DISSOLVE_AOE := 10
const CONTEXT_SPELLS := 11
const CONTEXT_CAMERA_SETTINGS := 12
const CONTEXT_INITIATIVE := 13
const CONTEXT_TOKEN_DETAILS := 14
const CONTEXT_RESTORE_TRANSFORMATION := 15
const CONTEXT_PLAYER_AREA := 16
const CAMPAIGN_EDITOR_SCENE_PATH := "res://vtt/editor/campaign_editor.tscn"
const LOCAL_TOKEN_CATALOG := "res://dist/token_packs/token_catalog.json"
const LOCAL_TOKEN_PACK_ROOT := "res://dist/token_packs"
const CHARACTER_TOKEN_ROOT := "res://assets/tokens/Characters"
const DEFAULT_TOKEN_PROFILE_ID := "death_knight"
const GridHighlightRenderer = preload("res://vtt/grid_highlight_renderer.gd")
const TokenScript = preload("res://token.gd")
const FlankingGeometry = preload("res://vtt/flanking_system.gd")

const CAMERA_SPEED_DEFAULT := 5.0
const CAMERA_SENSITIVITY_DEFAULT := 0.002
const ALL_COLLISION_LAYERS := 0xFFFFFFFF
# Persistent AoEs use this layer only so the right-click context menu can
# identify them. Token picking must see through this layer.
const AOE_PICK_LAYER := 1 << 20
const TOKEN_PICK_COLLISION_MASK := ALL_COLLISION_LAYERS & ~AOE_PICK_LAYER
const UNDO_LIMIT := 50

const TOKEN_SIZES := [
	{"name": "Tiny", "footprint": 0.5},
	{"name": "Small", "footprint": 1.0},
	{"name": "Medium", "footprint": 1.0},
	{"name": "Large", "footprint": 2.0},
	{"name": "Huge", "footprint": 3.0},
	{"name": "Gargantuan", "footprint": 4.0},
]

@export var grid_visible_on_start: bool = true
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
@onready var measurement_tool: Node3D = $MeasurementTool
@onready var measurement_mode_label: Label = $UI/MeasurementModeLabel

var _pending_spawn_position: Vector3 = Vector3.ZERO
var _has_pending_spawn_position: bool = false
var _pending_spawn_support: Node3D = null
var _token_generation_confirmed_callback: Callable = Callable()
var _token_generation_canceled_callback: Callable = Callable()
var _token_generation_exact_position: bool = false
var _token_generation_place_on_surface: bool = false
var _token_generation_transform_target: CharacterBody3D
var token_resize_menu: PopupMenu
var context_token_menu: PopupMenu
var context_game_menu: PopupMenu
var context_measure_menu: PopupMenu
var context_view_menu: PopupMenu
var context_session_menu: PopupMenu
var _token_resize_target: CharacterBody3D
var _token_resize_confirmed_callback: Callable = Callable()
var _token_resize_canceled_callback: Callable = Callable()
var _pending_aoe_index: int = -1
var _context_token: CharacterBody3D = null
var _selected_tokens: Array[CharacterBody3D] = []
var _ui_owns_mouse: bool = false
var _vision_cones_visible: bool = false
var board_sync: Node
var share_dialog: AcceptDialog
var share_session: SpinBox
var share_status: Label
var map_save_dialog: FileDialog
var map_load_dialog: FileDialog
var camera_settings_dialog: AcceptDialog
var camera_speed_slider: HSlider
var camera_sensitivity_slider: HSlider
var camera_speed_value_label: Label
var camera_sensitivity_value_label: Label
var token_name_input: LineEdit
var _token_name_is_auto: bool = true
var _updating_token_name_input: bool = false
var token_reach_input: SpinBox
var token_miniature_search: LineEdit
var token_miniature_list: ItemList
var token_download_button: Button
var token_front_selector: OptionButton
var _token_profiles: Array[Dictionary] = []
var _visible_token_profiles: Array[Dictionary] = []
var _selected_token_profile: Dictionary = {}
var _token_front_by_id: Dictionary = {}
var _selection_grid_instance: MultiMeshInstance3D
var _selection_grid_multimesh: MultiMesh
var _selection_grid_signature: String = ""
var _affected_grid_instance: MultiMeshInstance3D
var _affected_grid_multimesh: MultiMesh
var _affected_grid_signature: String = ""
var _affected_tokens: Array[CharacterBody3D] = []
var token_state_dialog: ConfirmationDialog
var opportunity_dialog: PanelContainer
var opportunity_label: Label
var _opportunity_notice_generation: int = 0
var token_state_name: LineEdit
var token_party_input: LineEdit
var token_identity_label: Label
var token_state_grid: GridContainer
var token_state_checks: Dictionary = {}
var _editing_token: CharacterBody3D
var token_drag: Node
var spell_system: Node
var attack_system: Node
var flanking_system: Node
var initiative_tracker: Node
var token_list: Node
var player_area: Node
var master_area: Node
var dice_roller_chat: Node
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _pending_history_actions: Array[int] = []
var _history_action_scheduled: bool = false
var _undo_restoring: bool = false


func _ready() -> void:
	# Unica griglia tattica: la VolumetricGrid collision-aware.
	# grid_3d_visible_on_start resta come alias di compatibilita per scene
	# create prima della rimozione della SurfaceGrid.
	set_grid_visible(grid_visible_on_start or grid_3d_visible_on_start)
	set_vision_cones_visible(vision_cones_visible_on_start)

	context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	context_menu.popup_hide.connect(_on_context_menu_hidden)
	_build_context_submenus()

	color_dialog.confirmed.connect(_on_token_dialog_confirmed)
	color_dialog.canceled.connect(_on_token_dialog_canceled)
	color_dialog.close_requested.connect(_on_token_dialog_canceled)

	size_selector.clear()
	for token_size: Dictionary in TOKEN_SIZES:
		size_selector.add_item(String(token_size.get("name", "Medium")))
	size_selector.select(2)
	size_selector.disabled = true
	size_selector.tooltip_text = "Taglia determinata dalla miniatura selezionata."

	volumetric_grid.call("set_camera", camera)

	if not tokens_root.child_entered_tree.is_connected(
		_configure_token_volumetric_grid
	):
		tokens_root.child_entered_tree.connect(
			_configure_token_volumetric_grid
		)
	for token_child: Node in tokens_root.get_children():
		_configure_token_volumetric_grid(token_child)

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
	board_sync.listen(true, _share_session_key())
	_build_camera_settings_dialog()
	_build_token_generation_controls()
	_connect_token_pack_manager()
	_build_token_resize_menu()
	_build_token_state_dialog()
	_build_opportunity_attack_dialog()

	spell_system = preload("res://vtt/spells/spell_system.gd").new()
	spell_system.name = "SpellSystem"
	add_child(spell_system)
	spell_system.call("setup", self)

	attack_system = preload("res://vtt/attack_system.gd").new()
	attack_system.name = "AttackSystem"
	add_child(attack_system)
	attack_system.call("setup", self)

	flanking_system = preload("res://vtt/flanking_system.gd").new()
	flanking_system.name = "FlankingSystem"
	add_child(flanking_system)
	flanking_system.call("setup", self)

	initiative_tracker = preload("res://vtt/initiative_tracker.gd").new()
	initiative_tracker.name = "InitiativeTracker"
	add_child(initiative_tracker)
	initiative_tracker.call("setup", self)

	token_list = preload("res://vtt/token_list.gd").new()
	token_list.name = "TokenList"
	add_child(token_list)
	token_list.call("setup", self)

	player_area = preload("res://vtt/player_area.gd").new()
	player_area.name = "PlayerArea"
	add_child(player_area)
	player_area.call("setup", self)

	master_area = preload("res://vtt/master_area.gd").new()
	master_area.name = "MasterArea"
	add_child(master_area)
	master_area.call("setup", self)

	dice_roller_chat = preload("res://vtt/dice_roller_chat.gd").new()
	dice_roller_chat.name = "DiceRollerChat"
	add_child(dice_roller_chat)
	dice_roller_chat.call(
		"setup",
		self,
		_share_session_key(),
		Callable(board_sync, "_tailscale_peer_ipv4s")
	)

	var runtime_toolbar: Node = (
		preload("res://vtt/runtime_toolbar.gd").new() as Node
	)
	runtime_toolbar.name = "RuntimeToolbarController"
	add_child(runtime_toolbar)
	runtime_toolbar.call("setup", self)

	_build_selection_grid_highlight()
	_build_affected_grid_highlight()
	_capture_mouse()


func _configure_token_volumetric_grid(node: Node) -> void:
	if (
		node is CharacterBody3D
		and node.has_method("set_volumetric_grid")
	):
		node.call("set_volumetric_grid", volumetric_grid)


func _read_local_token_catalog() -> Dictionary:
	if not FileAccess.file_exists(LOCAL_TOKEN_CATALOG):
		return {}
	var file := FileAccess.open(LOCAL_TOKEN_CATALOG, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _local_pack_path(entry: Dictionary) -> String:
	var pck_name := String(entry.get("pck", "")).strip_edges()
	if pck_name.is_empty():
		var token_id := String(entry.get("id", "")).strip_edges()
		if token_id.is_empty():
			return ""
		pck_name = "%s.pck" % token_id
	if pck_name.begins_with("res://"):
		return pck_name
	return LOCAL_TOKEN_PACK_ROOT.path_join(pck_name.get_file())


func _token_profile_visual_asset(profile: Dictionary) -> String:
	var path := String(profile.get("visual_asset", "")).strip_edges()
	if not path.is_empty():
		return path
	return String(profile.get("obj", "")).strip_edges()



func _collect_character_obj_paths(
	directory_path: String,
	relative_prefix: String,
	out_paths: Array[String]
) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return

	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue

		var relative_path := (
			entry
			if relative_prefix.is_empty()
			else relative_prefix.path_join(entry)
		)
		var full_path := CHARACTER_TOKEN_ROOT.path_join(relative_path)
		if directory.current_is_dir():
			_collect_character_obj_paths(
				full_path,
				relative_path,
				out_paths
			)
		elif entry.get_extension().to_lower() == "obj":
			out_paths.append(relative_path)
	directory.list_dir_end()


func _character_token_group(relative_path: String) -> String:
	var normalized := relative_path.replace("\\", "/")
	var parts := normalized.split("/", false)
	if parts.size() >= 2:
		return String(parts[0]).strip_edges()
	return normalized.get_file().get_basename().strip_edges()


func _append_character_token_profiles() -> void:
	var relative_paths: Array[String] = []
	_collect_character_obj_paths(
		CHARACTER_TOKEN_ROOT,
		"",
		relative_paths
	)
	if relative_paths.is_empty():
		return

	relative_paths.sort()
	var known_assets: Dictionary = {}
	for profile: Dictionary in _token_profiles:
		known_assets[_token_profile_visual_asset(profile)] = true

	var group_counts: Dictionary = {}
	for relative_path: String in relative_paths:
		var group_name := _character_token_group(relative_path)
		group_counts[group_name] = int(group_counts.get(group_name, 0)) + 1

	for relative_path: String in relative_paths:
		var normalized_relative := relative_path.replace("\\", "/")
		var visual_path := CHARACTER_TOKEN_ROOT.path_join(normalized_relative)
		if known_assets.has(visual_path):
			continue

		var group_name := _character_token_group(normalized_relative)
		var display_name := group_name
		if int(group_counts.get(group_name, 0)) > 1:
			display_name = "%s · %s" % [
				group_name,
				normalized_relative.get_file().get_basename()
			]

		_token_profiles.append({
			"id": "character:" + normalized_relative.to_lower(),
			"name": display_name,
			"source": "Characters/" + normalized_relative,
			"visual_asset": visual_path,
			"size_name": "Medium",
			"footprint": 1.0,
			"_pack_origin": "character",
		})
		known_assets[visual_path] = true


func _sort_token_profiles(a: Dictionary, b: Dictionary) -> bool:
	return (
		String(a.get("name", "")).nocasecmp_to(
			String(b.get("name", ""))
		) < 0
	)


func _build_token_generation_controls() -> void:
	var content_box: VBoxContainer = (
		color_dialog.get_node_or_null("Content/VBox") as VBoxContainer
	)
	if content_box == null:
		return

	color_dialog.min_size = Vector2i(360, 360)
	color_dialog.get_ok_button().custom_minimum_size = Vector2(110, 36)
	color_dialog.get_ok_button().show()
	var cancel_button := color_dialog.get_cancel_button()
	if cancel_button != null:
		cancel_button.text = "Annulla"
		cancel_button.custom_minimum_size = Vector2(110, 36)
		cancel_button.show()

	_ensure_token_name_input()
	if token_name_input != null:
		token_name_input.editable = true
		token_name_input.placeholder_text = "Nome del token"
		token_name_input.tooltip_text = (
			"Il nome parte da quello della miniatura, ma puoi modificarlo "
			+ "prima di creare il token."
		)
		if not token_name_input.text_changed.is_connected(
			_on_token_name_input_changed
		):
			token_name_input.text_changed.connect(_on_token_name_input_changed)

	var name_label := content_box.get_node_or_null("TokenNameLabel") as Label
	if name_label != null:
		name_label.text = "Nome del token"

	var miniature_label := content_box.get_node_or_null("MiniatureLabel") as Label
	if miniature_label == null:
		miniature_label = Label.new()
		miniature_label.name = "MiniatureLabel"
		miniature_label.text = "Miniatura"
		content_box.add_child(miniature_label)

	token_miniature_search = (
		content_box.get_node_or_null("MiniatureSearch") as LineEdit
	)
	if token_miniature_search == null:
		token_miniature_search = LineEdit.new()
		token_miniature_search.name = "MiniatureSearch"
		token_miniature_search.placeholder_text = "Cerca miniatura..."
		token_miniature_search.clear_button_enabled = true
		token_miniature_search.text_changed.connect(
			_on_token_miniature_search_changed
		)
		content_box.add_child(token_miniature_search)

	token_miniature_list = (
		content_box.get_node_or_null("MiniatureList") as ItemList
	)
	if token_miniature_list == null:
		token_miniature_list = ItemList.new()
		token_miniature_list.name = "MiniatureList"
		token_miniature_list.custom_minimum_size = Vector2(500, 270)
		token_miniature_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		token_miniature_list.allow_reselect = true
		token_miniature_list.item_selected.connect(
			_on_token_miniature_selected
		)
		content_box.add_child(token_miniature_list)

	token_download_button = (
		content_box.get_node_or_null("TokenDownloadButton") as Button
	)
	if token_download_button == null:
		token_download_button = Button.new()
		token_download_button.name = "TokenDownloadButton"
		token_download_button.text = "Scarica"
		token_download_button.visible = false
		token_download_button.pressed.connect(
			_on_token_download_button_pressed
		)
		content_box.add_child(token_download_button)

	var size_label := content_box.get_node_or_null("SizeLabel") as Label
	if size_label != null:
		size_label.text = "Taglia D&D"

	size_selector.disabled = false
	size_selector.tooltip_text = (
		"La miniatura propone una taglia iniziale, ma puoi cambiarla. "
		+ "La scelta modifica footprint, collisione e scala del token."
	)
	if not size_selector.item_selected.is_connected(_on_token_size_selected):
		size_selector.item_selected.connect(_on_token_size_selected)

	var reach_label := content_box.get_node_or_null("ReachLabel") as Label
	if reach_label == null:
		reach_label = Label.new()
		reach_label.name = "ReachLabel"
		reach_label.text = "Gittata della creatura (ft)"
		reach_label.tooltip_text = (
			"Default: 5 ft per Medium o inferiore, 10 ft Large, "
			+ "15 ft Huge, 20 ft Gargantuan. Puoi sovrascriverla."
		)
		content_box.add_child(reach_label)

	token_reach_input = content_box.get_node_or_null("ReachInput") as SpinBox
	if token_reach_input == null:
		token_reach_input = SpinBox.new()
		token_reach_input.name = "ReachInput"
		token_reach_input.min_value = 5.0
		token_reach_input.max_value = 1000.0
		token_reach_input.step = 5.0
		token_reach_input.value = 5.0
		token_reach_input.allow_greater = true
		token_reach_input.tooltip_text = reach_label.tooltip_text
		content_box.add_child(token_reach_input)

	var front_label := content_box.get_node_or_null("FrontLabel") as Label
	if front_label == null:
		front_label = Label.new()
		front_label.name = "FrontLabel"
		front_label.text = "Faccia frontale della miniatura"
		front_label.tooltip_text = (
			"Scegli quale asse del modello rappresenta il fronte. "
			+ "Verrà allineato alla freccia frontale del token."
		)
		content_box.add_child(front_label)

	token_front_selector = (
		content_box.get_node_or_null("FrontSelector") as OptionButton
	)
	if token_front_selector == null:
		token_front_selector = OptionButton.new()
		token_front_selector.name = "FrontSelector"
		token_front_selector.add_item("-Z del modello")
		token_front_selector.add_item("+X del modello")
		token_front_selector.add_item("+Z del modello")
		token_front_selector.add_item("-X del modello")
		token_front_selector.tooltip_text = front_label.tooltip_text
		token_front_selector.item_selected.connect(
			_on_token_front_selected
		)
		content_box.add_child(token_front_selector)

	content_box.move_child(miniature_label, 0)
	content_box.move_child(token_miniature_search, 1)
	content_box.move_child(token_miniature_list, 2)
	content_box.move_child(token_download_button, 3)
	if name_label != null:
		content_box.move_child(name_label, 4)
	if token_name_input != null:
		content_box.move_child(token_name_input, 5)
	if size_label != null:
		content_box.move_child(size_label, 6)
	content_box.move_child(size_selector, 7)
	content_box.move_child(reach_label, 8)
	content_box.move_child(token_reach_input, 9)
	content_box.move_child(front_label, 10)
	content_box.move_child(token_front_selector, 11)

	_reload_token_miniature_list()


func _connect_token_pack_manager() -> void:
	if TokenPackManager == null:
		return
	if not TokenPackManager.catalog_updated.is_connected(
		_on_remote_token_catalog_updated
	):
		TokenPackManager.catalog_updated.connect(
			_on_remote_token_catalog_updated
		)
	if not TokenPackManager.token_downloaded.is_connected(
		_on_remote_token_downloaded
	):
		TokenPackManager.token_downloaded.connect(
			_on_remote_token_downloaded
		)
	if not TokenPackManager.token_mounted.is_connected(
		_on_remote_token_mounted
	):
		TokenPackManager.token_mounted.connect(
			_on_remote_token_mounted
		)
	if not TokenPackManager.token_download_failed.is_connected(
		_on_remote_token_download_failed
	):
		TokenPackManager.token_download_failed.connect(
			_on_remote_token_download_failed
		)
	if not TokenPackManager.token_mount_failed.is_connected(
		_on_remote_token_mount_failed
	):
		TokenPackManager.token_mount_failed.connect(
			_on_remote_token_mount_failed
		)


func _on_remote_token_catalog_updated(_entries: Array[Dictionary]) -> void:
	if token_miniature_list != null:
		_reload_token_miniature_list()


func _remote_visual_path(token_id: String) -> String:
	return "res://remote_tokens/%s/%s_visual.res" % [token_id, token_id]


func _on_remote_token_downloaded(
	token_id: String,
	_cache_path: String
) -> void:
	if String(_selected_token_profile.get("id", "")) == token_id:
		var ok_button := color_dialog.get_ok_button()
		if ok_button != null:
			ok_button.disabled = false
	call_deferred("_reload_token_miniature_list", token_id)


func _on_remote_token_mounted(
	token_id: String,
	_scene_path: String
) -> void:
	if (
		String(_selected_token_profile.get("_pack_origin", "")) == "remote"
		and String(_selected_token_profile.get("id", "")) == token_id
	):
		_selected_token_profile["visual_asset"] = _remote_visual_path(token_id)
		var ok_button := color_dialog.get_ok_button()
		if ok_button != null:
			ok_button.disabled = false
	call_deferred("_reload_token_miniature_list", token_id)


func _on_remote_token_download_failed(
	token_id: String,
	message: String
) -> void:
	if String(_selected_token_profile.get("id", "")) == token_id:
		var ok_button := color_dialog.get_ok_button()
		if ok_button != null:
			ok_button.disabled = true
		if token_download_button != null:
			token_download_button.visible = true
			token_download_button.disabled = false
			token_download_button.text = "Scarica"
	push_warning("DnDBase: download token remoto fallito: %s" % message)


func _on_remote_token_mount_failed(
	token_id: String,
	message: String
) -> void:
	if String(_selected_token_profile.get("id", "")) == token_id:
		var ok_button := color_dialog.get_ok_button()
		if ok_button != null:
			ok_button.disabled = true
	push_warning("DnDBase: mount token remoto fallito: %s" % message)


func _prepare_remote_token(profile: Dictionary) -> void:
	if String(profile.get("_pack_origin", "")) != "remote":
		return
	var token_id := String(profile.get("id", "")).strip_edges()
	if token_id.is_empty():
		return

	var downloaded := TokenPackManager.is_downloaded(token_id)
	var mounted := TokenPackManager.is_mounted(token_id)
	var ok_button := color_dialog.get_ok_button()
	if ok_button != null:
		ok_button.disabled = not (downloaded or mounted)

	if token_download_button != null:
		token_download_button.visible = not downloaded and not mounted
		token_download_button.disabled = false
		var size_text := _format_token_download_size(profile)
		token_download_button.text = (
			"Scarica (%s)" % size_text
			if not size_text.is_empty()
			else "Scarica"
		)


func _on_token_download_button_pressed() -> void:
	if String(_selected_token_profile.get("_pack_origin", "")) != "remote":
		return
	var token_id := String(_selected_token_profile.get("id", "")).strip_edges()
	if token_id.is_empty():
		return
	if TokenPackManager.is_downloaded(token_id):
		_reload_token_miniature_list(token_id)
		return

	if token_download_button != null:
		token_download_button.disabled = true
		token_download_button.text = "Download..."

	var error := TokenPackManager.download_token(token_id)
	if error != OK:
		if token_download_button != null:
			token_download_button.disabled = false
			token_download_button.text = "Scarica"
		_on_remote_token_download_failed(
			token_id,
			"Download non avviato: %s" % error_string(error)
		)


func _remote_token_status(token_id: String) -> String:
	if TokenPackManager.is_mounted(token_id):
		return "Montato"
	if TokenPackManager.is_downloaded(token_id):
		return "Scaricato"
	return "Remoto"


func _append_remote_token_profiles() -> void:
	var known_ids: Dictionary = {}
	for profile: Dictionary in _token_profiles:
		var local_id := String(profile.get("id", "")).strip_edges()
		if not local_id.is_empty():
			known_ids[local_id] = true

	for entry: Dictionary in TokenPackManager.get_entries():
		var token_id := String(entry.get("id", "")).strip_edges()
		if token_id.is_empty():
			continue

		if known_ids.has(token_id):
			continue

		var remote_profile := entry.duplicate(true)
		remote_profile["_pack_origin"] = "remote"
		remote_profile["visual_asset"] = _remote_visual_path(token_id)
		remote_profile["_pack_status"] = _remote_token_status(token_id)
		remote_profile["_remote_scene"] = String(
			entry.get(
				"scene",
				"res://remote_tokens/%s/%s_token.tscn"
				% [token_id, token_id]
			)
		)
		_token_profiles.append(remote_profile)
		known_ids[token_id] = true


func _token_profile_status(profile: Dictionary) -> String:
	var origin := String(profile.get("_pack_origin", ""))
	if origin == "current":
		return "Attuale"
	if origin == "local_pack":
		var local_token_id := String(profile.get("id", ""))
		return "Montato" if TokenPackManager.is_mounted(local_token_id) else "Locale"
	if origin == "character":
		return "Locale"
	var token_id := String(profile.get("id", ""))
	return _remote_token_status(token_id)


func _format_token_download_size(profile: Dictionary) -> String:
	var bytes := int(profile.get("bytes", 0))
	if bytes <= 0:
		return ""
	if bytes >= 1024 * 1024:
		return "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))
	if bytes >= 1024:
		return "%.0f KB" % (float(bytes) / 1024.0)
	return "%d B" % bytes


func _reload_token_miniature_list(preferred_id: String = "") -> void:
	var previous_id := preferred_id.strip_edges()
	if previous_id.is_empty():
		previous_id = String(_selected_token_profile.get("id", ""))
	var previous_query := (
		token_miniature_search.text
		if token_miniature_search != null
		else ""
	)

	_token_profiles.clear()
	_visible_token_profiles.clear()
	_selected_token_profile.clear()
	if token_miniature_list == null:
		return

	var local_catalog := _read_local_token_catalog()
	var local_tokens_value: Variant = local_catalog.get("tokens", [])
	if local_tokens_value is Array:
		for value: Variant in local_tokens_value:
			if not value is Dictionary:
				continue
			var profile := (value as Dictionary).duplicate(true)
			var token_id := String(profile.get("id", "")).strip_edges()
			if token_id.is_empty():
				continue
			var local_pck := _local_pack_path(profile)
			if local_pck.is_empty() or not FileAccess.file_exists(local_pck):
				continue
			profile["_pack_origin"] = "local_pack"
			profile["_local_pck_path"] = local_pck
			profile["visual_asset"] = _remote_visual_path(token_id)
			_token_profiles.append(profile)

	_append_character_token_profiles()
	_append_remote_token_profiles()

	_token_profiles.sort_custom(
		Callable(self, "_sort_token_profiles")
	)

	if previous_id.is_empty():
		previous_id = DEFAULT_TOKEN_PROFILE_ID
	if token_miniature_search != null and token_miniature_search.text != previous_query:
		token_miniature_search.text = previous_query
	_refresh_token_miniature_filter(previous_query, previous_id)


func _on_token_miniature_search_changed(query: String) -> void:
	_refresh_token_miniature_filter(query)


func _refresh_token_miniature_filter(
	query: String,
	preferred_id: String = ""
) -> void:
	if token_miniature_list == null:
		return

	var current_id := preferred_id.strip_edges()
	if current_id.is_empty():
		current_id = String(_selected_token_profile.get("id", ""))

	var normalized_query := query.strip_edges().to_lower()
	_visible_token_profiles.clear()
	token_miniature_list.clear()

	var target_index := -1
	for profile: Dictionary in _token_profiles:
		var token_name := String(
			profile.get("name", profile.get("id", "Token"))
		)
		var searchable := (
			token_name
			+ " "
			+ String(profile.get("id", ""))
			+ " "
			+ String(profile.get("source", ""))
			+ " "
			+ String(profile.get("pck", ""))
			+ " "
			+ _token_profile_status(profile)
		).to_lower()
		if not normalized_query.is_empty() and not searchable.contains(
			normalized_query
		):
			continue

		var visible_index := _visible_token_profiles.size()
		_visible_token_profiles.append(profile)
		var size_name := String(profile.get("size_name", "Medium"))
		var status := _token_profile_status(profile)
		token_miniature_list.add_item(
			"%s  ·  %s  ·  %s" % [token_name, size_name, status]
		)

		var tooltip_parts: Array[String] = []
		var source_text := String(
			profile.get(
				"source",
				_token_profile_visual_asset(profile)
			)
		).strip_edges()
		if not source_text.is_empty():
			tooltip_parts.append(source_text)
		tooltip_parts.append("Stato: %s" % status)
		var download_size := _format_token_download_size(profile)
		if not download_size.is_empty():
			tooltip_parts.append("Download: %s" % download_size)
		token_miniature_list.set_item_tooltip(
			visible_index,
			"\n".join(tooltip_parts)
		)
		if String(profile.get("id", "")) == current_id:
			target_index = visible_index

	var ok_button := color_dialog.get_ok_button()
	if _visible_token_profiles.is_empty():
		_selected_token_profile.clear()
		if ok_button != null:
			ok_button.disabled = true
		return

	if target_index < 0:
		target_index = 0

	var target_profile: Dictionary = _visible_token_profiles[target_index]
	var target_id := String(target_profile.get("id", ""))
	token_miniature_list.select(target_index)
	if (
		_selected_token_profile.is_empty()
		or String(_selected_token_profile.get("id", "")) != target_id
	):
		_on_token_miniature_selected(target_index)
	else:
		# Filtering can keep the same first result selected, so item_selected
		# is not emitted again. Re-apply its availability state instead of
		# leaving the Create button enabled by the list refresh.
		var target_origin := String(target_profile.get("_pack_origin", ""))
		if target_origin == "remote":
			_prepare_remote_token(target_profile)
		else:
			if token_download_button != null:
				token_download_button.visible = false
			if ok_button != null:
				ok_button.disabled = false


static func unique_token_display_name(
	base_name: String,
	existing_names: Array[String]
) -> String:
	var resolved_base := base_name.strip_edges()
	if resolved_base.is_empty():
		resolved_base = "Token"

	var used_names: Dictionary = {}
	for existing_name: String in existing_names:
		var normalized := existing_name.strip_edges().to_lower()
		if not normalized.is_empty():
			used_names[normalized] = true

	if not used_names.has(resolved_base.to_lower()):
		return resolved_base

	var suffix := 1
	while used_names.has(("%s %d" % [resolved_base, suffix]).to_lower()):
		suffix += 1
	return "%s %d" % [resolved_base, suffix]


func _current_token_display_names(
	excluded_token: CharacterBody3D = null
) -> Array[String]:
	var names: Array[String] = []
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if not node is CharacterBody3D:
			continue
		var token := node as CharacterBody3D
		if (
			token == excluded_token
			or not is_instance_valid(token)
			or not is_ancestor_of(token)
		):
			continue
		var display_name := (
			String(token.call("get_display_name")).strip_edges()
			if token.has_method("get_display_name")
			else String(token.name).strip_edges()
		)
		if not display_name.is_empty():
			names.append(display_name)
	return names


func _unique_token_display_name(
	base_name: String,
	excluded_token: CharacterBody3D = null
) -> String:
	return unique_token_display_name(
		base_name,
		_current_token_display_names(excluded_token)
	)


func _token_profile_default_name(profile: Dictionary) -> String:
	var profile_name := String(
		profile.get("name", profile.get("id", "Token"))
	).strip_edges()
	return profile_name if not profile_name.is_empty() else "Token"


func _set_token_name_input(value: String, automatic: bool) -> void:
	if token_name_input == null:
		return
	_updating_token_name_input = true
	token_name_input.text = value
	_updating_token_name_input = false
	_token_name_is_auto = automatic


func _on_token_name_input_changed(_value: String) -> void:
	if _updating_token_name_input:
		return
	_token_name_is_auto = false


func _on_token_miniature_selected(index: int) -> void:
	if index < 0 or index >= _visible_token_profiles.size():
		return
	_selected_token_profile = _visible_token_profiles[index].duplicate(true)

	if token_name_input != null and _token_name_is_auto:
		var token_name := _token_profile_default_name(_selected_token_profile)
		_set_token_name_input(
			_unique_token_display_name(token_name),
			true
		)

	var size_name := String(
		_selected_token_profile.get("size_name", "Medium")
	)
	for size_index: int in range(TOKEN_SIZES.size()):
		if String(TOKEN_SIZES[size_index].get("name", "")) == size_name:
			size_selector.select(size_index)
			break
	size_selector.disabled = false
	_on_token_size_selected(size_selector.selected)

	var token_id := String(_selected_token_profile.get("id", ""))
	var front_index := clampi(
		int(_token_front_by_id.get(token_id, 0)),
		0,
		3
	)
	if token_front_selector != null:
		token_front_selector.select(front_index)

	var origin := String(_selected_token_profile.get("_pack_origin", ""))
	if token_download_button != null:
		token_download_button.visible = false
	if origin == "remote":
		_prepare_remote_token(_selected_token_profile)
	else:
		var ok_button := color_dialog.get_ok_button()
		if ok_button != null:
			ok_button.disabled = false


func _on_token_size_selected(index: int) -> void:
	if token_reach_input == null:
		return
	if index < 0 or index >= TOKEN_SIZES.size():
		index = 2
	var size_data: Dictionary = TOKEN_SIZES[index]
	var footprint: float = float(size_data.get("footprint", 1.0))
	token_reach_input.value = maxf(5.0, footprint * 5.0)


func _on_token_front_selected(index: int) -> void:
	if _selected_token_profile.is_empty():
		return
	var token_id := String(_selected_token_profile.get("id", ""))
	if not token_id.is_empty():
		_token_front_by_id[token_id] = clampi(index, 0, 3)


func _build_token_resize_menu() -> void:
	token_resize_menu = PopupMenu.new()
	token_resize_menu.name = "TokenResizeMenu"
	# Non lasciare che PopupMenu si chiuda prima di id_pressed: popup_hide
	# rappresenta l'annullamento e azzererebbe il target prima del resize.
	token_resize_menu.hide_on_item_selection = false
	for index: int in range(TOKEN_SIZES.size()):
		var size_data: Dictionary = TOKEN_SIZES[index]
		token_resize_menu.add_item(
			String(size_data.get("name", "Medium")),
			index
		)
		token_resize_menu.set_item_metadata(index, index)
	token_resize_menu.id_pressed.connect(_on_token_resize_selected)
	token_resize_menu.popup_hide.connect(_on_token_resize_menu_hidden)
	$UI.add_child(token_resize_menu)


func open_token_resize_menu(
	target: CharacterBody3D,
	confirmed_callback: Callable = Callable(),
	canceled_callback: Callable = Callable()
) -> void:
	if target == null or not is_instance_valid(target):
		if canceled_callback.is_valid():
			canceled_callback.call()
		return

	_token_resize_target = target
	_token_resize_confirmed_callback = confirmed_callback
	_token_resize_canceled_callback = canceled_callback
	_ui_owns_mouse = true
	_release_mouse()

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	token_resize_menu.position = Vector2i(
		int(viewport_size.x * 0.5 - 70.0),
		int(viewport_size.y * 0.5 - 90.0)
	)
	token_resize_menu.popup()


func _on_token_resize_selected(id: int) -> void:
	if (
		_token_resize_target == null
		or not is_instance_valid(_token_resize_target)
		or id < 0
		or id >= TOKEN_SIZES.size()
	):
		return

	var target: CharacterBody3D = _token_resize_target
	var size_data: Dictionary = TOKEN_SIZES[id]
	var confirmed_callback: Callable = _token_resize_confirmed_callback

	push_undo_state()
	if target.has_method("push_transformation_state"):
		target.call("push_transformation_state")
	if target.has_method("set_size_category"):
		target.call(
			"set_size_category",
			String(size_data.get("name", "Medium")),
			float(size_data.get("footprint", 1.0)),
			false
		)

	_token_resize_target = null
	_token_resize_confirmed_callback = Callable()
	_token_resize_canceled_callback = Callable()
	_refresh_token_views_after_appearance_change()

	# Ora che il resize e' stato applicato possiamo chiudere il popup.
	# _on_token_resize_menu_hidden vede target=null e non interpreta questa
	# chiusura come un annullamento.
	if token_resize_menu != null and token_resize_menu.visible:
		token_resize_menu.hide()

	_ui_owns_mouse = false
	_capture_mouse()

	if confirmed_callback.is_valid():
		confirmed_callback.call(target)


func _on_token_resize_menu_hidden() -> void:
	if _token_resize_target == null:
		return
	var canceled_callback: Callable = _token_resize_canceled_callback
	_token_resize_target = null
	_token_resize_confirmed_callback = Callable()
	_token_resize_canceled_callback = Callable()
	_ui_owns_mouse = false
	_capture_mouse()
	if canceled_callback.is_valid():
		canceled_callback.call()


func _refresh_token_views_after_appearance_change() -> void:
	_refresh_selection_grid_highlight()
	if token_list != null and is_instance_valid(token_list):
		if token_list.has_method("refresh"):
			token_list.call("refresh")
	if initiative_tracker != null and is_instance_valid(initiative_tracker):
		if initiative_tracker.has_method("refresh"):
			initiative_tracker.call("refresh")


func _build_grid_highlight(
	node_name: String,
	albedo: Color,
	emission: Color,
	emission_energy: float
) -> MultiMeshInstance3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = albedo
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = emission_energy
	material.no_depth_test = true

	var wire_cube := ImmediateMesh.new()
	wire_cube.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var half := cell_size * 0.49
	var corners: Array[Vector3] = [
		Vector3(-half, -half, -half),
		Vector3(half, -half, -half),
		Vector3(half, half, -half),
		Vector3(-half, half, -half),
		Vector3(-half, -half, half),
		Vector3(half, -half, half),
		Vector3(half, half, half),
		Vector3(-half, half, half),
	]
	var edges: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
		Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
	]
	for edge: Vector2i in edges:
		wire_cube.surface_add_vertex(corners[edge.x])
		wire_cube.surface_add_vertex(corners[edge.y])
	wire_cube.surface_end()

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = wire_cube
	multimesh.instance_count = 0

	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _build_selection_grid_highlight() -> void:
	_selection_grid_instance = _build_grid_highlight(
		"SelectedTokenGridHighlight",
		Color(1.0, 0.78, 0.08, 0.95),
		Color(1.0, 0.58, 0.02, 1.0),
		1.5
	)
	_selection_grid_multimesh = _selection_grid_instance.multimesh


func _build_affected_grid_highlight() -> void:
	_affected_grid_instance = _build_grid_highlight(
		"AffectedTokenGridHighlight",
		Color(1.0, 0.12, 0.08, 0.98),
		Color(1.0, 0.03, 0.01, 1.0),
		1.7
	)
	_affected_grid_multimesh = _affected_grid_instance.multimesh


func set_affected_token_highlight(tokens: Array) -> void:
	var resolved: Array[CharacterBody3D] = []
	for value: Variant in tokens:
		if not value is CharacterBody3D:
			continue
		var token: CharacterBody3D = value as CharacterBody3D
		if (
			token != null
			and is_instance_valid(token)
			and token.is_in_group("dnd_token")
			and not (token in resolved)
		):
			resolved.append(token)

	var same: bool = resolved.size() == _affected_tokens.size()
	if same:
		for index: int in range(resolved.size()):
			if resolved[index] != _affected_tokens[index]:
				same = false
				break
	if same:
		return

	_affected_tokens = resolved
	_affected_grid_signature = ""
	_refresh_affected_grid_highlight()


func _refresh_grid_highlight(
	tokens: Array[CharacterBody3D],
	multimesh: MultiMesh,
	previous_signature: String
) -> String:
	return GridHighlightRenderer.refresh(
		self,
		tokens,
		multimesh,
		previous_signature,
		cell_size
	)


func _refresh_affected_grid_highlight() -> void:
	_affected_grid_signature = _refresh_grid_highlight(
		_affected_tokens,
		_affected_grid_multimesh,
		_affected_grid_signature
	)


func _refresh_selection_grid_highlight() -> void:
	_selection_grid_signature = _refresh_grid_highlight(
		_selected_tokens,
		_selection_grid_multimesh,
		_selection_grid_signature
	)


func _process(_delta: float) -> void:
	_clean_selection()
	_refresh_selection_grid_highlight()
	_refresh_affected_grid_highlight()
	_process_pending_history_action()

	if _ui_owns_mouse and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
		and spell_system != null
		and is_instance_valid(spell_system)
		and spell_system.has_method("has_post_cast_cleanup")
		and bool(spell_system.call("has_post_cast_cleanup"))
	):
		spell_system.call("dismiss_post_cast_visuals")

	# Undo/redo sono shortcut globali e devono essere gestite prima dei
	# pannelli UI. In precedenza il pannello Incantesimi poteva lasciare
	# passare un movimento via _unhandled_input() ma bloccare Ctrl+Z qui.
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
		and bool(spell_system.call("is_panel_open"))
	):
		return

	# Player-sheet attacks use the same targeting priority as spells: the
	# click must be consumed before normal token selection/drag handles it.
	if (
		attack_system != null
		and is_instance_valid(attack_system)
		and bool(attack_system.call("is_targeting"))
		and (
			event is InputEventKey
			or event is InputEventMouseButton
		)
	):
		if bool(attack_system.call("handle_input", event)):
			get_viewport().set_input_as_handled()
			return

	# Spell targeting must see mouse/key input before GUI, camera, token drag,
	# or other gameplay handlers can consume it. Previously normal target
	# clicks were deferred to _unhandled_input(), which could leave a cast
	# stuck immediately after selecting its caster.
	if (
		spell_system != null
		and is_instance_valid(spell_system)
		and bool(spell_system.call("is_targeting"))
		and (
			event is InputEventKey
			or (
				event is InputEventMouseButton
				and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			)
		)
	):
		if bool(spell_system.call("handle_input", event)):
			get_viewport().set_input_as_handled()
			return

	if (
		spell_system != null
		and is_instance_valid(spell_system)
		and bool(spell_system.call("is_targeting"))
		and event is InputEventKey
		and event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
	):
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
		if (
			aoe_index >= 0
			and bool(measurement_tool.call("is_movable_aoe", aoe_index))
		):
			if bool(
				measurement_tool.call(
					"begin_movable_aoe_drag",
					aoe_index
				)
			):
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
					_move_selected_vertical(
						1 if event.keycode == KEY_UP else -1
					)
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
				_interact_or_select_under_mouse(
					event.position,
					event.shift_pressed,
					event.ctrl_pressed
				)
				get_viewport().set_input_as_handled()
			elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				_show_context_menu(event.position)
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


func _history_motion_in_progress() -> bool:
	if (
		token_drag != null
		and is_instance_valid(token_drag)
		and bool(token_drag.get("active"))
	):
		return true

	if (
		measurement_tool != null
		and is_instance_valid(measurement_tool)
		and measurement_tool.has_method("is_movable_aoe_dragging")
		and bool(measurement_tool.call("is_movable_aoe_dragging"))
	):
		return true

	for child: Node in tokens_root.get_children():
		if (
			child != null
			and is_instance_valid(child)
			and child.has_method("is_motion_in_progress")
			and bool(child.call("is_motion_in_progress"))
		):
			return true
	return false


func _queue_history_action(action: int) -> void:
	if action != -1 and action != 1:
		return
	_pending_history_actions.append(action)
	if _pending_history_actions.size() > UNDO_LIMIT:
		_pending_history_actions.pop_front()


func _process_pending_history_action() -> void:
	if (
		_history_action_scheduled
		or _undo_restoring
		or _pending_history_actions.is_empty()
		or _history_motion_in_progress()
	):
		return

	var action: int = _pending_history_actions.pop_front()
	_history_action_scheduled = true
	call_deferred("_execute_pending_history_action", action)


func _execute_pending_history_action(action: int) -> void:
	_history_action_scheduled = false
	if _history_motion_in_progress():
		_pending_history_actions.push_front(action)
		return
	if action == -1:
		_undo_last_action_now()
	elif action == 1:
		_redo_last_action_now()


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


func begin_undo_transaction() -> Dictionary:
	if _undo_restoring:
		return {}
	return _capture_history_state()


func begin_token_move_transaction(tokens: Array) -> Dictionary:
	if _undo_restoring:
		return {}
	return _capture_token_move_state(tokens)


func _capture_token_move_state(tokens: Array) -> Dictionary:
	var token_states: Array[Dictionary] = []
	for value: Variant in tokens:
		if not value is CharacterBody3D:
			continue
		var token: CharacterBody3D = value as CharacterBody3D
		if token == null or not is_instance_valid(token):
			continue

		var support_id := ""
		var support_value: Variant = token.get("grid_support")
		if support_value is Node3D and is_instance_valid(support_value):
			support_id = _history_node_id(support_value as Node3D)

		token_states.append({
			"id": _history_node_id(token),
			"transform": token.global_transform,
			"flying": bool(token.get("flying")),
			"support_id": support_id
		})

	if token_states.is_empty():
		return {}
	return {
		"kind": "token_move",
		"tokens": token_states
	}


func _history_node_id(node: Node3D) -> String:
	if node.has_meta("sync_id"):
		return String(node.get_meta("sync_id"))
	if board_sync != null and is_instance_valid(board_sync):
		var value: Variant = board_sync.call("_sync_id", node)
		if value is String and not String(value).is_empty():
			return String(value)
	var fallback := "path:" + String(get_path_to(node))
	node.set_meta("sync_id", fallback)
	return fallback


func _find_history_node(node_id: String) -> Node3D:
	if node_id.is_empty():
		return null
	for group_name: String in [
		"dnd_token",
		"tactical_platform",
		"encounter_obstacle"
	]:
		for node: Node in get_tree().get_nodes_in_group(group_name):
			if not node is Node3D:
				continue
			var node_3d: Node3D = node as Node3D
			if not is_ancestor_of(node_3d):
				continue
			if _history_node_id(node_3d) == node_id:
				return node_3d
	return null


func _capture_matching_history_state(target_state: Dictionary) -> Dictionary:
	if String(target_state.get("kind", "")) != "token_move":
		return _capture_history_state()

	var tokens: Array = []
	var target_tokens_value: Variant = target_state.get("tokens", [])
	if not target_tokens_value is Array:
		return {}
	var target_tokens: Array = target_tokens_value
	for item_value: Variant in target_tokens:
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value as Dictionary
		var token: Node3D = _find_history_node(String(item.get("id", "")))
		if token is CharacterBody3D:
			tokens.append(token)
	return _capture_token_move_state(tokens)


func _apply_token_move_history_state(state: Dictionary) -> bool:
	var values: Variant = state.get("tokens", [])
	if not values is Array:
		return false

	var token_states: Array = values as Array
	if token_states.is_empty():
		return false

	var resolved: Array[Dictionary] = []
	for item_value: Variant in token_states:
		if not item_value is Dictionary:
			return false
		var item: Dictionary = item_value as Dictionary
		var node: Node3D = _find_history_node(String(item.get("id", "")))
		if not node is CharacterBody3D:
			return false
		var transform_value: Variant = item.get("transform")
		if not transform_value is Transform3D:
			return false
		resolved.append({
			"token": node,
			"state": item
		})

	_undo_restoring = true
	for pair: Dictionary in resolved:
		var token: CharacterBody3D = pair.get("token") as CharacterBody3D
		var item: Dictionary = pair.get("state", {}) as Dictionary
		token.set_physics_process(false)
		if token.has_method("set_flying"):
			token.call("set_flying", bool(item.get("flying", true)))
		var saved_transform: Transform3D = item.get("transform")
		token.global_transform = saved_transform
		token.velocity = Vector3.ZERO

	for pair: Dictionary in resolved:
		var token: CharacterBody3D = pair.get("token") as CharacterBody3D
		var item: Dictionary = pair.get("state", {}) as Dictionary
		var support: Node3D = _find_history_node(
			String(item.get("support_id", ""))
		)
		token.set("grid_support", support)
		if support != null:
			token.set("_support_transform", support.global_transform)
		token.set_physics_process(true)

	_undo_restoring = false
	return true


func commit_undo_transaction(state: Dictionary) -> void:
	if _undo_restoring or state.is_empty():
		return
	_append_history_state(_undo_stack, state)
	# Una nuova azione crea una nuova linea temporale: il redo precedente
	# non e' piu' applicabile.
	_redo_stack.clear()


func push_undo_state() -> void:
	commit_undo_transaction(begin_undo_transaction())


func _apply_history_state(state: Dictionary) -> bool:
	if String(state.get("kind", "")) == "token_move":
		return _apply_token_move_history_state(state)

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
	if _history_motion_in_progress():
		_queue_history_action(-1)
		return true
	return _undo_last_action_now()


func _undo_last_action_now() -> bool:
	if _undo_stack.is_empty():
		return false
	if board_sync == null or not is_instance_valid(board_sync):
		return false

	var target_state: Dictionary = _undo_stack.pop_back()
	var current_state: Dictionary = _capture_matching_history_state(target_state)
	if current_state.is_empty():
		_append_history_state(_undo_stack, target_state)
		return false

	if not _apply_history_state(target_state):
		_append_history_state(_undo_stack, target_state)
		return false

	_append_history_state(_redo_stack, current_state)
	return true


func redo_last_action() -> bool:
	if _history_motion_in_progress():
		_queue_history_action(1)
		return true
	return _redo_last_action_now()


func _redo_last_action_now() -> bool:
	if _redo_stack.is_empty():
		return false
	if board_sync == null or not is_instance_valid(board_sync):
		return false

	var target_state: Dictionary = _redo_stack.pop_back()
	var current_state: Dictionary = _capture_matching_history_state(target_state)
	if current_state.is_empty():
		_append_history_state(_redo_stack, target_state)
		return false

	if not _apply_history_state(target_state):
		_append_history_state(_redo_stack, target_state)
		return false

	_append_history_state(_undo_stack, current_state)
	return true

func toggle_player_area() -> void:
	if player_area != null and is_instance_valid(player_area):
		player_area.call("toggle_panel")


func add_player_character() -> void:
	if player_area != null and is_instance_valid(player_area):
		player_area.call("add_character")


func link_player_character_to_selected_token() -> void:
	if player_area != null and is_instance_valid(player_area):
		player_area.call("request_link_character_to_selected_token")


func link_selected_player_character_to_named_token() -> void:
	if player_area != null and is_instance_valid(player_area):
		player_area.call("request_link_selected_character_to_named_token")


func get_selected_tokens_for_player_area() -> Array[CharacterBody3D]:
	_clean_selection()
	return _selected_tokens.duplicate()


func toggle_master_area() -> void:
	if master_area != null and is_instance_valid(master_area):
		master_area.call("toggle_panel")


func link_master_creature_to_selected_token() -> void:
	if master_area != null and is_instance_valid(master_area):
		master_area.call("request_link_creature_to_selected_token")


func link_selected_master_creature_to_named_token() -> void:
	if master_area != null and is_instance_valid(master_area):
		master_area.call("request_link_selected_creature_to_named_token")


func get_selected_tokens_for_master_area() -> Array[CharacterBody3D]:
	_clean_selection()
	return _selected_tokens.duplicate()


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


func start_combat_mode() -> void:
	if (
		initiative_tracker == null
		or not is_instance_valid(initiative_tracker)
	):
		return
	initiative_tracker.call("start_combat")


func end_combat_mode() -> void:
	if (
		initiative_tracker == null
		or not is_instance_valid(initiative_tracker)
	):
		return
	initiative_tracker.call("end_combat")


func toggle_grid() -> void:
	push_undo_state()
	set_grid_visible(not volumetric_grid.visible)


func set_grid_visible(enabled: bool) -> void:
	volumetric_grid.visible = enabled


# Alias di compatibilita: ora esiste una sola griglia volumetrica.
func toggle_grid_3d() -> void:
	toggle_grid()


func set_grid_3d_visible(enabled: bool) -> void:
	set_grid_visible(enabled)


func toggle_vision_cones() -> void:
	push_undo_state()
	set_vision_cones_visible(not _vision_cones_visible)


func set_vision_cones_visible(enabled: bool) -> void:
	_vision_cones_visible = enabled

	for child_node: Node in tokens_root.get_children():
		if child_node.is_in_group("dnd_token") \
		and child_node.has_method("set_vision_cone_visible"):
			child_node.call("set_vision_cone_visible", enabled)


func toggle_all_reach_spheres() -> void:
	if attack_system == null or not is_instance_valid(attack_system):
		return
	var visible := false
	if attack_system.has_method("are_all_reaches_visible"):
		visible = bool(attack_system.call("are_all_reaches_visible"))
	attack_system.call("set_all_reaches_visible", not visible)


func are_all_reach_spheres_visible() -> bool:
	return (
		attack_system != null
		and is_instance_valid(attack_system)
		and attack_system.has_method("are_all_reaches_visible")
		and bool(attack_system.call("are_all_reaches_visible"))
	)


func _toggle_measurement_mode() -> void:
	measurement_tool.aoe_mode = false
	var enabled: bool = bool(measurement_tool.call("toggle_measurement_mode"))
	measurement_mode_label.visible = enabled

	if enabled:
		measurement_mode_label.text = "MISURAZIONE  [R per uscire]"
	else:
		measurement_mode_label.text = ""


func _build_context_submenus() -> void:
	context_token_menu = _create_context_submenu("ContextTokenMenu")
	context_game_menu = _create_context_submenu("ContextGameMenu")
	context_measure_menu = _create_context_submenu("ContextMeasureMenu")
	context_view_menu = _create_context_submenu("ContextViewMenu")
	context_session_menu = _create_context_submenu("ContextSessionMenu")


func _create_context_submenu(menu_name: String) -> PopupMenu:
	var menu := PopupMenu.new()
	menu.name = menu_name
	menu.id_pressed.connect(_on_context_menu_id_pressed)
	context_menu.add_child(menu)
	return menu


func _prepare_context_submenus() -> void:
	context_token_menu.clear()
	context_game_menu.clear()
	context_measure_menu.clear()
	context_view_menu.clear()
	context_session_menu.clear()
	_limit_popup_menu(context_menu)
	_limit_popup_menu(context_token_menu)
	_limit_popup_menu(context_game_menu)
	_limit_popup_menu(context_measure_menu)
	_limit_popup_menu(context_view_menu)
	_limit_popup_menu(context_session_menu)


func _limit_popup_menu(menu: PopupMenu) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	menu.max_size = Vector2i(
		maxi(140, int(viewport_size.x) - 24),
		maxi(140, int(viewport_size.y) - 24)
	)


func _popup_context_menu(screen_position: Vector2) -> void:
	_limit_popup_menu(context_menu)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	context_menu.position = Vector2i(
		clampi(int(screen_position.x), 8, maxi(8, int(viewport_size.x) - 8)),
		clampi(int(screen_position.y), 8, maxi(8, int(viewport_size.y) - 8))
	)
	context_menu.popup()
	# Encounter subclasses append entries after super() returns. Reposition on
	# the next idle step using the popup's final size so it stays fully visible.
	call_deferred("_fit_context_menu_to_viewport", screen_position)


func _fit_context_menu_to_viewport(screen_position: Vector2) -> void:
	if context_menu == null or not is_instance_valid(context_menu):
		return
	if not context_menu.visible:
		return
	_limit_popup_menu(context_menu)
	var viewport_size := Vector2i(get_viewport().get_visible_rect().size)
	var popup_size := context_menu.size
	var margin := 8
	var max_x := maxi(margin, viewport_size.x - popup_size.x - margin)
	var max_y := maxi(margin, viewport_size.y - popup_size.y - margin)
	context_menu.position = Vector2i(
		clampi(int(screen_position.x), margin, max_x),
		clampi(int(screen_position.y), margin, max_y)
	)


func _popup_dialog_safe(
	dialog: Window,
	preferred_size: Vector2i,
	fallback_ratio: float = 0.92
) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var safe_size := Vector2i(
		mini(preferred_size.x, maxi(340, int(viewport_size.x) - 48)),
		mini(preferred_size.y, maxi(260, int(viewport_size.y) - 48))
	)
	dialog.popup_centered_clamped(safe_size, fallback_ratio)


func _show_context_menu(screen_position: Vector2) -> void:
	_clean_selection()
	_has_pending_spawn_position = false
	_pending_aoe_index = int(
		measurement_tool.call("get_aoe_index_at_screen", screen_position)
	)

	if _pending_aoe_index >= 0:
		context_menu.clear()
		context_menu.add_item("Dissolvi AoE", CONTEXT_DISSOLVE_AOE)
		_ui_owns_mouse = true
		_release_mouse()
		_popup_context_menu(screen_position)
		call_deferred("_release_mouse")
		return

	_context_token = null
	_pending_spawn_support = null
	var token_hit: Dictionary = _raycast_from_screen(
		screen_position,
		TOKEN_PICK_COLLISION_MASK,
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

	var hit: Dictionary = _raycast_from_screen(screen_position, 1 | 4, false)
	if not hit.is_empty():
		var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
		if hit_normal.dot(Vector3.UP) >= 0.35:
			_pending_spawn_position = hit.get("position", Vector3.ZERO)
			_has_pending_spawn_position = true
			var hit_collider := hit.get("collider") as Node3D
			if (
				hit_collider != null
				and hit_collider.is_in_group("tactical_platform")
			):
				_pending_spawn_support = hit_collider

	context_menu.clear()
	_prepare_context_submenus()

	if measurement_tool.is_measurement_mode():
		context_measure_menu.add_item("AoE: sfera", 20)
		context_measure_menu.add_item("AoE: cubo", 21)
		context_measure_menu.add_item("AoE: cono", 22)
		context_measure_menu.add_item("AoE: linea", 23)
		context_measure_menu.add_separator()
		context_measure_menu.add_item("Cancella tutte le AoE", 24)
		context_menu.add_submenu_node_item("Misura", context_measure_menu)

	if _has_pending_spawn_position:
		context_token_menu.add_item("Genera token", CONTEXT_CREATE_TOKEN)

	if not _selected_tokens.is_empty():
		if context_token_menu.item_count > 0:
			context_token_menu.add_separator()

		if _selected_tokens.size() == 1:
			context_token_menu.add_item("Modifica token…", CONTEXT_TOKEN_DETAILS)
			var selected_token: CharacterBody3D = _selected_tokens[0]
			if (
				selected_token != null
				and is_instance_valid(selected_token)
				and selected_token.has_method("has_previous_transformation")
				and bool(selected_token.call("has_previous_transformation"))
			):
				context_token_menu.add_item(
					"Ripristina aspetto precedente",
					CONTEXT_RESTORE_TRANSFORMATION
				)

		var count: int = _selected_tokens.size()
		var suffix: String = "" if count == 1 else " (%d)" % count
		context_token_menu.add_separator()
		context_token_menu.add_item(
			"Applica gravità" + suffix,
			CONTEXT_FLYING
		)
		context_token_menu.add_separator()
		context_token_menu.add_item(
			"Elimina token selezionati" + suffix,
			CONTEXT_DELETE_SELECTED
		)

	if context_token_menu.item_count > 0:
		context_menu.add_submenu_node_item("Token", context_token_menu)

	context_game_menu.add_item("Incantesimi", CONTEXT_SPELLS)
	context_game_menu.add_item("Area Player", CONTEXT_PLAYER_AREA)
	var initiative_visible: bool = (
		initiative_tracker != null
		and is_instance_valid(initiative_tracker)
		and bool(initiative_tracker.call("is_panel_visible"))
	)
	context_game_menu.add_item(
		"Nascondi iniziativa" if initiative_visible else "Mostra iniziativa",
		CONTEXT_INITIATIVE
	)
	context_menu.add_submenu_node_item("Gioco", context_game_menu)

	if volumetric_grid.visible:
		context_view_menu.add_item("Nascondi griglia", CONTEXT_TOGGLE_GRID)
	else:
		context_view_menu.add_item("Mostra griglia", CONTEXT_TOGGLE_GRID)
	if _vision_cones_visible:
		context_view_menu.add_item(
			"Nascondi coni visivi dei token",
			CONTEXT_TOGGLE_VISION_CONES
		)
	else:
		context_view_menu.add_item(
			"Mostra coni visivi dei token",
			CONTEXT_TOGGLE_VISION_CONES
		)
	if are_all_reach_spheres_visible():
		context_view_menu.add_item(
			"Nascondi gittate di tutte le creature",
			CONTEXT_TOGGLE_REACH_SPHERES
		)
	else:
		context_view_menu.add_item(
			"Mostra gittate di tutte le creature",
			CONTEXT_TOGGLE_REACH_SPHERES
		)
	context_view_menu.add_separator()
	context_view_menu.add_item("Velocità camera…", CONTEXT_CAMERA_SETTINGS)
	context_menu.add_submenu_node_item("Vista", context_view_menu)

	context_session_menu.add_item("Sincronizza mappa / Tailscale", 25)
	if scene_file_path != CAMPAIGN_EDITOR_SCENE_PATH:
		context_session_menu.add_separator()
		context_session_menu.add_item(
			"Torna al menu VTT",
			CONTEXT_MAIN_MENU
		)
	context_menu.add_submenu_node_item("Sessione", context_session_menu)

	_ui_owns_mouse = true
	_release_mouse()
	_popup_context_menu(screen_position)
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

	if id == CONTEXT_PLAYER_AREA:
		context_menu.hide()
		if player_area != null and is_instance_valid(player_area):
			player_area.call_deferred("show_panel")
		return

	if id == CONTEXT_TOKEN_DETAILS:
		open_selected_token_state_editor()
		return

	if id == CONTEXT_RESTORE_TRANSFORMATION:
		if _selected_tokens.size() == 1:
			var token: CharacterBody3D = _selected_tokens[0]
			if (
				token != null
				and is_instance_valid(token)
				and token.has_method("restore_previous_transformation")
			):
				push_undo_state()
				token.call("restore_previous_transformation")
				_refresh_token_views_after_appearance_change()
		_close_context_menu_to_game()
		return

	if id == CONTEXT_DISSOLVE_AOE:
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
		_popup_dialog_safe(share_dialog, Vector2i(620, 430))
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
			var gravity_tokens: Array[CharacterBody3D] = []
			for token: CharacterBody3D in _selected_tokens:
				if token != null and is_instance_valid(token) and bool(token.get("flying")):
					gravity_tokens.append(token)
			if not gravity_tokens.is_empty():
				push_undo_state()
				for token: CharacterBody3D in gravity_tokens:
					if token.has_method("apply_gravity"):
						token.call("apply_gravity")
					else:
						token.call("set_flying", false)
			_close_context_menu_to_game()
		CONTEXT_TOGGLE_GRID:
			toggle_grid()
			_close_context_menu_to_game()

		CONTEXT_TOGGLE_VISION_CONES:
			toggle_vision_cones()
			_close_context_menu_to_game()

		CONTEXT_TOGGLE_REACH_SPHERES:
			toggle_all_reach_spheres()
			_close_context_menu_to_game()

		CONTEXT_CAMERA_SETTINGS:
			open_camera_settings()

		CONTEXT_CREATE_TOKEN:
			if not _has_pending_spawn_position:
				return
			_token_generation_confirmed_callback = Callable()
			_token_generation_canceled_callback = Callable()
			_token_generation_exact_position = (
				_pending_spawn_support != null
				and is_instance_valid(_pending_spawn_support)
			)
			_token_generation_place_on_surface = _token_generation_exact_position
			_open_token_generation_dialog()

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
	_popup_dialog_safe(camera_settings_dialog, Vector2i(460, 240))
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


func _build_opportunity_attack_dialog() -> void:
	opportunity_dialog = PanelContainer.new()
	opportunity_dialog.name = "OpportunityAttackNotice"
	opportunity_dialog.anchor_left = 0.5
	opportunity_dialog.anchor_right = 0.5
	opportunity_dialog.offset_left = -260.0
	opportunity_dialog.offset_top = 82.0
	opportunity_dialog.offset_right = 260.0
	opportunity_dialog.offset_bottom = 132.0
	opportunity_dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opportunity_dialog.z_index = 95
	opportunity_dialog.hide()
	$UI.add_child(opportunity_dialog)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.04, 0.05, 0.86)
	style.border_color = Color(0.72, 0.48, 0.20, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	opportunity_dialog.add_theme_stylebox_override("panel", style)

	opportunity_label = Label.new()
	opportunity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opportunity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	opportunity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	opportunity_label.add_theme_font_size_override("font_size", 13)
	opportunity_dialog.add_child(opportunity_label)


func _close_opportunity_attack_dialog() -> void:
	_opportunity_notice_generation += 1
	if opportunity_dialog != null:
		opportunity_dialog.hide()


func _show_opportunity_notice(lines: PackedStringArray) -> void:
	if (
		opportunity_dialog == null
		or opportunity_label == null
		or lines.is_empty()
	):
		return
	_opportunity_notice_generation += 1
	var generation := _opportunity_notice_generation
	opportunity_label.text = "\n".join(lines)
	opportunity_dialog.show()

	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(
		func() -> void:
			if (
				generation == _opportunity_notice_generation
				and opportunity_dialog != null
			):
				opportunity_dialog.hide()
	)


func _token_reach_feet(token: CharacterBody3D) -> float:
	if token != null and is_instance_valid(token):
		if token.has_method("get_reach_feet"):
			return maxf(float(token.call("get_reach_feet")), 1.0)
		var footprint_value: Variant = token.get("_footprint_cells")
		if footprint_value is float or footprint_value is int:
			return maxf(5.0, float(footprint_value) * 5.0)
	return 5.0


func _token_party_key(token: CharacterBody3D) -> String:
	if token == null or not is_instance_valid(token):
		return ""
	var value := ""
	if token.has_method("get_effective_party_id"):
		value = String(token.call("get_effective_party_id"))
	elif token.has_method("get_party_id"):
		value = String(token.call("get_party_id"))
	else:
		value = String(token.get_meta("party_id", ""))
	value = value.strip_edges()
	return (value if not value.is_empty() else "Default").to_lower()


func _token_half_extents_world(token: CharacterBody3D) -> Vector3:
	return FlankingGeometry.token_half_extents_world(
		token,
		maxf(cell_size, 0.001)
	)


func _tactical_distance_to_position_feet(
	attacker: CharacterBody3D,
	target: CharacterBody3D,
	target_position: Vector3
) -> float:
	return FlankingGeometry.tactical_reach_distance_feet(
		attacker.global_position,
		_token_half_extents_world(attacker),
		target_position,
		_token_half_extents_world(target),
		maxf(cell_size, 0.001)
	)


func _token_notice_name(token: CharacterBody3D) -> String:
	if token != null and is_instance_valid(token):
		if token.has_method("get_display_name"):
			var display_name: String = String(
				token.call("get_display_name")
			).strip_edges()
			if not display_name.is_empty():
				return display_name
		return String(token.name)
	return "Creatura"


func check_opportunity_attacks_after_movement(
	moved_tokens: Array[CharacterBody3D],
	origins: Array[Vector3]
) -> void:
	if moved_tokens.is_empty() or moved_tokens.size() != origins.size():
		return

	var moved_lookup: Dictionary = {}
	for moved_token: CharacterBody3D in moved_tokens:
		if moved_token != null and is_instance_valid(moved_token):
			moved_lookup[moved_token.get_instance_id()] = true

	var notices := PackedStringArray()
	for index: int in range(moved_tokens.size()):
		var moved_token: CharacterBody3D = moved_tokens[index]
		if moved_token == null or not is_instance_valid(moved_token):
			continue
		var old_position: Vector3 = origins[index]
		var new_position: Vector3 = moved_token.global_position

		for node: Node in get_tree().get_nodes_in_group("dnd_token"):
			if not node is CharacterBody3D:
				continue
			var attacker: CharacterBody3D = node as CharacterBody3D
			if (
				attacker == moved_token
				or not is_instance_valid(attacker)
				or not is_ancestor_of(attacker)
				or moved_lookup.has(attacker.get_instance_id())
			):
				continue

			if _token_party_key(attacker) == _token_party_key(moved_token):
				continue

			var reach_feet: float = _token_reach_feet(attacker)
			var before_feet := _tactical_distance_to_position_feet(
				attacker,
				moved_token,
				old_position
			)
			var after_feet := _tactical_distance_to_position_feet(
				attacker,
				moved_token,
				new_position
			)
			if (
				before_feet <= reach_feet + 0.001
				and after_feet > reach_feet + 0.001
			):
				var notice: String = "⚔ %s → %s · opportunità" % [
					_token_notice_name(attacker),
					_token_notice_name(moved_token)
				]
				notices.append(notice)

	if notices.is_empty() or opportunity_dialog == null:
		return

	_show_opportunity_notice(notices)


func _build_token_state_dialog() -> void:
	# Nome, party, condizioni e miniatura condividono lo stesso editor usato
	# sia per creare sia per modificare un token.
	token_state_dialog = null
	var content_box: VBoxContainer = (
		color_dialog.get_node_or_null("Content/VBox") as VBoxContainer
	)
	if content_box == null:
		return

	token_identity_label = Label.new()
	token_identity_label.name = "TokenIdentityLabel"
	token_identity_label.text = "ID token: assegnato automaticamente alla creazione"
	token_identity_label.add_theme_font_size_override("font_size", 11)
	content_box.add_child(token_identity_label)

	var party_label := Label.new()
	party_label.name = "PartyLabel"
	party_label.text = "Party / gruppo tattico"
	content_box.add_child(party_label)

	token_party_input = LineEdit.new()
	token_party_input.name = "PartyInput"
	token_party_input.placeholder_text = "Vuoto = party Default"
	token_party_input.max_length = 80
	token_party_input.tooltip_text = (
		"Token senza party esplicito appartengono tutti al party Default."
	)
	content_box.add_child(token_party_input)

	var party_help := Label.new()
	party_help.name = "PartyHelp"
	party_help.text = (
		"Lascia vuoto per usare il party Default. Token con lo stesso party "
		+ "sono alleati ai fini dell'affiancamento."
	)
	party_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	party_help.add_theme_font_size_override("font_size", 11)
	content_box.add_child(party_help)

	var states_label := Label.new()
	states_label.name = "StatesLabel"
	states_label.text = "Condizioni e marker D&D 5e"
	states_label.add_theme_font_size_override("font_size", 14)
	content_box.add_child(states_label)

	token_state_grid = GridContainer.new()
	token_state_grid.name = "TokenStateGrid"
	token_state_grid.columns = 2
	token_state_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	token_state_grid.add_theme_constant_override("h_separation", 16)
	token_state_grid.add_theme_constant_override("v_separation", 4)
	content_box.add_child(token_state_grid)

	token_state_checks.clear()
	for value: Variant in TokenScript.CONDITION_DEFINITIONS:
		if not value is Dictionary:
			continue
		var definition := value as Dictionary
		var condition_id := String(definition.get("id", ""))
		if condition_id.is_empty():
			continue
		var check := CheckButton.new()
		var label_text := "%s  %s" % [
			String(definition.get("icon", "[--]")),
			String(definition.get("name", condition_id))
		]
		if not bool(definition.get("official", true)):
			label_text += "  (marker)"
		check.text = label_text
		token_state_grid.add_child(check)
		token_state_checks[condition_id] = check

	var help := Label.new()
	help.name = "StatesHelp"
	help.text = (
		"I primi 15 elementi sono le condizioni ufficiali 5e/SRD; "
		+ "gli altri sono marker tattici."
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 11)
	content_box.add_child(help)


func _set_shared_token_editor_conditions(value: Variant) -> void:
	var active: Array = []
	if value is Array:
		active = value as Array
	for condition_id: Variant in token_state_checks.keys():
		var check: CheckButton = token_state_checks[condition_id] as CheckButton
		if check != null:
			check.set_pressed_no_signal(String(condition_id) in active)


func _shared_token_editor_conditions() -> Array[String]:
	var active: Array[String] = []
	for condition_id: Variant in token_state_checks.keys():
		var check: CheckButton = token_state_checks[condition_id] as CheckButton
		if check != null and check.button_pressed:
			active.append(String(condition_id))
	return active


func open_selected_token_state_editor() -> void:
	_clean_selection()
	if _selected_tokens.size() != 1:
		_close_context_menu_to_game()
		return
	if context_menu.visible:
		context_menu.hide()
	open_token_transformation(_selected_tokens[0])


func _open_token_state_editor(token: CharacterBody3D) -> void:
	# Compatibilità per eventuali chiamanti esistenti.
	open_token_transformation(token)


func _apply_token_state_editor() -> void:
	# L'editor stato è ora lo stesso ConfirmationDialog dell'editor token.
	_on_token_dialog_confirmed()


func _close_token_state_editor() -> void:
	_reset_token_generation_state()


func _close_context_menu_to_game() -> void:
	_ui_owns_mouse = false
	_capture_mouse()


func _on_context_menu_hidden() -> void:
	if (
		color_dialog.visible
		or (is_instance_valid(share_dialog) and share_dialog.visible)
		or (is_instance_valid(map_save_dialog) and map_save_dialog.visible)
		or (is_instance_valid(map_load_dialog) and map_load_dialog.visible)
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
		or (is_instance_valid(map_save_dialog) and map_save_dialog.visible)
		or (is_instance_valid(map_load_dialog) and map_load_dialog.visible)
		or (is_instance_valid(token_state_dialog) and token_state_dialog.visible)
		or (
			is_instance_valid(camera_settings_dialog)
			and camera_settings_dialog.visible
		)
	):
		return
	var spell_panel_open: bool = (
		spell_system != null
		and is_instance_valid(spell_system)
		and bool(spell_system.call("is_panel_open"))
	)
	var player_panel_open: bool = (
		player_area != null
		and is_instance_valid(player_area)
		and player_area.has_method("is_panel_open")
		and bool(player_area.call("is_panel_open"))
	)
	if spell_panel_open or player_panel_open:
		_pending_aoe_index = -1
		_context_token = null
		_ui_owns_mouse = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	_pending_aoe_index = -1
	_context_token = null
	_ui_owns_mouse = false
	_capture_mouse()


func open_token_generation_at(
	world_position: Vector3,
	confirmed_callback: Callable = Callable(),
	canceled_callback: Callable = Callable(),
	place_on_surface: bool = false
) -> void:
	_pending_spawn_position = world_position
	_has_pending_spawn_position = true
	_pending_spawn_support = null
	_token_generation_transform_target = null
	_token_generation_confirmed_callback = confirmed_callback
	_token_generation_canceled_callback = canceled_callback
	_token_generation_exact_position = true
	_token_generation_place_on_surface = place_on_surface
	_open_token_generation_dialog()


func open_token_transformation(
	target: CharacterBody3D,
	confirmed_callback: Callable = Callable(),
	canceled_callback: Callable = Callable()
) -> void:
	if target == null or not is_instance_valid(target):
		if canceled_callback.is_valid():
			canceled_callback.call()
		return

	_token_generation_transform_target = target
	_token_generation_confirmed_callback = confirmed_callback
	_token_generation_canceled_callback = canceled_callback
	_token_generation_exact_position = false
	_token_generation_place_on_surface = false
	_has_pending_spawn_position = false
	_open_token_generation_dialog()


func _existing_token_profile_id(token: CharacterBody3D) -> String:
	var visual_asset := (
		String(token.call("get_visual_asset_path")).strip_edges()
		if token.has_method("get_visual_asset_path")
		else ""
	)
	for profile: Dictionary in _token_profiles:
		if _token_profile_visual_asset(profile) == visual_asset:
			return String(profile.get("id", ""))

	var stable_id := (
		String(token.call("get_token_id"))
		if token.has_method("get_token_id")
		else str(token.get_instance_id())
	)
	var synthetic_id := "current:" + stable_id
	for profile: Dictionary in _token_profiles:
		if String(profile.get("id", "")) == synthetic_id:
			return synthetic_id

	var size_name := (
		String(token.call("get_size_name"))
		if token.has_method("get_size_name")
		else "Medium"
	)
	var footprint := (
		float(token.call("get_footprint_cells"))
		if token.has_method("get_footprint_cells")
		else 1.0
	)
	_token_profiles.append({
		"id": synthetic_id,
		"name": (
			String(token.call("get_display_name"))
			if token.has_method("get_display_name")
			else "Token attuale"
		),
		"visual_asset": visual_asset,
		"size_name": size_name,
		"footprint": footprint,
		"token_pack_id": (
			String(token.call("get_token_pack_id"))
			if token.has_method("get_token_pack_id")
			else ""
		),
		"_pack_origin": "current",
	})
	_token_profiles.sort_custom(Callable(self, "_sort_token_profiles"))
	return synthetic_id


func _load_shared_token_editor_from_target(token: CharacterBody3D) -> void:
	if token == null or not is_instance_valid(token):
		return
	if token_name_input != null:
		var current_display_name := (
			String(token.call("get_display_name"))
			if token.has_method("get_display_name")
			else ""
		)
		_set_token_name_input(current_display_name, false)
	if token_party_input != null:
		token_party_input.text = (
			String(token.call("get_party_id"))
			if token.has_method("get_party_id")
			else String(token.get_meta("party_id", ""))
		)

	var size_name := (
		String(token.call("get_size_name"))
		if token.has_method("get_size_name")
		else "Medium"
	)
	for size_index: int in range(TOKEN_SIZES.size()):
		if String(TOKEN_SIZES[size_index].get("name", "")) == size_name:
			size_selector.select(size_index)
			break

	if token_reach_input != null and token.has_method("get_reach_feet"):
		token_reach_input.value = float(token.call("get_reach_feet"))
	if token_front_selector != null and token.has_method(
		"get_visual_front_quarter_turns"
	):
		token_front_selector.select(
			clampi(int(token.call("get_visual_front_quarter_turns")), 0, 3)
		)

	var conditions: Variant = []
	if token.has_method("get_conditions"):
		conditions = token.call("get_conditions")
	_set_shared_token_editor_conditions(conditions)


func _prepare_shared_token_editor() -> void:
	var editing := (
		_token_generation_transform_target != null
		and is_instance_valid(_token_generation_transform_target)
	)
	if editing:
		color_dialog.title = "Modifica token"
		color_dialog.ok_button_text = "Applica"
		color_dialog.get_ok_button().text = "Applica"
		color_dialog.get_ok_button().show()
		var target := _token_generation_transform_target
		if token_identity_label != null:
			token_identity_label.text = (
				"ID token: %s"
				% (
					String(target.call("get_token_id"))
					if target.has_method("get_token_id")
					else str(target.get_instance_id())
				)
			)
		var preferred_id := _existing_token_profile_id(target)
		if token_miniature_search != null:
			token_miniature_search.text = ""
		_refresh_token_miniature_filter("", preferred_id)
		_load_shared_token_editor_from_target(target)
	else:
		color_dialog.title = "Crea token"
		color_dialog.ok_button_text = "Crea"
		color_dialog.get_ok_button().text = "Crea"
		color_dialog.get_ok_button().show()
		if token_identity_label != null:
			token_identity_label.text = (
				"ID token: assegnato automaticamente alla creazione"
			)
		if token_party_input != null:
			token_party_input.text = ""
		_set_shared_token_editor_conditions([])


func _open_token_generation_dialog() -> void:
	if (
		not _has_pending_spawn_position
		and (
			_token_generation_transform_target == null
			or not is_instance_valid(_token_generation_transform_target)
		)
	):
		return

	_ui_owns_mouse = true
	var editing_existing := (
		_token_generation_transform_target != null
		and is_instance_valid(_token_generation_transform_target)
	)
	_token_name_is_auto = not editing_existing
	if not editing_existing:
		if token_miniature_list != null and not _token_profiles.is_empty():
			var selected_items: PackedInt32Array = (
				token_miniature_list.get_selected_items()
			)
			var selected_index: int = (
				int(selected_items[0])
				if not selected_items.is_empty()
				else 0
			)
			token_miniature_list.select(selected_index)
			_on_token_miniature_selected(selected_index)

	_prepare_shared_token_editor()
	_popup_dialog_safe(color_dialog, Vector2i(650, 760))
	call_deferred("_release_mouse")


func _reset_token_generation_state() -> void:
	_token_generation_confirmed_callback = Callable()
	_token_generation_canceled_callback = Callable()
	_token_generation_transform_target = null
	_token_generation_exact_position = false
	_token_generation_place_on_surface = false
	_has_pending_spawn_position = false
	_pending_spawn_support = null
	_token_name_is_auto = true
	_updating_token_name_input = false
	_ui_owns_mouse = false
	_capture_mouse()


func _on_token_dialog_confirmed() -> void:
	var selected_origin := String(
		_selected_token_profile.get("_pack_origin", "")
	)
	if selected_origin in ["remote", "local_pack"]:
		var pack_id := String(_selected_token_profile.get("id", ""))
		if not TokenPackManager.is_mounted(pack_id):
			var mount_error := OK
			if selected_origin == "local_pack":
				mount_error = TokenPackManager.mount_local_token(
					pack_id,
					_selected_token_profile,
					String(
						_selected_token_profile.get("_local_pck_path", "")
					)
				)
			else:
				if not TokenPackManager.is_downloaded(pack_id):
					push_warning(
						"DnDBase: scarica prima il token remoto: %s" % pack_id
					)
					return
				mount_error = TokenPackManager.mount_token(pack_id)
			if mount_error != OK:
				_on_remote_token_mount_failed(
					pack_id,
					"Mount non riuscito: %s" % error_string(mount_error)
				)
				return
		_selected_token_profile["visual_asset"] = _remote_visual_path(pack_id)

	var selected_pack_id := ""
	if selected_origin in ["remote", "local_pack"]:
		selected_pack_id = String(
			_selected_token_profile.get("id", "")
		).strip_edges()
	elif selected_origin == "current":
		selected_pack_id = String(
			_selected_token_profile.get("token_pack_id", "")
		).strip_edges()

	var selected_index: int = size_selector.selected
	if selected_index < 0 or selected_index >= TOKEN_SIZES.size():
		selected_index = 2
	var selected_size: Dictionary = TOKEN_SIZES[selected_index]

	var size_name := String(selected_size.get("name", "Medium"))
	var footprint := float(selected_size.get("footprint", 1.0))
	var visual_native_footprint := maxf(
		float(_selected_token_profile.get("footprint", footprint)),
		0.5
	)
	var reach_feet: float = maxf(5.0, footprint * 5.0)
	if token_reach_input != null:
		reach_feet = maxf(float(token_reach_input.value), 5.0)
	var display_name := (
		token_name_input.text.strip_edges()
		if token_name_input != null
		else "Token"
	)
	var party_value := (
		token_party_input.text.strip_edges()
		if token_party_input != null
		else ""
	)
	var active_conditions := _shared_token_editor_conditions()
	var editing_existing := (
		_token_generation_transform_target != null
		and is_instance_valid(_token_generation_transform_target)
	)
	if display_name.is_empty() and not editing_existing:
		display_name = _token_profile_default_name(_selected_token_profile)

	if editing_existing:
		display_name = _unique_token_display_name(
			display_name,
			_token_generation_transform_target
		)

	var visual_asset := _token_profile_visual_asset(
		_selected_token_profile
	)
	var front_quarter_turns := 0
	if token_front_selector != null:
		front_quarter_turns = clampi(
			token_front_selector.selected,
			0,
			3
		)

	var created_token: CharacterBody3D
	if (
		_token_generation_transform_target != null
		and is_instance_valid(_token_generation_transform_target)
	):
		created_token = _token_generation_transform_target
		push_undo_state()
		if created_token.has_method("push_transformation_state"):
			created_token.call("push_transformation_state")
		var visual_applied: bool = true
		if (
			not visual_asset.is_empty()
			and created_token.has_method("set_visual_asset")
		):
			visual_applied = bool(
				created_token.call(
					"set_visual_asset",
					visual_asset,
					visual_native_footprint
				)
			)

		# Una trasformazione deve essere atomica. Prima questo risultato veniva
		# ignorato: un OBJ non caricabile lasciava il token con nome/taglia/reach
		# nuovi ma con la vecchia miniatura.
		if not visual_applied:
			if created_token.has_method("restore_previous_transformation"):
				created_token.call("restore_previous_transformation")
			var failed_callback: Callable = (
				_token_generation_canceled_callback
			)
			_reset_token_generation_state()
			push_error(
				"DnDBase: trasformazione annullata, impossibile caricare %s"
				% visual_asset
			)
			if failed_callback.is_valid():
				failed_callback.call()
			return

		if created_token.has_method("set_visual_front_quarter_turns"):
			created_token.call(
				"set_visual_front_quarter_turns",
				front_quarter_turns
			)
		if created_token.has_method("set_size_category"):
			created_token.call(
				"set_size_category",
				size_name,
				footprint,
				false
			)
		if created_token.has_method("set_reach_feet"):
			created_token.call("set_reach_feet", reach_feet, true)
		if created_token.has_method("set_display_name"):
			created_token.call("set_display_name", display_name)
		_refresh_token_views_after_appearance_change()
	else:
		created_token = _spawn_token(
			size_name,
			footprint,
			display_name,
			visual_asset,
			front_quarter_turns,
			reach_feet,
			visual_native_footprint
		)

	if created_token != null and is_instance_valid(created_token):
		if created_token.has_method("set_token_pack_id"):
			created_token.call("set_token_pack_id", selected_pack_id)
		if created_token.has_method("set_party_id"):
			created_token.call("set_party_id", party_value)
		else:
			created_token.set_meta("party_id", party_value)
		if created_token.has_method("set_conditions"):
			created_token.call("set_conditions", active_conditions)
		if flanking_system != null and is_instance_valid(flanking_system):
			flanking_system.call("refresh_now")
		if token_list != null and is_instance_valid(token_list):
			token_list.call("refresh")
		if initiative_tracker != null and is_instance_valid(initiative_tracker):
			initiative_tracker.call("refresh")

	var confirmed_callback: Callable = (
		_token_generation_confirmed_callback
	)
	_reset_token_generation_state()

	if confirmed_callback.is_valid():
		# ConfirmationDialog emette confirmed prima di completare il proprio
		# ciclo di chiusura. Rimandare il callback evita che Polymorph apra il
		# TS (o il dialogo del bersaglio successivo) mentre questo popup e'
		# ancora attivo.
		call_deferred(
			"_invoke_token_generation_confirmed",
			confirmed_callback,
			created_token
		)


func _invoke_token_generation_confirmed(
	callback: Callable,
	token: CharacterBody3D
) -> void:
	if callback.is_valid() and token != null and is_instance_valid(token):
		callback.call(token)


func _on_token_dialog_canceled() -> void:
	var canceled_callback: Callable = (
		_token_generation_canceled_callback
	)
	_reset_token_generation_state()

	if canceled_callback.is_valid():
		canceled_callback.call()


func _spawn_token(
	size_name: String,
	footprint_cells: float,
	display_name: String = "",
	visual_asset: String = "",
	front_quarter_turns: int = 0,
	reach_feet: float = 0.0,
	visual_native_footprint: float = 0.0
) -> CharacterBody3D:
	if token_scene == null:
		push_error("DnDBase: token_scene non assegnata.")
		return null

	display_name = _unique_token_display_name(display_name)
	push_undo_state()
	var token_instance: Node = token_scene.instantiate()
	if not (token_instance is CharacterBody3D):
		push_error(
			"DnDBase: token_scene deve avere un CharacterBody3D come nodo root."
		)
		token_instance.queue_free()
		return null

	var token: CharacterBody3D = token_instance as CharacterBody3D
	tokens_root.add_child(token)

	token.global_position = Vector3(
		_pending_spawn_position.x,
		(
			_pending_spawn_position.y
			if _token_generation_exact_position
			else _pending_spawn_position.y + token_spawn_height
		),
		_pending_spawn_position.z
	)

	if not visual_asset.is_empty() and token.has_method("set_visual_asset"):
		if not bool(
			token.call(
				"set_visual_asset",
				visual_asset,
				visual_native_footprint
			)
		):
			push_warning(
				"DnDBase: miniatura non caricata: %s" % visual_asset
			)
	if token.has_method("set_visual_front_quarter_turns"):
		token.call(
			"set_visual_front_quarter_turns",
			front_quarter_turns
		)

	if token.has_method("configure"):
		token.call(
			"configure",
			Color.WHITE,
			cell_size,
			size_name,
			footprint_cells
		)

	if _token_generation_exact_position and _token_generation_place_on_surface:
		var token_height: float = float(token.get("token_height_cells"))
		token.global_position.y = (
			_pending_spawn_position.y
			+ token_height * cell_size * 0.5
		)
		if (
			_pending_spawn_support != null
			and is_instance_valid(_pending_spawn_support)
		):
			token.set("grid_support", _pending_spawn_support)
			token.set(
				"_support_transform",
				_pending_spawn_support.global_transform
			)

	if token.has_method("set_reach_feet"):
		var resolved_reach: float = reach_feet
		if resolved_reach <= 0.0:
			resolved_reach = maxf(5.0, footprint_cells * 5.0)
		token.call("set_reach_feet", resolved_reach, true)

	if token.has_method("set_display_name"):
		token.call("set_display_name", display_name)

	if token.has_method("set_vision_cone_visible"):
		token.call("set_vision_cone_visible", _vision_cones_visible)

	_replace_selection(token)
	return token


func _interact_or_select_under_mouse(
	screen_position: Vector2,
	additive_selection: bool,
	first_person_request: bool
) -> void:
	var hit: Dictionary = _raycast_from_screen(
		screen_position,
		TOKEN_PICK_COLLISION_MASK,
		true
	)
	hit = _prefer_passenger_token_hit(screen_position, hit)

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


func get_attack_token_at_screen(
	screen_position: Vector2
) -> CharacterBody3D:
	var hit: Dictionary = _raycast_from_screen(
		screen_position,
		TOKEN_PICK_COLLISION_MASK,
		true
	)
	if hit.is_empty():
		return null

	hit = _prefer_passenger_token_hit(screen_position, hit)
	var collider: Node = hit.get("collider") as Node
	if collider == null:
		return null
	var target: Node = _find_interaction_target(collider)
	if (
		target != null
		and target is CharacterBody3D
		and target.is_in_group("dnd_token")
	):
		return target as CharacterBody3D
	return null


func _find_interaction_target(start_node: Node) -> Node:
	var current: Node = start_node

	while current != null and current != self:
		if current.is_in_group("dnd_token") or current.has_method("interact"):
			return current
		current = current.get_parent()

	return null


func set_token_selected_from_ui(
	token: CharacterBody3D,
	selected: bool
) -> void:
	_clean_selection()
	if token == null or not is_instance_valid(token):
		return
	if selected:
		_add_to_selection(token)
	else:
		_remove_from_selection(token)


func focus_camera_on_token(token: CharacterBody3D) -> void:
	if token == null or not is_instance_valid(token):
		return
	if camera.has_method("focus_on_token"):
		camera.call("focus_on_token", token)


func toggle_token_list() -> void:
	if token_list != null and is_instance_valid(token_list):
		token_list.call("toggle_panel")


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


func _remove_from_selection(token: CharacterBody3D) -> void:
	if token == null or not is_instance_valid(token):
		return
	_selected_tokens.erase(token)
	if token.has_method("set_selected"):
		token.call("set_selected", false)


func clear_token_selection() -> void:
	_clear_selection()


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
	if _selected_tokens.is_empty():
		return

	var before: Dictionary = begin_token_move_transaction(_selected_tokens)
	var origins: Array[Vector3] = []
	for token: CharacterBody3D in _selected_tokens:
		origins.append(token.global_position)

	for token: CharacterBody3D in _selected_tokens:
		if token.has_method("nudge_grid"):
			token.call("nudge_grid", direction)

	var moved: bool = _selected_tokens_moved_from(origins)
	if moved:
		commit_undo_transaction(before)
		check_opportunity_attacks_after_movement(
			_selected_tokens.duplicate(),
			origins
		)


func _move_selected_vertical(steps: int) -> void:
	_clean_selection()
	if _selected_tokens.is_empty():
		return

	var before: Dictionary = begin_token_move_transaction(_selected_tokens)
	var origins: Array[Vector3] = []
	for token: CharacterBody3D in _selected_tokens:
		origins.append(token.global_position)

	for token: CharacterBody3D in _selected_tokens:
		if token.has_method("nudge_vertical"):
			token.call("nudge_vertical", steps)

	var moved: bool = _selected_tokens_moved_from(origins)
	if moved:
		commit_undo_transaction(before)
		check_opportunity_attacks_after_movement(
			_selected_tokens.duplicate(),
			origins
		)


func _selected_tokens_moved_from(origins: Array[Vector3]) -> bool:
	if origins.size() != _selected_tokens.size():
		return true
	for index: int in range(_selected_tokens.size()):
		var token: CharacterBody3D = _selected_tokens[index]
		if (
			token != null
			and is_instance_valid(token)
			and not token.global_position.is_equal_approx(origins[index])
		):
			return true
	return false


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


func _prefer_passenger_token_hit(
	screen_position: Vector2,
	first_hit: Dictionary
) -> Dictionary:
	if first_hit.is_empty():
		return first_hit

	var collider: Node = first_hit.get("collider") as Node
	if collider == null:
		return first_hit

	var first_target: Node = _find_interaction_target(collider)
	if (
		first_target == null
		or not first_target.is_in_group("dnd_token")
		or not first_target.has_meta("compound_chariot")
		or not bool(first_target.get_meta("compound_chariot"))
	):
		return first_hit

	# Il collider principale del carro racchiude anche i passeggeri. Per il
	# picking soltanto, attraversiamo corpo e ponte del carro e controlliamo
	# se il cursore sta realmente intersecando un altro token.
	var exclusions: Array[RID] = []
	if first_target is CollisionObject3D:
		exclusions.append((first_target as CollisionObject3D).get_rid())
	if first_target.has_method("get_movement_exclusions"):
		var movement_exclusions: Variant = first_target.call(
			"get_movement_exclusions"
		)
		if movement_exclusions is Array:
			for value: Variant in movement_exclusions:
				if value is RID and not (value in exclusions):
					exclusions.append(value)

	var passenger_hit := _raycast_from_screen_excluding(
		screen_position,
		TOKEN_PICK_COLLISION_MASK,
		exclusions,
		true
	)
	if passenger_hit.is_empty():
		return first_hit

	var passenger_collider: Node = passenger_hit.get("collider") as Node
	if passenger_collider == null:
		return first_hit
	var passenger_target: Node = _find_interaction_target(passenger_collider)
	if (
		passenger_target != null
		and passenger_target != first_target
		and passenger_target.is_in_group("dnd_token")
	):
		return passenger_hit

	return first_hit


func _raycast_from_screen_excluding(
	screen_position: Vector2,
	collision_mask: int,
	exclusions: Array[RID],
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
	query.exclude = exclusions

	return get_world_3d().direct_space_state.intersect_ray(query)


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


func release_camera_control() -> void:
	_ui_owns_mouse = true
	_release_mouse()


func capture_camera_control() -> void:
	_ui_owns_mouse = false
	_capture_mouse()


func _capture_mouse() -> void:
	if not _ui_owns_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _share_session_key() -> String:
	if share_session == null:
		return "1"
	return str(clampi(int(share_session.value), 1, 5))


func _on_share_session_changed(_value: float) -> void:
	var key := _share_session_key()
	board_sync.listen(true, key)
	if dice_roller_chat != null and is_instance_valid(dice_roller_chat):
		dice_roller_chat.call("set_session_key", key)


func _build_share_dialog() -> void:
	share_dialog = AcceptDialog.new()
	share_dialog.title = "Mappa · locale e Tailscale"
	$UI.add_child(share_dialog)
	share_dialog.confirmed.connect(_close_context_menu_to_game)
	share_dialog.canceled.connect(_close_context_menu_to_game)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	share_dialog.add_child(layout)

	var info := Label.new()
	info.text = (
		"Puoi salvare o caricare una copia locale della mappa, oppure "
		+ "sincronizzarla con gli altri VTT via Tailscale. La ricezione "
		+ "di rete resta sempre attiva. Dice roller e chat usano un canale "
		+ "separato e non salvano né sincronizzano automaticamente la mappa."
	)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(info)

	var session_row := HBoxContainer.new()
	layout.add_child(session_row)

	var session_label := Label.new()
	session_label.text = "Partita:"
	session_row.add_child(session_label)

	share_session = SpinBox.new()
	share_session.min_value = 1.0
	share_session.max_value = 5.0
	share_session.step = 1.0
	share_session.value = 1.0
	share_session.allow_greater = false
	share_session.allow_lesser = false
	share_session.custom_minimum_size = Vector2(90, 0)
	share_session.tooltip_text = (
		"Solo i computer impostati sullo stesso numero di partita "
		+ "accettano la sincronizzazione."
	)
	share_session.value_changed.connect(_on_share_session_changed)
	session_row.add_child(share_session)

	var local_row := HBoxContainer.new()
	local_row.add_theme_constant_override("separation", 8)
	layout.add_child(local_row)

	var save_local := Button.new()
	save_local.text = "Salva mappa in locale"
	save_local.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	local_row.add_child(save_local)
	save_local.pressed.connect(_open_map_save_dialog)

	var load_local := Button.new()
	load_local.text = "Carica mappa locale"
	load_local.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	local_row.add_child(load_local)
	load_local.pressed.connect(_open_map_load_dialog)

	var send := Button.new()
	send.text = "Sincronizza mappa su Tailscale"
	layout.add_child(send)
	send.pressed.connect(
		func(): board_sync.send_snapshot_to_tailnet(_share_session_key())
	)

	_build_map_file_dialogs()

	share_status = Label.new()
	share_status.text = "Ricezione automatica · Partita 1"
	share_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(share_status)
	board_sync.status_changed.connect(
		func(message): share_status.text = message
	)


func _build_map_file_dialogs() -> void:
	var documents_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)

	map_save_dialog = FileDialog.new()
	map_save_dialog.title = "Salva mappa VTT"
	map_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	map_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	map_save_dialog.filters = PackedStringArray([
		"*.vttmap ; Mappa VTT",
		"*.json ; JSON"
	])
	map_save_dialog.current_file = _default_map_save_filename()
	if not documents_dir.is_empty():
		map_save_dialog.current_dir = documents_dir
	$UI.add_child(map_save_dialog)
	map_save_dialog.file_selected.connect(_on_map_save_file_selected)

	map_load_dialog = FileDialog.new()
	map_load_dialog.title = "Carica mappa VTT"
	map_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	map_load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	map_load_dialog.filters = PackedStringArray([
		"*.vttmap ; Mappa VTT",
		"*.json ; JSON"
	])
	if not documents_dir.is_empty():
		map_load_dialog.current_dir = documents_dir
	$UI.add_child(map_load_dialog)
	map_load_dialog.file_selected.connect(_on_map_load_file_selected)


func _default_map_save_filename() -> String:
	var base_name := scene_file_path.get_file().get_basename()
	if base_name.is_empty():
		base_name = "mappa"
	return "%s.vttmap" % base_name


func _open_map_save_dialog() -> void:
	if map_save_dialog == null or not is_instance_valid(map_save_dialog):
		return
	_ui_owns_mouse = true
	_release_mouse()
	map_save_dialog.current_file = _default_map_save_filename()
	_popup_dialog_safe(map_save_dialog, Vector2i(880, 620), 0.96)


func _open_map_load_dialog() -> void:
	if map_load_dialog == null or not is_instance_valid(map_load_dialog):
		return
	_ui_owns_mouse = true
	_release_mouse()
	_popup_dialog_safe(map_load_dialog, Vector2i(880, 620), 0.96)


func _on_map_save_file_selected(path: String) -> void:
	if board_sync == null or not is_instance_valid(board_sync):
		return
	var error := int(board_sync.call("save_snapshot_to_file", path))
	if error == OK:
		var clean_path := path.strip_edges()
		if clean_path.get_extension().is_empty():
			clean_path += ".vttmap"
		if map_load_dialog != null and is_instance_valid(map_load_dialog):
			map_load_dialog.current_path = clean_path


func _on_map_load_file_selected(path: String) -> void:
	if board_sync == null or not is_instance_valid(board_sync):
		return
	push_undo_state()
	var error := int(board_sync.call("load_snapshot_from_file", path))
	if error != OK and not _undo_stack.is_empty():
		_undo_stack.pop_back()
