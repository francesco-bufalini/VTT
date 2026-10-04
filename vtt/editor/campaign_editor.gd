extends Node

const SAVE_VERSION := 1

const PRESET_SMALL := 100
const PRESET_STANDARD := 101
const PRESET_LARGE := 102
const PRESET_WHITE := 110
const PRESET_EMPTY_ELEMENTS := 120
const PRESET_FOREST_MOUNTAINS := 121

const FOREST_MOUNTAINS_PRESET_PATH := (
	"res://assets/presets/forest_mountains/forest_mountains_preset.glb"
)
const FOREST_MOUNTAINS_PRESET_ID := "forest_mountains"
const FOREST_MOUNTAINS_GRID_CELLS := 100
const FOREST_TERRAIN_MATERIALS := [
	"Material.001",
	"Material.007",
	"Material.008",
	"Material.009",
]

const GRID_RESIZE := 200
const GRID_ADD := 201
const GRID_REMOVE_LAST := 202

const TOKEN_LIBRARY := 300
const TOKEN_CREATE := 301
const TOKEN_FLYING := 302
const TOKEN_ROTATE_LEFT := 303
const TOKEN_ROTATE_RIGHT := 304
const TOKEN_DELETE := 305

const MEASURE_RULER := 400
const MEASURE_SPHERE := 401
const MEASURE_CUBE := 402
const MEASURE_CONE := 403
const MEASURE_LINE := 404
const MEASURE_CLEAR := 405

const VIEW_GRID := 500
const VIEW_VISION := 502

const SHARE_OPEN := 600

var board_root: Node3D
var ui_root: CanvasLayer
var status_label: Label

var primary_width_cells := 30
var primary_depth_cells := 30
var next_grid_id := 1
var active_element_preset: String = ""

var resize_dialog: ConfirmationDialog
var resize_width: SpinBox
var resize_depth: SpinBox

var add_grid_dialog: ConfirmationDialog
var add_x: SpinBox
var add_y: SpinBox
var add_z: SpinBox
var add_width: SpinBox
var add_depth: SpinBox

var leave_dialog: ConfirmationDialog


func _ready() -> void:
	board_root = get_parent() as Node3D
	if board_root == null:
		push_error("CampaignEditor: il controller deve essere figlio di DnDBase.")
		return

	# I nodi figli ricevono _ready prima del parent. Rimandiamo quindi
	# l'inizializzazione a quando dnd_base ha creato la griglia volumetrica,
	# BoardSync, token drag e gli altri servizi runtime.
	call_deferred("_initialize_editor")


func _initialize_editor() -> void:
	if board_root == null or not is_instance_valid(board_root):
		return

	ui_root = board_root.get_node("UI") as CanvasLayer
	_set_white_environment()
	_resize_primary_grid(primary_width_cells, primary_depth_cells)
	board_root.call("set_grid_visible", true)
	_build_toolbar()
	_build_grid_dialogs()
	_build_leave_dialog()

	# L'editor deve essere utilizzabile subito con il mouse. ESC continua a
	# catturare/liberare il cursore tramite la logica gia' presente in dnd_base.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_load_active_campaign()


