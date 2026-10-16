extends Node

const DialogLayout = preload("res://vtt/dialog_layout.gd")

const SAVE_VERSION := 1

const PRESET_SMALL := 100
const PRESET_STANDARD := 101
const PRESET_LARGE := 102
const PRESET_WHITE := 110
const PRESET_EMPTY_ELEMENTS := 120
const PRESET_FOREST_MOUNTAINS := 121
const PRESET_PIRATE_SHIP := 122
const PRESET_CREATE_GRID := 123

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

const PIRATE_SHIP_PRESET_PATH := (
	"res://assets/presets/pirate_ship/sirens_light_pirate_ship_preset.glb"
)
const PIRATE_SHIP_PRESET_ID := "sirens_light_pirate_ship"
const PIRATE_SHIP_GRID_CELLS := 50
const PIRATE_SHIP_COLLISION_KEYWORDS := [
	"Ship_Hull",
	"Main_Deck",
	"Upper_Deck",
	"Poop_Deck",
	"Captain_Deck",
	"Rudder",
	"Keel",
	"Ram",
]
const PIRATE_WATER_UV_SPEED := Vector2(0.010, 0.006)
const PIRATE_WATER_BOB_SPEED := 0.65
const PIRATE_WATER_BOB_AMPLITUDE_CELLS := 0.035
const PIRATE_LANTERN_LIGHT_RANGE_CELLS := 6.0
const PIRATE_LANTERN_LIGHT_ENERGY := 1.8

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
const VIEW_2D_TOGGLE := 510
const VIEW_2D_IMAGE_LOAD := 511
const VIEW_2D_IMAGE_RESIZE := 512
const VIEW_2D_IMAGE_REMOVE := 513
const VIEW_2D_LAYER_MAP := 514
const VIEW_2D_LAYER_GAME := 515
const VIEW_2D_OPACITY_UP := 516
const VIEW_2D_OPACITY_DOWN := 517
const VIEW_2D_LAYER_FOG := 518
const VIEW_2D_FOG_TOGGLE := 519
const VIEW_2D_FOG_RESET := 520

const FOG_PIXELS_PER_CELL := 16.0
const FOG_MAX_TEXTURE_SIDE := 2048
const FOG_MIN_TEXTURE_SIDE := 64
const FOG_DEFAULT_BRUSH_RADIUS_CELLS := 1.25

const SHARE_OPEN := 600

var board_root: Node3D
var ui_root: CanvasLayer
var status_label: Label

var primary_width_cells := 30
var primary_depth_cells := 30
var next_grid_id := 1
var active_element_preset: String = ""

var _pirate_water_root: Node3D = null
var _pirate_water_base_global_y: float = 0.0
var _pirate_water_materials: Array[Dictionary] = []
var _pirate_water_time: float = 0.0

var resize_dialog: ConfirmationDialog
var resize_width: SpinBox
var resize_depth: SpinBox
var _resize_from_preset: bool = false

var map_image_file_dialog: FileDialog
var map_image_size_dialog: ConfirmationDialog
var map_image_width: SpinBox
var map_image_depth: SpinBox
var map_image_node: MeshInstance3D
var map_image_asset_path: String = ""
var map_image_width_cells: float = 0.0
var map_image_depth_cells: float = 0.0
var map_image_opacity: float = 1.0
var map_edit_layer_active: bool = false
var map_transform_panel: Panel
var map_transform_handles: Array[Button] = []
var _map_drag_mode: String = ""
var _map_drag_start_mouse_world: Vector3 = Vector3.ZERO
var _map_drag_start_center: Vector3 = Vector3.ZERO
var _map_drag_start_width_cells: float = 0.0
var _map_drag_start_depth_cells: float = 0.0
var _map_resize_sign := Vector2.ZERO
var _map_resize_opposite_world := Vector3.ZERO

var fog_enabled: bool = false
var fog_edit_layer_active: bool = false
var fog_overlay_node: MeshInstance3D = null
var fog_mask_image: Image = null
var fog_mask_texture: ImageTexture = null
var fog_mask_asset_path: String = ""
var fog_brush_radius_cells: float = FOG_DEFAULT_BRUSH_RADIUS_CELLS
var _fog_painting: bool = false
var _fog_last_world: Vector3 = Vector3.ZERO
const EDITOR_AUTOSAVE_POLL_MS := 450
const EDITOR_AUTOSAVE_DEBOUNCE_MS := 350
var _editor_autosave_ready := false
var _editor_autosave_blocked := false
var _editor_autosave_last_signature := ""
var _editor_autosave_candidate := ""
var _editor_autosave_candidate_since := 0
var _editor_autosave_last_poll := 0
var _editor_autosave_retry_after := 0
var _fog_change_revision := 0

var add_grid_dialog: ConfirmationDialog
var add_x: SpinBox
var add_y: SpinBox
var add_z: SpinBox
var add_width: SpinBox
var add_depth: SpinBox

var leave_dialog: ConfirmationDialog


func _input(event: InputEvent) -> void:
	if not fog_edit_layer_active or not fog_enabled:
		return
	if not bool(board_root.call("is_2d_view_enabled")):
		return

	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null:
		return

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		if event.pressed:
			var world: Vector3 = _screen_to_map_plane(event.position)
			if not world.is_finite() or not _world_inside_primary_grid(world):
				return
			_fog_painting = true
			_fog_last_world = world
			_paint_fog_at_world(world)
		else:
			_fog_painting = false
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _fog_painting:
		var current: Vector3 = _screen_to_map_plane(event.position)
		if not current.is_finite():
			return
		_paint_fog_path(_fog_last_world, current)
		_fog_last_world = current
		get_viewport().set_input_as_handled()


func _ready() -> void:
	board_root = get_parent() as Node3D
	if board_root == null:
		push_error("CampaignEditor: il controller deve essere figlio di DnDBase.")
		return

	# I nodi figli ricevono _ready prima del parent. Rimandiamo quindi
	# l'inizializzazione a quando dnd_base ha creato la griglia volumetrica,
	# BoardSync, token drag e gli altri servizi runtime.
	call_deferred("_initialize_editor")


func _process(delta: float) -> void:
	_poll_editor_autosave()
	_sync_edit_layers_with_2d_view()
	_update_map_transform_overlay()

	if active_element_preset != PIRATE_SHIP_PRESET_ID:
		return
	if _pirate_water_root == null or not is_instance_valid(_pirate_water_root):
		return

	_pirate_water_time += delta
	_pirate_water_root.global_position.y = (
		_pirate_water_base_global_y
		+ sin(_pirate_water_time * PIRATE_WATER_BOB_SPEED)
		* PIRATE_WATER_BOB_AMPLITUDE_CELLS
		* _cell_size()
	)

	for entry: Dictionary in _pirate_water_materials:
		var material := entry.get("material") as StandardMaterial3D
		if material == null or not is_instance_valid(material):
			continue
		var base_offset: Vector3 = entry.get("base_offset", Vector3.ZERO)
		material.uv1_offset = base_offset + Vector3(
			fposmod(
				_pirate_water_time * PIRATE_WATER_UV_SPEED.x,
				1.0
			),
			fposmod(
				_pirate_water_time * PIRATE_WATER_UV_SPEED.y,
				1.0
			),
			0.0
		)


