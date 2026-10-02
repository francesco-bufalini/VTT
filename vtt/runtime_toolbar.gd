extends Node

const GRID := 10
const GAME_SPELLS := 11
const GAME_INITIATIVE := 12

const PLAYER_AREA_OPEN := 60
const PLAYER_ADD_CHARACTER := 61
const PLAYER_LINK_TOKEN := 62

const TOKEN_CREATE := 20
const TOKEN_FLYING := 21
const TOKEN_ROTATE_LEFT := 22
const TOKEN_ROTATE_RIGHT := 23
const TOKEN_DELETE := 24
const TOKEN_DETAILS := 25
const TOKEN_LIST := 26

const MEASURE_RULER := 30
const MEASURE_SPHERE := 31
const MEASURE_CUBE := 32
const MEASURE_CONE := 33
const MEASURE_LINE := 34
const MEASURE_CLEAR := 35

const VIEW_VISION := 40
const VIEW_CAMERA_SETTINGS := 41
const SHARE_OPEN := 50
const SESSION_SAVE := 51
const SESSION_MAIN_MENU := 52
const CAMPAIGN_EDITOR_SCENE_PATH := "res://vtt/editor/campaign_editor.tscn"

var board_root: Node3D
var ui_root: CanvasLayer
var status_label: Label


func setup(root: Node3D) -> void:
	board_root = root
	call_deferred("_initialize_toolbar")


func _initialize_toolbar() -> void:
	if board_root == null or not is_instance_valid(board_root):
		return
	if board_root.scene_file_path == CAMPAIGN_EDITOR_SCENE_PATH:
		queue_free()
		return

	ui_root = board_root.get_node_or_null("UI") as CanvasLayer
	if ui_root == null:
		queue_free()
		return

	var campaign_manager: Node = _campaign_manager()
	if campaign_manager != null:
		campaign_manager.call(
			"activate_campaign_for_scene",
			board_root.scene_file_path
		)

	_build_toolbar()
	call_deferred("_load_saved_state")