func _build_toolbar() -> void:
	var panel := PanelContainer.new()
	panel.name = "CampaignToolbar"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 8
	panel.offset_top = 6
	panel.offset_right = -8
	panel.offset_bottom = 44
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	panel.add_child(row)

	row.add_child(_make_menu_button("Preset", [
		["Griglia piccola · 15 × 15", PRESET_SMALL],
		["Griglia standard · 30 × 30", PRESET_STANDARD],
		["Griglia grande · 50 × 50", PRESET_LARGE],
		["Scenario · Vuoto bianco", PRESET_WHITE],
		["Elementi · Nessuno", PRESET_EMPTY_ELEMENTS],
		["Elementi · Foresta e montagne", PRESET_FOREST_MOUNTAINS]
	], _on_preset_selected))

	row.add_child(_make_menu_button("Griglia", [
		["Dimensioni griglia principale…", GRID_RESIZE],
		["Inserisci nuova griglia…", GRID_ADD],
		["Rimuovi ultima griglia", GRID_REMOVE_LAST]
	], _on_grid_selected))

	var token_menu := _make_menu_button("Token", [
		["Libreria token · prossimamente", TOKEN_LIBRARY],
		["Crea token nel punto osservato…", TOKEN_CREATE],
		["Applica gravità · token selezionati", TOKEN_FLYING],
		["Ruota 45° a sinistra", TOKEN_ROTATE_LEFT],
		["Ruota 45° a destra", TOKEN_ROTATE_RIGHT],
		["Elimina token selezionati", TOKEN_DELETE]
	], _on_token_selected)
	token_menu.get_popup().set_item_disabled(
		token_menu.get_popup().get_item_index(TOKEN_LIBRARY),
		true
	)
	row.add_child(token_menu)

	var spells_button: Button = Button.new()
	spells_button.text = "Incantesimi"
	spells_button.custom_minimum_size = Vector2(82, 28)
	spells_button.add_theme_font_size_override("font_size", 13)
	spells_button.pressed.connect(
		func() -> void:
			board_root.call("toggle_spell_menu")
	)
	row.add_child(spells_button)

	var initiative_button: Button = Button.new()
	initiative_button.text = "Iniziativa"
	initiative_button.custom_minimum_size = Vector2(78, 28)
	initiative_button.add_theme_font_size_override("font_size", 13)
	initiative_button.pressed.connect(
		func() -> void:
			board_root.call("toggle_initiative_panel")
	)
	row.add_child(initiative_button)

	row.add_child(_make_menu_button("Misura", [
		["Righello", MEASURE_RULER],
		["AoE · Sfera", MEASURE_SPHERE],
		["AoE · Cubo", MEASURE_CUBE],
		["AoE · Cono", MEASURE_CONE],
		["AoE · Linea", MEASURE_LINE],
		["Cancella tutte le AoE", MEASURE_CLEAR]
	], _on_measurement_selected))

	row.add_child(_make_menu_button("Vista", [
		["Mostra / nascondi griglia", VIEW_GRID],
		["Mostra / nascondi coni visivi", VIEW_VISION]
	], _on_view_selected))

	row.add_child(_make_menu_button("Rete", [
		["Condividi mappa / Tailscale…", SHARE_OPEN]
	], _on_share_selected))

	status_label = Label.new()
	status_label.text = _campaign_name()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	status_label.add_theme_font_size_override("font_size", 12)
	row.add_child(status_label)

	var save_button := Button.new()
	save_button.text = "Salva"
	save_button.custom_minimum_size = Vector2(64, 28)
	save_button.add_theme_font_size_override("font_size", 13)
	save_button.pressed.connect(_save_campaign)
	row.add_child(save_button)

	var menu_button := Button.new()
	menu_button.text = "Menu"
	menu_button.custom_minimum_size = Vector2(56, 28)
	menu_button.add_theme_font_size_override("font_size", 13)
	menu_button.pressed.connect(
		func() -> void:
			leave_dialog.reset_size()
			leave_dialog.popup_centered_clamped(Vector2i(470, 190), 0.92)
	)
	row.add_child(menu_button)


func _make_menu_button(
	label_text: String,
	items: Array,
	callback: Callable
) -> MenuButton:
	var button := MenuButton.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(72, 28)
	button.add_theme_font_size_override("font_size", 13)

	var popup := button.get_popup()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	popup.max_size = Vector2i(
		maxi(180, int(viewport_size.x) - 24),
		maxi(160, int(viewport_size.y) - 24)
	)
	popup.add_theme_font_size_override("font_size", 13)
	for item: Array in items:
		popup.add_item(String(item[0]), int(item[1]))
	popup.id_pressed.connect(callback)
	return button


func _on_preset_selected(id: int) -> void:
	match id:
		PRESET_SMALL:
			_resize_primary_grid(15, 15)
			_set_status("Preset griglia: 15 × 15")
		PRESET_STANDARD:
			_resize_primary_grid(30, 30)
			_set_status("Preset griglia: 30 × 30")
		PRESET_LARGE:
			_resize_primary_grid(50, 50)
			_set_status("Preset griglia: 50 × 50")
		PRESET_WHITE:
			_set_white_environment()
			_set_status("Scenario: vuoto bianco")
		PRESET_EMPTY_ELEMENTS:
			_clear_element_presets()
			active_element_preset = ""
			_set_status("Preset elementi: nessun elemento")
		PRESET_FOREST_MOUNTAINS:
			_apply_forest_mountains_preset(true)