func _initialize_editor() -> void:
	if board_root == null or not is_instance_valid(board_root):
		return

	ui_root = board_root.get_node("UI") as CanvasLayer
	_set_white_environment()
	_resize_primary_grid(primary_width_cells, primary_depth_cells)
	board_root.call("set_grid_visible", true)
	_build_toolbar()
	_build_grid_dialogs()
	_build_2d_image_dialogs()
	_build_map_transform_overlay()
	_build_leave_dialog()

	# L'editor deve essere utilizzabile subito con il mouse. ESC continua a
	# catturare/liberare il cursore tramite la logica gia' presente in dnd_base.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _load_active_campaign()
	_editor_autosave_ready = not _editor_autosave_blocked


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
		["Scenario · Foresta e montagne", PRESET_FOREST_MOUNTAINS],
		["Scenario · The Siren's Light", PRESET_PIRATE_SHIP],
		["Crea griglia…", PRESET_CREATE_GRID]
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

	row.add_child(_make_menu_button("Vista 2D", [
		["Attiva / disattiva vista 2D", VIEW_2D_TOGGLE],
		["Livello · Mappa", VIEW_2D_LAYER_MAP],
		["Livello · Gioco", VIEW_2D_LAYER_GAME],
		["Livello · Ombra di guerra", VIEW_2D_LAYER_FOG],
		["Attiva / disattiva ombra di guerra", VIEW_2D_FOG_TOGGLE],
		["Ripristina ombra completa", VIEW_2D_FOG_RESET],
		["Inserisci immagine sulla griglia…", VIEW_2D_IMAGE_LOAD],
		["Ridimensiona immagine con valori…", VIEW_2D_IMAGE_RESIZE],
		["Aumenta opacità immagine", VIEW_2D_OPACITY_UP],
		["Diminuisci opacità immagine", VIEW_2D_OPACITY_DOWN],
		["Rimuovi immagine", VIEW_2D_IMAGE_REMOVE]
	], _on_2d_view_selected))

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

	var menu_button := Button.new()
	menu_button.text = "Menu"
	menu_button.custom_minimum_size = Vector2(56, 28)
	menu_button.add_theme_font_size_override("font_size", 13)
	menu_button.pressed.connect(
		func() -> void:
			DialogLayout.popup(leave_dialog, Vector2i(470, 190), 0.92)
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
			_clear_element_presets()
			active_element_preset = ""
			_set_orientation_marker_enabled(false)
			_set_base_platform_enabled(true)
			_set_white_environment()
			_set_status("Scenario: vuoto bianco")
		PRESET_EMPTY_ELEMENTS:
			_clear_element_presets()
			active_element_preset = ""
			_set_orientation_marker_enabled(false)
			_set_base_platform_enabled(true)
			_set_status("Preset elementi: nessun elemento")
		PRESET_FOREST_MOUNTAINS:
			_apply_forest_mountains_preset(true)
		PRESET_PIRATE_SHIP:
			_apply_pirate_ship_preset(true)
		PRESET_CREATE_GRID:
			_open_primary_grid_resize_dialog(true)


func _apply_forest_mountains_preset(resize_grid: bool = true) -> void:
	_clear_element_presets()

	# FileAccess is used before load() so a missing optional binary asset does
	# not flood the Godot debugger with ResourceLoader errors.
	if not FileAccess.file_exists(FOREST_MOUNTAINS_PRESET_PATH):
		active_element_preset = ""
		_set_base_platform_enabled(true)
		_set_status(
			"Preset foresta non installato: manca forest_mountains_preset.glb"
		)
		return

	var packed: Resource = load(FOREST_MOUNTAINS_PRESET_PATH)
	if not packed is PackedScene:
		active_element_preset = ""
		_set_base_platform_enabled(true)
		_set_status("Preset foresta non caricabile")
		return

	var instance: Node = (packed as PackedScene).instantiate()
	if not instance is Node3D:
		instance.free()
		active_element_preset = ""
		_set_base_platform_enabled(true)
		_set_status("Preset foresta non e' una scena 3D")
		return

	var root := instance as Node3D
	_set_base_platform_enabled(false)
	_set_orientation_marker_enabled(false)
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


func _apply_pirate_ship_preset(resize_grid: bool = true) -> void:
	_clear_element_presets()

	if not FileAccess.file_exists(PIRATE_SHIP_PRESET_PATH):
		active_element_preset = ""
		_set_base_platform_enabled(true)
		_set_status(
			"Preset nave non installato: manca sirens_light_pirate_ship_preset.glb"
		)
		return

	var packed: Resource = load(PIRATE_SHIP_PRESET_PATH)
	if not packed is PackedScene:
		active_element_preset = ""
		_set_base_platform_enabled(true)
		_set_status("Preset nave non caricabile")
		return

	var instance: Node = (packed as PackedScene).instantiate()
	if not instance is Node3D:
		instance.free()
		active_element_preset = ""
		_set_base_platform_enabled(true)
		_set_status("Preset nave non e' una scena 3D")
		return

	var root := instance as Node3D
	_set_base_platform_enabled(false)
	_set_orientation_marker_enabled(false)
	root.name = "CampaignPreset_SirensLight"
	# The prepared GLB is already normalized so one cannon is 2 grid cells
	# long. Scaling by cell_size only preserves that reference at runtime.
	root.scale = Vector3.ONE * _cell_size()
	root.add_to_group("campaign_preset_element")
	root.set_meta("campaign_preset_id", PIRATE_SHIP_PRESET_ID)
	board_root.add_child(root)

	_build_pirate_ship_collisions(root)
	_configure_pirate_ship_water(root)
	_preserve_pirate_ship_lighting(root)
	active_element_preset = PIRATE_SHIP_PRESET_ID

	if resize_grid:
		_resize_primary_grid(
			PIRATE_SHIP_GRID_CELLS,
			PIRATE_SHIP_GRID_CELLS
		)

	_refresh_volumetric_grid()
	_set_status(
		"Preset: The Siren's Light · cannone lungo 2 celle · griglia 50×50"
	)


func _configure_pirate_ship_water(root: Node3D) -> void:
	_pirate_water_root = null
	_pirate_water_materials.clear()
	_pirate_water_time = 0.0

	var water_parent := root.find_child("Water", true, false) as Node3D
	if water_parent != null:
		_pirate_water_root = water_parent
		_pirate_water_base_global_y = water_parent.global_position.y

	for candidate: Node in root.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	):
		var mesh_instance := candidate as MeshInstance3D
		if (
			mesh_instance == null
			or mesh_instance.mesh == null
			or not String(mesh_instance.name).contains("Water")
		):
			continue

		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.mesh.surface_get_material(surface_index)
			if not source is StandardMaterial3D:
				continue
			var animated := source.duplicate(true) as StandardMaterial3D
			mesh_instance.set_surface_override_material(
				surface_index,
				animated
			)
			_pirate_water_materials.append({
				"material": animated,
				"base_offset": animated.uv1_offset,
			})