func _build_toolbar() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "RuntimeToolbar"
	panel.position = Vector2(8, 8)
	panel.custom_minimum_size = Vector2(0, 36)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(panel)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	panel.add_child(row)

	row.add_child(_menu("Token", [
		["Crea token", TOKEN_CREATE],
		["Applica gravità", TOKEN_FLYING],
		["Ruota sx", TOKEN_ROTATE_LEFT],
		["Ruota dx", TOKEN_ROTATE_RIGHT],
		["Nome e stati…", TOKEN_DETAILS],
		["Lista token", TOKEN_LIST],
		["Elimina", TOKEN_DELETE]
	], _on_token))

	row.add_child(_menu("Gioco", [
		["Incantesimi", GAME_SPELLS],
		["Iniziativa", GAME_INITIATIVE]
	], _on_game))

	row.add_child(_menu("Area Player", [
		["Apri Area Player", PLAYER_AREA_OPEN],
		["Aggiungi Personaggio", PLAYER_ADD_CHARACTER],
		["Collega personaggio a token", PLAYER_LINK_TOKEN]
	], _on_player))

	row.add_child(_menu("Misura", [
		["Righello", MEASURE_RULER],
		["AoE · Sfera", MEASURE_SPHERE],
		["AoE · Cubo", MEASURE_CUBE],
		["AoE · Cono", MEASURE_CONE],
		["AoE · Linea", MEASURE_LINE],
		["Cancella AoE", MEASURE_CLEAR]
	], _on_measure))

	row.add_child(_menu("Vista", [
		["Mostra / nascondi griglia", GRID],
		["Coni visivi", VIEW_VISION],
		["Velocità camera…", VIEW_CAMERA_SETTINGS]
	], _on_view))

	row.add_child(_menu("Sessione", [
		["Salva", SESSION_SAVE],
		["Condividi / Tailscale", SHARE_OPEN],
		["Torna al menu VTT", SESSION_MAIN_MENU]
	], _on_session))

	status_label = Label.new()
	status_label.text = ""
	status_label.custom_minimum_size = Vector2(90, 0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.clip_text = true
	row.add_child(status_label)


func _menu(label_text: String, items: Array, callback: Callable) -> MenuButton:
	var button: MenuButton = MenuButton.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(
		maxf(72.0, float(label_text.length() * 8 + 22)),
		30
	)
	button.add_theme_font_size_override("font_size", 13)

	var popup: PopupMenu = button.get_popup()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	popup.max_size = Vector2i(
		maxi(180, int(viewport_size.x) - 24),
		maxi(160, int(viewport_size.y) - 24)
	)
	for item: Array in items:
		popup.add_item(String(item[0]), int(item[1]))
	popup.id_pressed.connect(callback)
	return button


func _on_game(id: int) -> void:
	match id:
		GAME_SPELLS:
			board_root.call("toggle_spell_menu")
		GAME_INITIATIVE:
			board_root.call("toggle_initiative_panel")


func _on_player(id: int) -> void:
	match id:
		PLAYER_AREA_OPEN:
			board_root.call("toggle_player_area")
		PLAYER_ADD_CHARACTER:
			board_root.call("add_player_character")
		PLAYER_LINK_TOKEN:
			board_root.call("link_player_character_to_selected_token")


func _on_token(id: int) -> void:
	match id:
		TOKEN_CREATE:
			var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
			board_root.call("_show_context_menu", center)
		TOKEN_FLYING:
			board_root.call("_on_context_menu_id_pressed", 8)
		TOKEN_ROTATE_LEFT:
			board_root.call("_on_context_menu_id_pressed", 3)
		TOKEN_ROTATE_RIGHT:
			board_root.call("_on_context_menu_id_pressed", 4)
		TOKEN_DELETE:
			board_root.call("_on_context_menu_id_pressed", 2)
		TOKEN_DETAILS:
			board_root.call("open_selected_token_state_editor")
		TOKEN_LIST:
			board_root.call("toggle_token_list")


func _on_measure(id: int) -> void:
	var tool: Node = board_root.get_node_or_null("MeasurementTool")
	if tool == null:
		return

	if id == MEASURE_CLEAR:
		tool.call("clear_persistent_aoes")
		return

	if not bool(tool.call("is_measurement_mode")):
		tool.call("set_measurement_mode", true)

	var label: Label = board_root.get_node_or_null("UI/MeasurementModeLabel") as Label
	if id == MEASURE_RULER:
		tool.set("aoe_mode", false)
		if label != null:
			label.text = "MISURAZIONE  [R per uscire]"
			label.show()
		return

	var shape: String = ""
	match id:
		MEASURE_SPHERE:
			shape = "sphere"
		MEASURE_CUBE:
			shape = "cube"
		MEASURE_CONE:
			shape = "cone"
		MEASURE_LINE:
			shape = "line"

	if not shape.is_empty():
		tool.call("set_aoe_mode", shape)
		if label != null:
			label.text = "AoE: trascina clic sinistro | R per uscire"
			label.show()


func _on_view(id: int) -> void:
	match id:
		GRID:
			board_root.call("toggle_grid")
		VIEW_VISION:
			board_root.call("toggle_vision_cones")
		VIEW_CAMERA_SETTINGS:
			board_root.call("open_camera_settings")


func _on_session(id: int) -> void:
	match id:
		SESSION_SAVE:
			_save_current_state()
		SHARE_OPEN:
			board_root.call("_on_context_menu_id_pressed", 25)
		SESSION_MAIN_MENU:
			var campaign_manager: Node = _campaign_manager()
			if campaign_manager != null:
				campaign_manager.call("return_to_main_menu")


func _save_current_state() -> void:
	var campaign_manager: Node = _campaign_manager()
	var sync: Node = _board_sync()
	if campaign_manager == null or sync == null:
		_set_status("Salvataggio non disponibile")
		return

	var snapshot_value: Variant = sync.call("create_snapshot")
	if not snapshot_value is Dictionary:
		_set_status("Stato non disponibile")
		return

	var snapshot: Dictionary = snapshot_value as Dictionary
	if snapshot.is_empty():
		_set_status("Attendi la fine dell'azione")
		return

	var error: Error = int(
		campaign_manager.call("save_active_runtime_state", snapshot)
	)
	if error == OK:
		_set_status("Salvato")
	else:
		_set_status("Errore salvataggio")


func _load_saved_state() -> void:
	var campaign_manager: Node = _campaign_manager()
	var sync: Node = _board_sync()
	if campaign_manager == null or sync == null:
		return

	var state_value: Variant = campaign_manager.call(
		"load_active_runtime_state"
	)
	if not state_value is Dictionary:
		return

	var state: Dictionary = state_value as Dictionary
	if state.is_empty():
		return

	var applied: bool = bool(sync.call("apply_snapshot", state))
	if applied:
		_set_status("Salvataggio caricato")


func _board_sync() -> Node:
	if board_root == null or not is_instance_valid(board_root):
		return null

	var value: Variant = board_root.get("board_sync")
	if is_instance_valid(value) and value is Node:
		return value as Node
	return null


func _campaign_manager() -> Node:
	var manager: Node = get_node_or_null("/root/CampaignManager")
	if manager == null:
		push_error("CampaignManager autoload non disponibile.")
	return manager


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message