func _apply_forest_mountains_preset(resize_grid: bool = true) -> void:
	_clear_element_presets()

	# FileAccess is used before load() so a missing optional binary asset does
	# not flood the Godot debugger with ResourceLoader errors.
	if not FileAccess.file_exists(FOREST_MOUNTAINS_PRESET_PATH):
		active_element_preset = ""
		_set_status(
			"Preset foresta non installato: manca forest_mountains_preset.glb"
		)
		return

	var packed: Resource = load(FOREST_MOUNTAINS_PRESET_PATH)
	if not packed is PackedScene:
		active_element_preset = ""
		_set_status("Preset foresta non caricabile")
		return

	var instance: Node = (packed as PackedScene).instantiate()
	if not instance is Node3D:
		instance.free()
		active_element_preset = ""
		_set_status("Preset foresta non e' una scena 3D")
		return

	var root := instance as Node3D
	root.name = "CampaignPreset_ForestMountains"
	root.scale = Vector3.ONE * _cell_size()
	root.add_to_group("campaign_preset_element")
	root.set_meta("campaign_preset_id", FOREST_MOUNTAINS_PRESET_ID)
	board_root.add_child(root)

	_build_forest_terrain_collisions(root)
	active_element_preset = FOREST_MOUNTAINS_PRESET_ID

	if resize_grid:
		_resize_primary_grid(
			FOREST_MOUNTAINS_GRID_CELLS,
			FOREST_MOUNTAINS_GRID_CELLS
		)

	_refresh_volumetric_grid()
	_set_status(
		"Preset: foresta e montagne · alberi 2×2 × 8 celle · griglia 100×100"
	)


func _build_forest_terrain_collisions(root: Node3D) -> void:
	for candidate: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if not _forest_mesh_is_terrain(mesh_instance):
			continue

		var faces: PackedVector3Array = mesh_instance.mesh.get_faces()
		if faces.is_empty():
			continue

		var body := StaticBody3D.new()
		body.name = "PresetTerrainCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group("campaign_preset_terrain")
		mesh_instance.add_child(body)

		var collision := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		collision.shape = shape
		body.add_child(collision)


func _forest_mesh_is_terrain(mesh_instance: MeshInstance3D) -> bool:
	var mesh: Mesh = mesh_instance.mesh
	for surface_index in range(mesh.get_surface_count()):
		var material: Material = mesh.surface_get_material(surface_index)
		if (
			material != null
			and material.resource_name in FOREST_TERRAIN_MATERIALS
		):
			return true

	# The optimized GLB keeps its merged geometry names equal to the original
	# material names. This fallback also works if Godot strips material names.
	return String(mesh_instance.name) in FOREST_TERRAIN_MATERIALS


func _clear_element_presets() -> void:
	for candidate: Node in get_tree().get_nodes_in_group(
		"campaign_preset_element"
	):
		if (
			candidate is Node3D
			and is_instance_valid(candidate)
			and board_root.is_ancestor_of(candidate)
		):
			(candidate as Node3D).free()
	_refresh_volumetric_grid()


func _on_grid_selected(id: int) -> void:
	match id:
		GRID_RESIZE:
			resize_width.value = primary_width_cells
			resize_depth.value = primary_depth_cells
			resize_dialog.reset_size()
			resize_dialog.popup_centered_clamped(Vector2i(460, 250), 0.92)
		GRID_ADD:
			add_grid_dialog.reset_size()
			add_grid_dialog.popup_centered_clamped(Vector2i(500, 430), 0.92)
		GRID_REMOVE_LAST:
			_remove_last_extra_grid()


func _on_token_selected(id: int) -> void:
	match id:
		TOKEN_CREATE:
			# Riutilizza il menu contestuale di dnd_base: il raycast al centro
			# individua il punto della superficie e rende disponibile "Genera token".
			var center := get_viewport().get_visible_rect().size * 0.5
			board_root.call("_show_context_menu", center)
		TOKEN_FLYING:
			board_root.call("_on_context_menu_id_pressed", 8)
		TOKEN_ROTATE_LEFT:
			board_root.call("_on_context_menu_id_pressed", 3)
		TOKEN_ROTATE_RIGHT:
			board_root.call("_on_context_menu_id_pressed", 4)
		TOKEN_DELETE:
			board_root.call("_on_context_menu_id_pressed", 2)


func _on_measurement_selected(id: int) -> void:
	var tool := board_root.get_node_or_null("MeasurementTool")
	if tool == null:
		return

	if id == MEASURE_CLEAR:
		tool.call("clear_persistent_aoes")
		_set_status("AoE persistenti cancellate")
		return

	if not bool(tool.call("is_measurement_mode")):
		tool.call("set_measurement_mode", true)

	var mode_label := board_root.get_node_or_null("UI/MeasurementModeLabel") as Label
	if id == MEASURE_RULER:
		tool.set("aoe_mode", false)
		if mode_label != null:
			mode_label.text = "MISURAZIONE  [R per uscire]"
			mode_label.show()
		_set_status("Righello attivo")
		return

	var shape := ""
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
		if mode_label != null:
			mode_label.text = "AoE: trascina clic sinistro | R per uscire"
			mode_label.show()
		_set_status("AoE attiva: %s" % shape)