func _preserve_pirate_ship_lighting(root: Node3D) -> void:
	var imported_lights := 0
	for candidate: Node in root.find_children("*", "Light3D", true, false):
		var imported_light := candidate as Light3D
		if imported_light == null:
			continue
		imported_light.visible = true
		imported_lights += 1

	# The current GLB carries glowing lantern meshes but no
	# KHR_lights_punctual nodes. Keep their original emissive materials intact
	# and give those lanterns a small warm runtime light instead.
	if imported_lights > 0:
		return

	for candidate: Node in root.find_children(
		"*Lantern*",
		"MeshInstance3D",
		true,
		false
	):
		var lantern := candidate as MeshInstance3D
		if lantern == null or lantern.mesh == null:
			continue
		if lantern.get_node_or_null("PresetLanternLight") != null:
			continue

		var light := OmniLight3D.new()
		light.name = "PresetLanternLight"
		light.light_color = Color(1.0, 0.63, 0.32, 1.0)
		light.light_energy = PIRATE_LANTERN_LIGHT_ENERGY
		light.omni_range = (
			PIRATE_LANTERN_LIGHT_RANGE_CELLS * _cell_size()
		)
		light.shadow_enabled = true
		lantern.add_child(light)
		light.position = lantern.get_aabb().get_center()


func _build_pirate_ship_collisions(root: Node3D) -> void:
	for candidate: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if not _pirate_ship_mesh_needs_collision(mesh_instance):
			continue

		var faces: PackedVector3Array = mesh_instance.mesh.get_faces()
		if faces.is_empty():
			continue

		var body := StaticBody3D.new()
		body.name = "PresetShipCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group("campaign_preset_terrain")
		mesh_instance.add_child(body)

		var collision := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		collision.shape = shape
		body.add_child(collision)


func _pirate_ship_mesh_needs_collision(mesh_instance: MeshInstance3D) -> bool:
	var label := String(mesh_instance.name)
	for keyword: String in PIRATE_SHIP_COLLISION_KEYWORDS:
		if label.contains(keyword):
			return true
	return false


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
	_pirate_water_root = null
	_pirate_water_materials.clear()
	_pirate_water_time = 0.0
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
			_open_primary_grid_resize_dialog(false)
		GRID_ADD:
			DialogLayout.popup(add_grid_dialog, Vector2i(500, 430), 0.92)
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


