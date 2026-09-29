extends Node

const GRID_2D := 10
const GRID_3D := 11

const TOKEN_CREATE := 20
const TOKEN_FLYING := 21
const TOKEN_ROTATE_LEFT := 22
const TOKEN_ROTATE_RIGHT := 23
const TOKEN_DELETE := 24

const MEASURE_RULER := 30
const MEASURE_SPHERE := 31
const MEASURE_CUBE := 32
const MEASURE_CONE := 33
const MEASURE_LINE := 34
const MEASURE_CLEAR := 35

const VIEW_VISION := 40
const SHARE_OPEN := 50

var board_root: Node3D
var ui_root: CanvasLayer


func setup(root: Node3D) -> void:
	board_root = root
	call_deferred("_initialize_toolbar")


func _initialize_toolbar() -> void:
	if board_root == null or not is_instance_valid(board_root):
		return
	if board_root.scene_file_path == CampaignManager.CAMPAIGN_EDITOR_SCENE:
		queue_free()
		return

	ui_root = board_root.get_node_or_null("UI") as CanvasLayer
	if ui_root == null:
		queue_free()
		return

	_build_toolbar()


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

	row.add_child(_menu("Griglia", [
		["Griglia 2D", GRID_2D],
		["Griglia 3D", GRID_3D]
	], _on_grid))

	row.add_child(_menu("Token", [
		["Crea token", TOKEN_CREATE],
		["Volante", TOKEN_FLYING],
		["Ruota sx", TOKEN_ROTATE_LEFT],
		["Ruota dx", TOKEN_ROTATE_RIGHT],
		["Elimina", TOKEN_DELETE]
	], _on_token))

	row.add_child(_menu("Misura", [
		["Righello", MEASURE_RULER],
		["AoE · Sfera", MEASURE_SPHERE],
		["AoE · Cubo", MEASURE_CUBE],
		["AoE · Cono", MEASURE_CONE],
		["AoE · Linea", MEASURE_LINE],
		["Cancella AoE", MEASURE_CLEAR]
	], _on_measure))

	row.add_child(_menu("Vista", [
		["Coni visivi", VIEW_VISION]
	], _on_view))

	row.add_child(_menu("Rete", [
		["Condividi / Tailscale", SHARE_OPEN]
	], _on_share))

	var menu_button: Button = Button.new()
	menu_button.text = "Menu"
	menu_button.custom_minimum_size = Vector2(54, 30)
	menu_button.add_theme_font_size_override("font_size", 13)
	menu_button.pressed.connect(
		func() -> void:
			CampaignManager.return_to_main_menu()
	)
	row.add_child(menu_button)


func _menu(label_text: String, items: Array, callback: Callable) -> MenuButton:
	var button: MenuButton = MenuButton.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(66, 30)
	button.add_theme_font_size_override("font_size", 13)

	var popup: PopupMenu = button.get_popup()
	for item: Array in items:
		popup.add_item(String(item[0]), int(item[1]))
	popup.id_pressed.connect(callback)
	return button


func _on_grid(id: int) -> void:
	match id:
		GRID_2D:
			board_root.call("toggle_grid")
		GRID_3D:
			board_root.call("toggle_grid_3d")


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
	if id == VIEW_VISION:
		board_root.call("toggle_vision_cones")


func _on_share(id: int) -> void:
	if id == SHARE_OPEN:
		board_root.call("_on_context_menu_id_pressed", 25)