func _on_view_selected(id: int) -> void:
	match id:
		VIEW_GRID:
			board_root.call("toggle_grid")
		VIEW_VISION:
			board_root.call("toggle_vision_cones")


func _on_share_selected(id: int) -> void:
	if id == SHARE_OPEN:
		# ID 25 e' gia' l'azione pubblicata dal context menu di dnd_base.
		board_root.call("_on_context_menu_id_pressed", 25)


func _build_grid_dialogs() -> void:
	resize_dialog = ConfirmationDialog.new()
	resize_dialog.title = "Dimensioni griglia principale"
	resize_dialog.ok_button_text = "Applica"
	resize_dialog.min_size = Vector2i(460, 250)
	ui_root.add_child(resize_dialog)

	var resize_body := _dialog_body(resize_dialog)
	resize_width = _spin_row(
		resize_body, "Quadretti X", 2, 200, 1, primary_width_cells
	)
	resize_depth = _spin_row(
		resize_body, "Quadretti Z", 2, 200, 1, primary_depth_cells
	)
	resize_dialog.confirmed.connect(
		func() -> void:
			_resize_primary_grid(
				int(resize_width.value),
				int(resize_depth.value)
			)
			_set_status(
				"Griglia principale: %d × %d"
				% [primary_width_cells, primary_depth_cells]
			)
	)

	add_grid_dialog = ConfirmationDialog.new()
	add_grid_dialog.title = "Inserisci nuova griglia"
	add_grid_dialog.ok_button_text = "Crea"
	add_grid_dialog.min_size = Vector2i(500, 430)
	ui_root.add_child(add_grid_dialog)

	var add_body := _dialog_body(add_grid_dialog)
	var explanation := Label.new()
	explanation.text = (
		"Posizione del centro e altezza della nuova superficie. "
		+ "Le dimensioni sono espresse in quadretti."
	)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_body.add_child(explanation)

	add_x = _spin_row(add_body, "Posizione X", -500, 500, 1, 0)
	add_y = _spin_row(add_body, "Altezza Y", -100, 500, 1, 5)
	add_z = _spin_row(add_body, "Posizione Z", -500, 500, 1, 0)
	add_width = _spin_row(add_body, "Quadretti X", 1, 200, 1, 10)
	add_depth = _spin_row(add_body, "Quadretti Z", 1, 200, 1, 10)

	add_grid_dialog.confirmed.connect(
		func() -> void:
			var data := {
				"id": next_grid_id,
				"x": add_x.value,
				"y": add_y.value,
				"z": add_z.value,
				"width": int(add_width.value),
				"depth": int(add_depth.value)
			}
			next_grid_id += 1
			_create_extra_grid(data)
			_set_status(
				"Nuova griglia %d × %d a quota %.1f"
				% [int(data.width), int(data.depth), float(data.y)]
			)
	)


func _dialog_body(dialog: ConfirmationDialog) -> VBoxContainer:
	dialog.add_theme_constant_override("buttons_min_width", 100)
	dialog.add_theme_constant_override("buttons_min_height", 34)
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(420, 0)
	body.add_theme_constant_override("separation", 8)
	dialog.add_child(body)
	return body


func _spin_row(
	parent: VBoxContainer,
	label_text: String,
	min_value: float,
	max_value: float,
	step: float,
	value: float
) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.custom_minimum_size = Vector2(150, 0)
	row.add_child(spin)
	return spin


func _build_leave_dialog() -> void:
	leave_dialog = ConfirmationDialog.new()
	leave_dialog.title = "Torna al menu"
	leave_dialog.dialog_text = (
		"Le modifiche non salvate andranno perse.\n"
		+ "Vuoi tornare al menu principale?"
	)
	leave_dialog.ok_button_text = "Torna al menu"
	ui_root.add_child(leave_dialog)
	leave_dialog.confirmed.connect(
		func() -> void:
			_campaign_manager().call("return_to_main_menu")
	)