func _on_2d_view_selected(id: int) -> void:
	match id:
		VIEW_2D_TOGGLE:
			board_root.call("toggle_2d_view")
			# Il cambio 3D/2D è un cambio di vista, non di strumento:
			# si rientra sempre sul livello Gioco. Mappa e Fog vanno scelti
			# esplicitamente per evitare che continuino a intercettare i token.
			_set_map_edit_layer(false)
			_set_fog_edit_layer(false)
			_set_status(
				"Vista 2D attiva"
				if bool(board_root.call("is_2d_view_enabled"))
				else "Vista 3D attiva"
			)
		VIEW_2D_LAYER_MAP:
			board_root.call("set_2d_view_enabled", true)
			_set_map_edit_layer(true)
			_set_status("Livello Mappa · trascina immagine o maniglie")
		VIEW_2D_LAYER_GAME:
			board_root.call("set_2d_view_enabled", true)
			_set_map_edit_layer(false)
			_set_fog_edit_layer(false)
			_set_status("Livello Gioco")
		VIEW_2D_LAYER_FOG:
			board_root.call("set_2d_view_enabled", true)
			if not fog_enabled:
				_set_fog_enabled(true)
			_set_fog_edit_layer(true)
			_set_status("Livello Ombra di guerra · tieni premuto per rivelare")
		VIEW_2D_FOG_TOGGLE:
			_set_fog_enabled(not fog_enabled)
			_set_status(
				"Ombra di guerra attiva"
				if fog_enabled
				else "Ombra di guerra disattivata"
			)
		VIEW_2D_FOG_RESET:
			_reset_fog_mask()
			_set_status("Ombra di guerra ripristinata")
		VIEW_2D_IMAGE_LOAD:
			board_root.call("set_2d_view_enabled", true)
			_set_map_edit_layer(true)
			if map_image_file_dialog != null:
				map_image_file_dialog.reset_size()
				map_image_file_dialog.popup_centered_clamped(
					Vector2i(900, 640),
					0.96
				)
		VIEW_2D_IMAGE_RESIZE:
			if map_image_node == null or not is_instance_valid(map_image_node):
				_set_status("Nessuna immagine 2D da ridimensionare")
				return
			_open_map_image_size_dialog()
		VIEW_2D_OPACITY_UP:
			_adjust_map_image_opacity(0.1)
		VIEW_2D_OPACITY_DOWN:
			_adjust_map_image_opacity(-0.1)
		VIEW_2D_IMAGE_REMOVE:
			_clear_map_image()
			_set_status("Immagine 2D rimossa")


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
			if _resize_from_preset:
				_clear_element_presets()
				active_element_preset = ""
				_set_orientation_marker_enabled(false)
				_set_base_platform_enabled(true)
				_set_white_environment()
			_resize_from_preset = false
			_resize_primary_grid(
				int(resize_width.value),
				int(resize_depth.value)
			)
			_set_status(
				"Griglia principale: %d × %d"
				% [primary_width_cells, primary_depth_cells]
			)
	)
	resize_dialog.canceled.connect(
		func() -> void:
			_resize_from_preset = false
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


func _open_primary_grid_resize_dialog(as_preset: bool) -> void:
	_resize_from_preset = as_preset
	resize_dialog.title = (
		"Crea griglia"
		if as_preset
		else "Dimensioni griglia principale"
	)
	resize_width.value = primary_width_cells
	resize_depth.value = primary_depth_cells
	DialogLayout.popup(resize_dialog, Vector2i(460, 250), 0.92)


func _build_2d_image_dialogs() -> void:
	map_image_file_dialog = FileDialog.new()
	map_image_file_dialog.title = "Inserisci immagine nella griglia"
	map_image_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	map_image_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	map_image_file_dialog.filters = PackedStringArray([
		"*.png,*.jpg,*.jpeg,*.webp ; Immagini",
		"*.png ; PNG",
		"*.jpg,*.jpeg ; JPEG",
		"*.webp ; WebP"
	])
	var pictures_dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if not pictures_dir.is_empty():
		map_image_file_dialog.current_dir = pictures_dir
	ui_root.add_child(map_image_file_dialog)
	map_image_file_dialog.file_selected.connect(_on_map_image_file_selected)

	map_image_size_dialog = ConfirmationDialog.new()
	map_image_size_dialog.title = "Dimensioni immagine 2D"
	map_image_size_dialog.ok_button_text = "Applica"
	map_image_size_dialog.min_size = Vector2i(470, 280)
	ui_root.add_child(map_image_size_dialog)

	var body := _dialog_body(map_image_size_dialog)
	var hint := Label.new()
	hint.text = (
		"Le dimensioni sono espresse in quadretti. "
		+ "L'immagine resta centrata e non può superare i bordi della griglia."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)
	map_image_width = _spin_row(
		body, "Larghezza X", 0.25, primary_width_cells, 0.25, 1.0
	)
	map_image_depth = _spin_row(
		body, "Profondità Z", 0.25, primary_depth_cells, 0.25, 1.0
	)
	map_image_size_dialog.confirmed.connect(
		func() -> void:
			map_image_width_cells = clampf(
				float(map_image_width.value), 0.25, float(primary_width_cells)
			)
			map_image_depth_cells = clampf(
				float(map_image_depth.value), 0.25, float(primary_depth_cells)
			)
			_apply_map_image_geometry()
			_set_status(
				"Immagine 2D: %.2f × %.2f quadretti"
				% [map_image_width_cells, map_image_depth_cells]
			)
	)


func _open_map_image_size_dialog() -> void:
	if map_image_size_dialog == null:
		return
	map_image_width.max_value = float(primary_width_cells)
	map_image_depth.max_value = float(primary_depth_cells)
	map_image_width.value = clampf(
		map_image_width_cells, 0.25, float(primary_width_cells)
	)
	map_image_depth.value = clampf(
		map_image_depth_cells, 0.25, float(primary_depth_cells)
	)
	DialogLayout.popup(map_image_size_dialog, Vector2i(470, 280), 0.92)


func _on_map_image_file_selected(path: String) -> void:
	var image := Image.new()
	var error := image.load(path)
	if error != OK or image.is_empty():
		_set_status("Impossibile caricare l'immagine selezionata")
		return

	var manager := _campaign_manager()
	if manager == null or not manager.has_method(
		"get_active_campaign_asset_directory"
	):
		_set_status("Cartella asset dello scenario non disponibile")
		return
	var asset_directory := String(
		manager.call("get_active_campaign_asset_directory")
	)
	if asset_directory.is_empty():
		_set_status("Salvataggio immagine disponibile solo negli scenari utente")
		return

	var target_path := asset_directory.path_join("map_background.png")
	var save_error := image.save_png(target_path)
	if save_error != OK:
		_set_status("Impossibile salvare l'immagine nello scenario")
		return

	map_image_asset_path = target_path
	_create_map_image_node(image)
	_fit_map_image_to_grid(image)
	map_image_opacity = 1.0
	_apply_map_image_geometry()
	_apply_map_image_opacity()
	board_root.call("set_2d_view_enabled", true)
	_set_map_edit_layer(true)
	_set_status("Immagine caricata · trascina per spostare, usa le maniglie per ridimensionare")


func _create_map_image_node(image: Image) -> void:
	_clear_map_image_node_only()
	var map_geometry := board_root.get_node_or_null(
		"Board/MapGeometry"
	) as Node3D
	if map_geometry == null:
		return

	map_image_node = MeshInstance3D.new()
	map_image_node.name = "CampaignMapImage"
	map_image_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map_image_node.position = Vector3(
		0.0, maxf(0.001, _cell_size() * 0.002), 0.0
	)
	map_geometry.add_child(map_image_node)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# La mappa è lo strato trasparente più basso della Vista 2D.
	material.render_priority = -20
	material.albedo_texture = ImageTexture.create_from_image(image)

	var plane := PlaneMesh.new()
	plane.material = material
	map_image_node.mesh = plane


func _fit_map_image_to_grid(image: Image) -> void:
	var pixel_width := maxf(float(image.get_width()), 1.0)
	var pixel_height := maxf(float(image.get_height()), 1.0)
	var aspect := pixel_width / pixel_height
	var width_cells := float(primary_width_cells)
	var depth_cells := width_cells / aspect
	if depth_cells > float(primary_depth_cells):
		depth_cells = float(primary_depth_cells)
		width_cells = depth_cells * aspect
	map_image_width_cells = clampf(
		width_cells, 0.25, float(primary_width_cells)
	)
	map_image_depth_cells = clampf(
		depth_cells, 0.25, float(primary_depth_cells)
	)


func _apply_map_image_geometry() -> void:
	if map_image_node == null or not is_instance_valid(map_image_node):
		return
	map_image_width_cells = clampf(
		map_image_width_cells, 0.25, float(primary_width_cells)
	)
	map_image_depth_cells = clampf(
		map_image_depth_cells, 0.25, float(primary_depth_cells)
	)
	var plane := map_image_node.mesh as PlaneMesh
	if plane == null:
		return
	plane.size = Vector2(
		map_image_width_cells * _cell_size(),
		map_image_depth_cells * _cell_size()
	)
	map_image_node.position.y = maxf(0.001, _cell_size() * 0.002)
	_clamp_map_image_center_to_grid()


func _map_image_material() -> StandardMaterial3D:
	if map_image_node == null or not is_instance_valid(map_image_node):
		return null
	var plane := map_image_node.mesh as PlaneMesh
	if plane == null:
		return null
	return plane.material as StandardMaterial3D


func _apply_map_image_opacity() -> void:
	map_image_opacity = clampf(map_image_opacity, 0.1, 1.0)
	var material := _map_image_material()
	if material != null:
		material.albedo_color = Color(1.0, 1.0, 1.0, map_image_opacity)


func _adjust_map_image_opacity(delta: float) -> void:
	if map_image_node == null or not is_instance_valid(map_image_node):
		_set_status("Nessuna immagine 2D caricata")
		return
	map_image_opacity = clampf(map_image_opacity + delta, 0.1, 1.0)
	_apply_map_image_opacity()
	_set_status("Opacità immagine: %d%%" % int(round(map_image_opacity * 100.0)))


func _sync_edit_layers_with_2d_view() -> void:
	if board_root == null or not is_instance_valid(board_root):
		return
	if bool(board_root.call("is_2d_view_enabled")):
		return
	if not map_edit_layer_active and not fog_edit_layer_active:
		return
	map_edit_layer_active = false
	fog_edit_layer_active = false
	_fog_painting = false
	_map_drag_mode = ""
	_sync_editor_input_layer()


func _set_map_edit_layer(enabled: bool) -> void:
	map_edit_layer_active = enabled
	if enabled:
		fog_edit_layer_active = false
	_fog_painting = false
	_sync_editor_input_layer()
	_update_map_transform_overlay()


func _set_fog_edit_layer(enabled: bool) -> void:
	fog_edit_layer_active = enabled
	if enabled:
		map_edit_layer_active = false
	_fog_painting = false
	_sync_editor_input_layer()
	_update_map_transform_overlay()


func _sync_editor_input_layer() -> void:
	if board_root != null and board_root.has_method("set_map_edit_layer_active"):
		board_root.call(
			"set_map_edit_layer_active",
			map_edit_layer_active or fog_edit_layer_active
		)


func _build_map_transform_overlay() -> void:
	map_transform_panel = Panel.new()
	map_transform_panel.name = "MapImageTransformOverlay"
	map_transform_panel.visible = false
	map_transform_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	map_transform_panel.z_index = 100
	map_transform_panel.focus_mode = Control.FOCUS_NONE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.45, 0.95, 0.04)
	style.border_color = Color(0.12, 0.58, 1.0, 0.95)
	style.set_border_width_all(2)
	map_transform_panel.add_theme_stylebox_override("panel", style)
	map_transform_panel.gui_input.connect(_on_map_transform_panel_input)
	ui_root.add_child(map_transform_panel)

	for signs: Vector2 in [
		Vector2(-1.0, -1.0),
		Vector2(1.0, -1.0),
		Vector2(-1.0, 1.0),
		Vector2(1.0, 1.0)
	]:
		var handle := Button.new()
		handle.custom_minimum_size = Vector2(14, 14)
		handle.size = Vector2(14, 14)
		handle.focus_mode = Control.FOCUS_NONE
		handle.mouse_filter = Control.MOUSE_FILTER_STOP
		handle.tooltip_text = "Trascina per ridimensionare"
		handle.set_meta("resize_sign", signs)
		handle.gui_input.connect(
			_on_map_resize_handle_input.bind(signs)
		)
		map_transform_panel.add_child(handle)
		map_transform_handles.append(handle)


