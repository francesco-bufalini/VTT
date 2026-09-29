extends "res://dnd_base.gd"

const CONTEXT_ADVANCE := 100
const CONTEXT_SHOULDERS := 101
const CONTEXT_BOARD := 102
const CONTEXT_OVERVIEW := 103
@onready var encounter: Node = $EncounterProgressController

func _ready() -> void:
	super._ready()
	$Scenery.build(self)
	encounter.seals = preload("res://encounter/seal_controller.gd").new()
	encounter.seals.name = "SealController"
	add_child(encounter.seals)
	encounter.seals.setup($KlothisRoot/KlothisVisual, measurement_tool.meters_to_world(1))
	encounter.seals.changed.connect(func(): encounter.state_changed.emit())
	$KaosRoot/ShoulderPlatform.setup(measurement_tool)
	measurement_tool.collision_mask = 1 | 4
	var hand_grids = preload("res://encounter/hand_platforms.gd").new()
	hand_grids.name = "HandPlatforms"
	add_child(hand_grids)
	hand_grids.setup(self)
	$KaosRoot.configure_positions($KaosPositions, measurement_tool)
	$EnvironmentCollapseController.setup(cell_size)
	encounter.setup($HazardController, $KaosRoot, $EnvironmentCollapseController, $HazardAllowedArea, cell_size)
	$UI/EncounterUI.setup(encounter)
	tokens_root.child_entered_tree.connect(_configure_encounter_token)
	encounter.state_changed.connect(_refresh_encounter_menu)
	encounter.state_changed.connect(_sync_end_state)
	for token in tokens_root.get_children():
		_configure_encounter_token(token)
	token_drag.interaction_changed.connect(_set_grid_interaction)

func _sync_end_state() -> void:
	for token in tokens_root.get_children():
		token.set_physics_process(not encounter.encounter_finished)
	if encounter.encounter_finished:
		context_menu.hide()

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(encounter) and encounter.encounter_finished:
		return
	super._unhandled_input(event)

func _on_token_dialog_confirmed() -> void:
	if not encounter.encounter_finished:
		super._on_token_dialog_confirmed()

func _set_grid_interaction(active: bool) -> void:
	var strength := 1.0 if active or not _selected_tokens.is_empty() else 0.55
	if surface_grid != null and is_instance_valid(surface_grid):
		surface_grid.set_interaction_strength(strength)

func _replace_selection(token: CharacterBody3D) -> void:
	super._replace_selection(token)
	if is_node_ready():
		_set_grid_interaction(false)

func _clear_selection() -> void:
	super._clear_selection()
	if is_node_ready():
		_set_grid_interaction(false)

func _configure_encounter_token(token: Node) -> void:
	if token is CharacterBody3D and token.has_method("nudge_grid"):
		token.movement_validator = $HazardController.can_move_token
		token.collision_mask = 1 | 4

func _show_context_menu(screen_position: Vector2) -> void:
	super._show_context_menu(screen_position)
	context_menu.add_separator()
	context_menu.add_item("Avanza", CONTEXT_ADVANCE)
	context_menu.add_separator()
	context_menu.add_item("Inquadra spalle di Kaos", CONTEXT_SHOULDERS)
	context_menu.add_item("Inquadra battlemap", CONTEXT_BOARD)
	context_menu.add_item("Vista generale", CONTEXT_OVERVIEW)
	_refresh_encounter_menu()

func _refresh_encounter_menu() -> void:
	var index := context_menu.get_item_index(CONTEXT_ADVANCE)
	if index >= 0:
		context_menu.set_item_disabled(index, encounter.is_advancing or encounter.encounter_finished)

func _on_context_menu_id_pressed(id: int) -> void:
	if encounter.encounter_finished:
		return
	if id in [CONTEXT_SHOULDERS, CONTEXT_BOARD, CONTEXT_OVERVIEW]:
		camera.exit_first_person()
		var target: Vector3
		if id == CONTEXT_SHOULDERS:
			target = $KaosRoot/ShoulderPlatform.global_position
			camera.position = target + Vector3(-18, 25, -24)
		elif id == CONTEXT_BOARD:
			target = Vector3(0, 0, measurement_tool.meters_to_world(85.5))
			camera.position = target + Vector3(35, 55, 60)
		else:
			target = Vector3(0, 225, -65) * measurement_tool.meters_to_world(1)
			camera.position = Vector3(260, 290, 510) * measurement_tool.meters_to_world(1)
		camera.look_at(target)
		_close_context_menu_to_game()
		return
	if id == CONTEXT_ADVANCE:
		_close_context_menu_to_game()
		encounter.advance_encounter()
	else:
		super._on_context_menu_id_pressed(id)