func _resize_primary_grid(width_cells: int, depth_cells: int) -> void:
	primary_width_cells = maxi(width_cells, 2)
	primary_depth_cells = maxi(depth_cells, 2)

	var floor := board_root.get_node_or_null("Board/FloorCollision") as StaticBody3D
	var collision := board_root.get_node_or_null(
		"Board/FloorCollision/CollisionShape3D"
	) as CollisionShape3D
	if floor == null or collision == null:
		return

	var cell := _cell_size()
	var world_size := Vector3(
		primary_width_cells * cell,
		0.1,
		primary_depth_cells * cell
	)

	var shape := BoxShape3D.new()
	shape.size = world_size
	collision.shape = shape
	collision.position = Vector3(0, -0.05, 0)

	var visual := floor.get_node_or_null("CampaignPlatformVisual") as MeshInstance3D
	if visual == null:
		visual = MeshInstance3D.new()
		visual.name = "CampaignPlatformVisual"
		visual.position = Vector3(0, -0.05, 0)
		floor.add_child(visual)

	var mesh := BoxMesh.new()
	mesh.size = world_size
	mesh.material = _platform_material()
	visual.mesh = mesh

	_refresh_volumetric_grid()


func _create_extra_grid(data: Dictionary) -> void:
	var board := board_root.get_node_or_null("Board/MapGeometry") as Node3D
	if board == null:
		return

	var grid_id: int = int(data.get("id", next_grid_id))
	next_grid_id = maxi(next_grid_id, grid_id + 1)

	var body := StaticBody3D.new()
	body.name = "CampaignGrid_%03d" % grid_id
	body.position = Vector3(
		float(data.get("x", 0.0)),
		float(data.get("y", 0.0)),
		float(data.get("z", 0.0))
	)
	body.add_to_group("campaign_grid")
	body.add_to_group("tactical_platform")
	body.set_meta("campaign_grid_id", grid_id)
	body.set_meta("width_cells", int(data.get("width", 10)))
	body.set_meta("depth_cells", int(data.get("depth", 10)))
	board.add_child(body)

	var cell := _cell_size()
	var world_size := Vector3(
		int(data.get("width", 10)) * cell,
		0.1,
		int(data.get("depth", 10)) * cell
	)

	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.position = Vector3(0, -0.05, 0)
	var mesh := BoxMesh.new()
	mesh.size = world_size
	mesh.material = _platform_material()
	visual.mesh = mesh
	body.add_child(visual)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.position = Vector3(0, -0.05, 0)
	var shape := BoxShape3D.new()
	shape.size = world_size
	collision.shape = shape
	body.add_child(collision)

	_refresh_volumetric_grid()


func _remove_last_extra_grid() -> void:
	var grids: Array[Node3D] = _campaign_grid_nodes()
	if grids.is_empty():
		_set_status("Non ci sono griglie aggiuntive da rimuovere")
		return

	grids.sort_custom(
		func(a: Node3D, b: Node3D) -> bool:
			return int(a.get_meta("campaign_grid_id", 0)) < int(
				b.get_meta("campaign_grid_id", 0)
			)
	)
	var target: Node3D = grids[grids.size() - 1]
	target.free()
	_refresh_volumetric_grid()
	_set_status("Ultima griglia aggiuntiva rimossa")


func _remove_all_extra_grids() -> void:
	for node: Node3D in _campaign_grid_nodes():
		node.free()
	_refresh_volumetric_grid()


func _campaign_grid_nodes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for candidate: Node in get_tree().get_nodes_in_group("campaign_grid"):
		if (
			candidate is Node3D
			and is_instance_valid(candidate)
			and board_root.is_ancestor_of(candidate)
		):
			result.append(candidate as Node3D)
	return result


func _serialize_extra_grids() -> Array:
	var result: Array = []
	for node: Node3D in _campaign_grid_nodes():
		result.append({
			"id": int(node.get_meta("campaign_grid_id", 0)),
			"x": node.position.x,
			"y": node.position.y,
			"z": node.position.z,
			"width": int(node.get_meta("width_cells", 10)),
			"depth": int(node.get_meta("depth_cells", 10))
		})
	return result


func _save_campaign() -> void:
	if not _is_active_user_campaign():
		_set_status("Questa scena non e' una campagna utente salvabile")
		return

	var state := {
		"version": SAVE_VERSION,
		"primary_grid": {
			"width": primary_width_cells,
			"depth": primary_depth_cells
		},
		"extra_grids": _serialize_extra_grids(),
		"element_preset": active_element_preset,
		"view": _serialize_view_state(),
		"board_snapshot": _create_board_snapshot()
	}

	var error: Error = int(_campaign_manager().call("save_active_state", state))
	if error == OK:
		_set_status(
			"Salvato · %s" % Time.get_time_string_from_system()
		)
	else:
		_set_status("Errore salvataggio: %s" % error_string(error))