func _update_map_transform_overlay() -> void:
	if map_transform_panel == null:
		return
	var should_show := (
		map_edit_layer_active
		and bool(board_root.call("is_2d_view_enabled"))
		and map_image_node != null
		and is_instance_valid(map_image_node)
	)
	map_transform_panel.visible = should_show
	if not should_show:
		return

	var camera := board_root.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		map_transform_panel.visible = false
		return

	var half_x := map_image_width_cells * _cell_size() * 0.5
	var half_z := map_image_depth_cells * _cell_size() * 0.5
	var center := map_image_node.global_position
	var screen_points: Array[Vector2] = [
		camera.unproject_position(center + Vector3(-half_x, 0.0, -half_z)),
		camera.unproject_position(center + Vector3(half_x, 0.0, -half_z)),
		camera.unproject_position(center + Vector3(-half_x, 0.0, half_z)),
		camera.unproject_position(center + Vector3(half_x, 0.0, half_z))
	]
	var min_point := screen_points[0]
	var max_point := screen_points[0]
	for point: Vector2 in screen_points:
		min_point = min_point.min(point)
		max_point = max_point.max(point)

	map_transform_panel.position = min_point
	map_transform_panel.size = (max_point - min_point).max(Vector2(24, 24))
	var panel_size := map_transform_panel.size
	for handle: Button in map_transform_handles:
		var signs: Vector2 = handle.get_meta(
			"resize_sign",
			Vector2.ONE
		)
		handle.position = Vector2(
			-7.0 if signs.x < 0.0 else panel_size.x - 7.0,
			-7.0 if signs.y < 0.0 else panel_size.y - 7.0
		)


func _on_map_transform_panel_input(event: InputEvent) -> void:
	if not map_edit_layer_active:
		return
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		if event.pressed:
			var world: Vector3 = _screen_to_map_plane(
				get_viewport().get_mouse_position()
			)
			if not world.is_finite():
				return
			_map_drag_mode = "move"
			_map_drag_start_mouse_world = world
			_map_drag_start_center = map_image_node.position
		else:
			_map_drag_mode = ""
		_set_status("Posizione immagine aggiornata")
		get_viewport().set_input_as_handled()
		return

	if (
		event is InputEventMouseMotion
		and _map_drag_mode == "move"
	):
		var current: Vector3 = _screen_to_map_plane(
			get_viewport().get_mouse_position()
		)
		if not current.is_finite():
			return
		var delta_world: Vector3 = current - _map_drag_start_mouse_world
		map_image_node.position.x = _map_drag_start_center.x + delta_world.x
		map_image_node.position.z = _map_drag_start_center.z + delta_world.z
		_clamp_map_image_center_to_grid()
		get_viewport().set_input_as_handled()


func _on_map_resize_handle_input(
	event: InputEvent,
	signs: Vector2
) -> void:
	if not map_edit_layer_active:
		return
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		if event.pressed:
			var world: Vector3 = _screen_to_map_plane(
				get_viewport().get_mouse_position()
			)
			if not world.is_finite():
				return
			_map_drag_mode = "resize"
			_map_resize_sign = signs
			_map_drag_start_center = map_image_node.position
			_map_drag_start_width_cells = map_image_width_cells
			_map_drag_start_depth_cells = map_image_depth_cells
			var half_x := map_image_width_cells * _cell_size() * 0.5
			var half_z := map_image_depth_cells * _cell_size() * 0.5
			_map_resize_opposite_world = Vector3(
				map_image_node.position.x - signs.x * half_x,
				0.0,
				map_image_node.position.z - signs.y * half_z
			)
		else:
			_map_drag_mode = ""
			_set_status(
				"Dimensioni immagine: %.2f × %.2f quadretti"
				% [map_image_width_cells, map_image_depth_cells]
			)
		get_viewport().set_input_as_handled()
		return

	if (
		event is InputEventMouseMotion
		and _map_drag_mode == "resize"
		and signs == _map_resize_sign
	):
		var current: Vector3 = _screen_to_map_plane(
			get_viewport().get_mouse_position()
		)
		if not current.is_finite():
			return
		_resize_map_image_to_world_corner(current, signs)
		get_viewport().set_input_as_handled()


func _screen_to_map_plane(screen_position: Vector2) -> Vector3:
	var invalid_point := Vector3(INF, INF, INF)
	var camera := board_root.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return invalid_point
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.000001:
		return invalid_point
	var t: float = -origin.y / direction.y
	if t < 0.0:
		return invalid_point
	return origin + direction * t