func _load_active_campaign() -> void:
	if not _is_active_user_campaign():
		_set_status("Editor aperto senza una campagna utente attiva")
		return

	var state: Dictionary = _load_active_state()
	if state.is_empty():
		_set_status("%s · nuovo salvataggio" % _campaign_name())
		return
	if int(state.get("version", -1)) != SAVE_VERSION:
		_set_status("Versione salvataggio non supportata")
		return

	var primary: Variant = state.get("primary_grid", {})
	if primary is Dictionary:
		_resize_primary_grid(
			int(primary.get("width", 30)),
			int(primary.get("depth", 30))
		)

	_remove_all_extra_grids()
	var max_id := 0
	var extras: Variant = state.get("extra_grids", [])
	if extras is Array:
		for item: Variant in extras:
			if item is Dictionary:
				_create_extra_grid(item)
				max_id = maxi(max_id, int(item.get("id", 0)))
	next_grid_id = max_id + 1

	_clear_element_presets()
	active_element_preset = String(
		state.get("element_preset", "")
	).strip_edges()
	if active_element_preset == FOREST_MOUNTAINS_PRESET_ID:
		_apply_forest_mountains_preset(false)

	_apply_view_state(state.get("view", {}))
	await get_tree().process_frame

	var snapshot: Variant = state.get("board_snapshot", {})
	if snapshot is Dictionary and not snapshot.is_empty():
		var sync := _board_sync()
		if sync != null:
			sync.call("apply_snapshot", snapshot)

	_set_status("%s · ultimo salvataggio caricato" % _campaign_name())


func _create_board_snapshot() -> Dictionary:
	var sync := _board_sync()
	if sync != null:
		var snapshot: Variant = sync.call("create_snapshot")
		if snapshot is Dictionary:
			return snapshot
	return {}


func _board_sync() -> Node:
	var value: Variant = board_root.get("board_sync")
	if is_instance_valid(value) and value is Node:
		return value as Node
	return null


func _serialize_view_state() -> Dictionary:
	var volumetric := board_root.get_node_or_null("VolumetricGrid") as Node3D
	var grid_visible := volumetric != null and volumetric.visible
	return {
		"grid": grid_visible,
		# Legacy keys are kept so existing campaign saves stay readable by
		# older builds; both now represent the same unified grid.
		"grid_2d": grid_visible,
		"grid_3d": grid_visible,
		"vision_cones": bool(board_root.get("_vision_cones_visible"))
	}


func _apply_view_state(value: Variant) -> void:
	if not value is Dictionary:
		return
	var data := value as Dictionary
	var grid_visible := bool(
		data.get(
			"grid",
			data.get("grid_3d", data.get("grid_2d", true))
		)
	)
	board_root.call("set_grid_visible", grid_visible)
	board_root.call(
		"set_vision_cones_visible",
		bool(data.get("vision_cones", false))
	)


func _set_white_environment() -> void:
	var world := board_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null:
		return

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.93, 0.94, 0.96, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.95, 0.96, 1.0, 1.0)
	environment.ambient_light_energy = 0.8
	world.environment = environment


func _platform_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.74, 0.78, 1.0)
	material.roughness = 0.9
	return material


func _refresh_volumetric_grid() -> void:
	var grid := board_root.get_node_or_null("VolumetricGrid") as Node3D
	if grid != null and grid.has_method("refresh"):
		grid.call_deferred("refresh")


func _cell_size() -> float:
	return maxf(float(board_root.get("cell_size")), 0.001)



func _campaign_manager() -> Node:
	var manager: Node = get_node_or_null("/root/CampaignManager")
	if manager == null:
		push_error("CampaignManager autoload non disponibile.")
	return manager


func _campaign_name() -> String:
	var manager: Node = _campaign_manager()
	if manager == null:
		return "Campagna"
	return String(manager.call("get_active_campaign_name"))


func _is_active_user_campaign() -> bool:
	var manager: Node = _campaign_manager()
	return manager != null and bool(manager.call("is_active_user_campaign"))


func _load_active_state() -> Dictionary:
	var manager: Node = _campaign_manager()
	if manager == null:
		return {}
	var value: Variant = manager.call("load_active_state")
	if value is Dictionary:
		return value as Dictionary
	return {}


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message