func _resize_map_image_to_world_corner(
	current_world: Vector3,
	signs: Vector2
) -> void:
	var cell := _cell_size()
	var half_grid_x := primary_width_cells * cell * 0.5
	var half_grid_z := primary_depth_cells * cell * 0.5
	var min_world_size := 0.25 * cell

	var corner_x := clampf(current_world.x, -half_grid_x, half_grid_x)
	var corner_z := clampf(current_world.z, -half_grid_z, half_grid_z)
	var opposite_x := _map_resize_opposite_world.x
	var opposite_z := _map_resize_opposite_world.z

	if signs.x > 0.0:
		corner_x = maxf(corner_x, opposite_x + min_world_size)
	else:
		corner_x = minf(corner_x, opposite_x - min_world_size)
	if signs.y > 0.0:
		corner_z = maxf(corner_z, opposite_z + min_world_size)
	else:
		corner_z = minf(corner_z, opposite_z - min_world_size)

	map_image_width_cells = clampf(
		absf(corner_x - opposite_x) / cell,
		0.25,
		float(primary_width_cells)
	)
	map_image_depth_cells = clampf(
		absf(corner_z - opposite_z) / cell,
		0.25,
		float(primary_depth_cells)
	)
	map_image_node.position.x = (corner_x + opposite_x) * 0.5
	map_image_node.position.z = (corner_z + opposite_z) * 0.5
	_apply_map_image_geometry()


func _clamp_map_image_center_to_grid() -> void:
	if map_image_node == null or not is_instance_valid(map_image_node):
		return
	var cell := _cell_size()
	var half_grid_x := primary_width_cells * cell * 0.5
	var half_grid_z := primary_depth_cells * cell * 0.5
	var half_image_x := map_image_width_cells * cell * 0.5
	var half_image_z := map_image_depth_cells * cell * 0.5
	map_image_node.position.x = clampf(
		map_image_node.position.x,
		-half_grid_x + half_image_x,
		half_grid_x - half_image_x
	)
	map_image_node.position.z = clampf(
		map_image_node.position.z,
		-half_grid_z + half_image_z,
		half_grid_z - half_image_z
	)




func _set_fog_enabled(enabled: bool) -> void:
	fog_enabled = enabled
	if fog_enabled:
		_ensure_fog_mask()
		_ensure_fog_overlay()
	elif fog_edit_layer_active:
		_set_fog_edit_layer(false)
	if fog_overlay_node != null and is_instance_valid(fog_overlay_node):
		fog_overlay_node.visible = fog_enabled


func _fog_texture_size() -> Vector2i:
	var longest_cells: float = maxf(
		float(primary_width_cells),
		float(primary_depth_cells)
	)
	var pixels_per_cell: float = minf(
		FOG_PIXELS_PER_CELL,
		float(FOG_MAX_TEXTURE_SIDE) / maxf(longest_cells, 1.0)
	)
	var width: int = maxi(
		FOG_MIN_TEXTURE_SIDE,
		int(round(float(primary_width_cells) * pixels_per_cell))
	)
	var height: int = maxi(
		FOG_MIN_TEXTURE_SIDE,
		int(round(float(primary_depth_cells) * pixels_per_cell))
	)
	return Vector2i(
		mini(width, FOG_MAX_TEXTURE_SIDE),
		mini(height, FOG_MAX_TEXTURE_SIDE)
	)


func _ensure_fog_mask() -> void:
	var target_size: Vector2i = _fog_texture_size()
	if fog_mask_image == null or fog_mask_image.is_empty():
		fog_mask_image = Image.create(
			target_size.x,
			target_size.y,
			false,
			Image.FORMAT_RGBA8
		)
		fog_mask_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	elif (
		fog_mask_image.get_width() != target_size.x
		or fog_mask_image.get_height() != target_size.y
	):
		fog_mask_image.resize(
			target_size.x,
			target_size.y,
			Image.INTERPOLATE_BILINEAR
		)

	if (
		fog_mask_texture == null
		or fog_mask_texture.get_width() != fog_mask_image.get_width()
		or fog_mask_texture.get_height() != fog_mask_image.get_height()
	):
		fog_mask_texture = ImageTexture.create_from_image(fog_mask_image)
	else:
		fog_mask_texture.update(fog_mask_image)


func _ensure_fog_overlay() -> void:
	_ensure_fog_mask()
	var map_geometry := board_root.get_node_or_null(
		"Board/MapGeometry"
	) as Node3D
	if map_geometry == null:
		return

	if fog_overlay_node == null or not is_instance_valid(fog_overlay_node):
		fog_overlay_node = MeshInstance3D.new()
		fog_overlay_node.name = "CampaignFogOfWar"
		fog_overlay_node.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		map_geometry.add_child(fog_overlay_node)

		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Il fog sta sopra la mappa, ma sotto la griglia-overlay.
		material.render_priority = -10
		material.albedo_color = Color.BLACK
		material.albedo_texture = fog_mask_texture

		var plane := PlaneMesh.new()
		plane.material = material
		fog_overlay_node.mesh = plane
	else:
		var material := _fog_material()
		if material != null:
			material.albedo_texture = fog_mask_texture

	_apply_fog_overlay_geometry()
	fog_overlay_node.visible = fog_enabled


func _fog_material() -> StandardMaterial3D:
	if fog_overlay_node == null or not is_instance_valid(fog_overlay_node):
		return null
	var plane := fog_overlay_node.mesh as PlaneMesh
	if plane == null:
		return null
	return plane.material as StandardMaterial3D


func _apply_fog_overlay_geometry() -> void:
	if fog_overlay_node == null or not is_instance_valid(fog_overlay_node):
		return
	var plane := fog_overlay_node.mesh as PlaneMesh
	if plane == null:
		return
	plane.size = Vector2(
		float(primary_width_cells) * _cell_size(),
		float(primary_depth_cells) * _cell_size()
	)
	# Immagine mappa: 0.002 celle. Fog: 0.008 celle. La griglia 2D
	# riceve un bias di 0.025 celle, quindi resta sempre sopra il velo.
	fog_overlay_node.position = Vector3(
		0.0,
		maxf(0.002, _cell_size() * 0.008),
		0.0
	)


func _reset_fog_mask() -> void:
	_ensure_fog_mask()
	if fog_mask_image == null:
		return
	fog_mask_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	_fog_change_revision += 1
	_update_fog_texture()
	if fog_enabled:
		_ensure_fog_overlay()


func _update_fog_texture() -> void:
	if fog_mask_image == null or fog_mask_image.is_empty():
		return
	if (
		fog_mask_texture == null
		or fog_mask_texture.get_width() != fog_mask_image.get_width()
		or fog_mask_texture.get_height() != fog_mask_image.get_height()
	):
		fog_mask_texture = ImageTexture.create_from_image(fog_mask_image)
	else:
		fog_mask_texture.update(fog_mask_image)
	var material := _fog_material()
	if material != null:
		material.albedo_texture = fog_mask_texture


func _world_inside_primary_grid(world: Vector3) -> bool:
	var half_x: float = float(primary_width_cells) * _cell_size() * 0.5
	var half_z: float = float(primary_depth_cells) * _cell_size() * 0.5
	return (
		world.x >= -half_x
		and world.x <= half_x
		and world.z >= -half_z
		and world.z <= half_z
	)


func _paint_fog_path(from_world: Vector3, to_world: Vector3) -> void:
	var distance: float = from_world.distance_to(to_world)
	var spacing: float = maxf(
		_cell_size() * fog_brush_radius_cells * 0.35,
		_cell_size() * 0.12
	)
	var steps: int = maxi(1, int(ceil(distance / spacing)))
	for index: int in range(1, steps + 1):
		var t: float = float(index) / float(steps)
		var point: Vector3 = from_world.lerp(to_world, t)
		if _world_inside_primary_grid(point):
			_paint_fog_at_world(point, false)
	_update_fog_texture()


func _paint_fog_at_world(
	world: Vector3,
	update_texture: bool = true
) -> void:
	_ensure_fog_mask()
	if fog_mask_image == null or fog_mask_image.is_empty():
		return

	var world_width: float = float(primary_width_cells) * _cell_size()
	var world_depth: float = float(primary_depth_cells) * _cell_size()
	var u: float = clampf(world.x / world_width + 0.5, 0.0, 1.0)
	var v: float = clampf(world.z / world_depth + 0.5, 0.0, 1.0)
	var center_x: int = int(round(u * float(fog_mask_image.get_width() - 1)))
	var center_y: int = int(round(v * float(fog_mask_image.get_height() - 1)))

	var radius_x: int = maxi(
		1,
		int(round(
			fog_brush_radius_cells
			* float(fog_mask_image.get_width())
			/ float(primary_width_cells)
		))
	)
	var radius_y: int = maxi(
		1,
		int(round(
			fog_brush_radius_cells
			* float(fog_mask_image.get_height())
			/ float(primary_depth_cells)
		))
	)

	var min_x: int = maxi(0, center_x - radius_x)
	var max_x: int = mini(fog_mask_image.get_width() - 1, center_x + radius_x)
	var min_y: int = maxi(0, center_y - radius_y)
	var max_y: int = mini(fog_mask_image.get_height() - 1, center_y + radius_y)

	for py: int in range(min_y, max_y + 1):
		for px: int in range(min_x, max_x + 1):
			var dx: float = float(px - center_x) / float(radius_x)
			var dy: float = float(py - center_y) / float(radius_y)
			if dx * dx + dy * dy <= 1.0:
				fog_mask_image.set_pixel(
					px,
					py,
					Color(0.0, 0.0, 0.0, 0.0)
				)
	_fog_change_revision += 1

	if update_texture:
		_update_fog_texture()


func _save_fog_mask_asset() -> void:
	if fog_mask_image == null or fog_mask_image.is_empty():
		return
	var manager := _campaign_manager()
	if manager == null or not manager.has_method(
		"get_active_campaign_asset_directory"
	):
		return
	var asset_directory: String = String(
		manager.call("get_active_campaign_asset_directory")
	)
	if asset_directory.is_empty():
		return
	fog_mask_asset_path = asset_directory.path_join("fog_of_war.png")
	fog_mask_image.save_png(fog_mask_asset_path)


func _serialize_fog() -> Dictionary:
	return {
		"enabled": fog_enabled,
		"file": fog_mask_asset_path.get_file(),
		"brush_radius_cells": fog_brush_radius_cells
	}


func _apply_fog_state(value: Variant) -> void:
	fog_enabled = false
	fog_edit_layer_active = false
	_fog_painting = false
	if fog_overlay_node != null and is_instance_valid(fog_overlay_node):
		fog_overlay_node.free()
	fog_overlay_node = null
	fog_mask_texture = null
	fog_mask_image = null
	fog_mask_asset_path = ""

	if not value is Dictionary:
		return
	var data: Dictionary = value as Dictionary
	fog_enabled = bool(data.get("enabled", false))
	fog_brush_radius_cells = clampf(
		float(data.get(
			"brush_radius_cells",
			FOG_DEFAULT_BRUSH_RADIUS_CELLS
		)),
		0.25,
		10.0
	)

	var file_name: String = String(data.get("file", "")).get_file()
	if not file_name.is_empty():
		var manager := _campaign_manager()
		if manager != null and manager.has_method(
			"get_active_campaign_asset_directory"
		):
			var asset_directory: String = String(
				manager.call("get_active_campaign_asset_directory")
			)
			var image_path: String = asset_directory.path_join(file_name)
			if FileAccess.file_exists(image_path):
				var loaded: Image = Image.new()
				if loaded.load(image_path) == OK and not loaded.is_empty():
					fog_mask_image = loaded
					fog_mask_asset_path = image_path

	if fog_enabled:
		_ensure_fog_mask()
		_ensure_fog_overlay()


func _clear_map_image_node_only() -> void:
	if map_image_node != null and is_instance_valid(map_image_node):
		map_image_node.free()
	map_image_node = null


func _clear_map_image() -> void:
	_clear_map_image_node_only()
	map_image_asset_path = ""
	map_image_width_cells = 0.0
	map_image_depth_cells = 0.0
	map_image_opacity = 1.0
	_map_drag_mode = ""


func _serialize_map_image() -> Dictionary:
	if (
		map_image_node == null
		or not is_instance_valid(map_image_node)
		or map_image_asset_path.is_empty()
	):
		return {}
	return {
		"file": map_image_asset_path.get_file(),
		"width_cells": map_image_width_cells,
		"depth_cells": map_image_depth_cells,
		"center_x": map_image_node.position.x,
		"center_z": map_image_node.position.z,
		"opacity": map_image_opacity
	}


func _apply_map_image_state(value: Variant) -> void:
	_clear_map_image()
	if not value is Dictionary:
		return
	var data := value as Dictionary
	var file_name := String(data.get("file", "")).get_file()
	if file_name.is_empty():
		return

	var manager := _campaign_manager()
	if manager == null or not manager.has_method(
		"get_active_campaign_asset_directory"
	):
		return
	var asset_directory := String(
		manager.call("get_active_campaign_asset_directory")
	)
	if asset_directory.is_empty():
		return

	var image_path := asset_directory.path_join(file_name)
	if not FileAccess.file_exists(image_path):
		return
	var image := Image.new()
	if image.load(image_path) != OK or image.is_empty():
		return

	map_image_asset_path = image_path
	_create_map_image_node(image)
	map_image_width_cells = clampf(
		float(data.get("width_cells", primary_width_cells)),
		0.25,
		float(primary_width_cells)
	)
	map_image_depth_cells = clampf(
		float(data.get("depth_cells", primary_depth_cells)),
		0.25,
		float(primary_depth_cells)
	)
	map_image_node.position.x = float(data.get("center_x", 0.0))
	map_image_node.position.z = float(data.get("center_z", 0.0))
	map_image_opacity = clampf(float(data.get("opacity", 1.0)), 0.1, 1.0)
	_apply_map_image_geometry()
	_apply_map_image_opacity()


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

	if map_image_node != null and is_instance_valid(map_image_node):
		map_image_width_cells = minf(
			map_image_width_cells, float(primary_width_cells)
		)
		map_image_depth_cells = minf(
			map_image_depth_cells, float(primary_depth_cells)
		)
		_apply_map_image_geometry()

	if fog_mask_image != null and not fog_mask_image.is_empty():
		_ensure_fog_mask()
	if fog_overlay_node != null and is_instance_valid(fog_overlay_node):
		_apply_fog_overlay_geometry()

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


# The complete editor save includes image/fog/grids absent from tactical
# network snapshots. Debounce the same live changes without a Save button.
func _editor_state() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"primary_grid": {
			"width": primary_width_cells,
			"depth": primary_depth_cells
		},
		"extra_grids": _serialize_extra_grids(),
		"element_preset": active_element_preset,
		"map_image": _serialize_map_image(),
		"fog_of_war": _serialize_fog(),
		"view": _serialize_view_state(),
		"board_snapshot": _create_board_snapshot()
	}


func _poll_editor_autosave() -> void:
	if not _editor_autosave_ready or not _is_active_user_campaign():
		return
	var now := Time.get_ticks_msec()
	if now < _editor_autosave_retry_after or now - _editor_autosave_last_poll < EDITOR_AUTOSAVE_POLL_MS:
		return
	_editor_autosave_last_poll = now
	var state := _editor_state()
	# The encounter controller can temporarily refuse snapshots mid-turn.
	# Never replace a valid campaign save with a partial board state.
	if (state.get("board_snapshot", {}) as Dictionary).is_empty():
		return
	var signature := JSON.stringify({
		"state": state, "fog_revision": _fog_change_revision
	}).sha256_text()
	if signature == _editor_autosave_last_signature:
		_editor_autosave_candidate = ""
		return
	if signature != _editor_autosave_candidate:
		_editor_autosave_candidate = signature
		_editor_autosave_candidate_since = now
		return
	if now - _editor_autosave_candidate_since < EDITOR_AUTOSAVE_DEBOUNCE_MS:
		return
	var error := _save_campaign()
	if error == OK:
		_editor_autosave_last_signature = signature
		_editor_autosave_candidate = ""
		_editor_autosave_retry_after = 0
	else:
		_editor_autosave_retry_after = now + 2000
		push_warning("Autosave campagna non riuscito: " + error_string(error))


func _save_campaign() -> Error:
	if not _is_active_user_campaign():
		return ERR_UNAVAILABLE
	var state := _editor_state()
	if (state.get("board_snapshot", {}) as Dictionary).is_empty():
		return ERR_BUSY
	_save_fog_mask_asset()
	var error: Error = int(_campaign_manager().call("save_active_state", state))
	if error != OK:
		_set_status("Errore salvataggio: %s" % error_string(error))
	return error


func _load_active_campaign() -> void:
	if not _is_active_user_campaign():
		_set_status("Editor aperto senza una campagna utente attiva")
		return

	var state: Dictionary = _load_active_state()
	if state.is_empty():
		var manager := _campaign_manager()
		var saved_path := "user://campaigns".path_join(
			String(manager.get("active_campaign_id"))
		).path_join("state.json")
		if FileAccess.file_exists(saved_path):
			_editor_autosave_blocked = true
			_set_status("Salvataggio campagna illeggibile: conservato senza sovrascriverlo.")
			return
		var initial_preset: String = _initial_element_preset()
		if initial_preset == FOREST_MOUNTAINS_PRESET_ID:
			active_element_preset = initial_preset
			_apply_forest_mountains_preset(true)
		elif initial_preset == PIRATE_SHIP_PRESET_ID:
			active_element_preset = initial_preset
			_apply_pirate_ship_preset(true)
		else:
			active_element_preset = ""
			_set_orientation_marker_enabled(false)
			_set_base_platform_enabled(true)
			_set_status("%s · nuovo salvataggio" % _campaign_name())
		return
	if int(state.get("version", -1)) != SAVE_VERSION:
		_editor_autosave_blocked = true
		_set_status("Versione salvataggio non supportata: file preservato.")
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
	elif active_element_preset == PIRATE_SHIP_PRESET_ID:
		_apply_pirate_ship_preset(false)
	else:
		_set_orientation_marker_enabled(false)
		_set_base_platform_enabled(true)

	_apply_map_image_state(state.get("map_image", {}))
	_apply_fog_state(state.get("fog_of_war", {}))
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
		"top_down_2d": bool(board_root.call("is_2d_view_enabled")),
		"map_edit_layer": map_edit_layer_active,
		"fog_edit_layer": fog_edit_layer_active,
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
	board_root.call(
		"set_2d_view_enabled",
		bool(data.get("top_down_2d", false))
	)
	var top_down_2d: bool = bool(data.get("top_down_2d", false))
	var restore_fog_layer: bool = (
		bool(data.get("fog_edit_layer", false))
		and top_down_2d
	)
	if restore_fog_layer:
		_set_fog_edit_layer(true)
	else:
		_set_map_edit_layer(
			bool(data.get("map_edit_layer", false))
			and top_down_2d
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


func _set_orientation_marker_enabled(enabled: bool) -> void:
	var marker := board_root.get_node_or_null(
		"Board/MapGeometry/OrientationMarker"
	) as StaticBody3D
	if marker == null:
		return
	marker.visible = enabled
	marker.collision_layer = 1 if enabled else 0
	marker.collision_mask = 1 if enabled else 0
	_refresh_volumetric_grid()


func _set_base_platform_enabled(enabled: bool) -> void:
	var floor := board_root.get_node_or_null(
		"Board/FloorCollision"
	) as StaticBody3D
	if floor == null:
		return

	# The collision layer changes immediately so the volumetric grid stops
	# seeing the white base plane in the same frame. The shape itself is
	# disabled deferred to stay safe around physics callbacks.
	floor.collision_layer = 1 if enabled else 0
	var collision := floor.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D
	if collision != null:
		collision.set_deferred("disabled", not enabled)

	var visual := floor.get_node_or_null(
		"CampaignPlatformVisual"
	) as MeshInstance3D
	if visual != null:
		visual.visible = enabled

	_refresh_volumetric_grid()


func _initial_element_preset() -> String:
	var manager := _campaign_manager()
	if (
		manager == null
		or not manager.has_method("get_active_campaign_initial_preset")
	):
		return ""
	return String(
		manager.call("get_active_campaign_initial_preset")
	).strip_edges()


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
