extends Node3D
## Self-contained 3D chess table; moves are validated by chess_rules.gd.
## The pieces are generic 3D tokens, not tactical VTT creatures.

const ChessRules = preload("res://vtt/chess/chess_rules.gd")
const SCENARIO_LIST := "res://vtt/menu/campaign_scenarios.tscn"
const NO_SQUARE := Vector2i(-1, -1)
const TILE_SIDE := 1.0

var game = ChessRules.new()
var _tiles: Array[MeshInstance3D] = []
var _piece_root: Node3D
var _piece_nodes: Dictionary = {}
var _transform_option_buttons: Dictionary = {}
var _selected := NO_SQUARE
var _destinations: Array[Dictionary] = []
var _promotion_from := NO_SQUARE
var _promotion_to := NO_SQUARE
var _status_label: Label
var _help_label: Label
var _promotion_box: VBoxContainer
var _undo_button: Button
var _transform_box: VBoxContainer
var _transform_buttons: HFlowContainer
var _transform_summary: Label
var _transform_kind := ""
var _power_mode := ""
var _power_kind := ""
var _power_buttons: Dictionary = {}
var _revive_buttons: Dictionary = {}
var _power_summary: Label
var _promotion_is_power := false
var _wall_white: StandardMaterial3D
var _wall_black: StandardMaterial3D
var _curse_tile: StandardMaterial3D
var _camera: Camera3D

var _light_tile: StandardMaterial3D
var _dark_tile: StandardMaterial3D
var _selected_tile: StandardMaterial3D
var _legal_tile: StandardMaterial3D
var _checked_tile: StandardMaterial3D
var _transform_tile: StandardMaterial3D


func _ready() -> void:
	_camera = $Camera3D as Camera3D
	_camera.position = Vector3(0, 12.5, 10.5)
	_camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	_camera.current = true
	_build_lighting()
	_build_table()
	_build_interface()
	var manager := get_node_or_null("/root/CampaignManager")
	if manager != null:
		var state: Variant = manager.call("load_active_runtime_state")
		if state is Dictionary:
			var stored: Variant = state.get("wizard_chess", {})
			if stored is Dictionary:
				game.restore_state(stored)
	_refresh()


func _build_lighting() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.075, 0.075, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.66, 0.7, 0.87)
	environment.ambient_light_energy = 0.7
	world.environment = environment
	add_child(world)


func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = 0.38
	return result


func _mesh(parent: Node3D, primitive: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = primitive
	visual.material_override = material
	visual.position = at
	parent.add_child(visual)
	return visual


func _build_table() -> void:
	_light_tile = _material(Color(0.82, 0.78, 0.66))
	_dark_tile = _material(Color(0.23, 0.27, 0.4))
	_selected_tile = _material(Color(0.97, 0.70, 0.20))
	_legal_tile = _material(Color(0.30, 0.65, 0.45))
	_checked_tile = _material(Color(0.84, 0.20, 0.21))
	_transform_tile = _material(Color(0.36, 0.66, 0.91))
	_wall_white = _material(Color(0.32, 0.56, 0.87))
	_wall_black = _material(Color(0.68, 0.33, 0.77))
	_curse_tile = _material(Color(0.73, 0.16, 0.45))
	var wood := _material(Color(0.12, 0.09, 0.14), 0.18)
	var board_root := Node3D.new()
	board_root.name = "ChessTable"
	add_child(board_root)
	var frame := BoxMesh.new()
	frame.size = Vector3(8.75, 0.32, 8.75)
	_mesh(board_root, frame, wood, Vector3(0, -0.19, 0))
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(0.99, 0.12, 0.99)
	for rank in range(8):
		for file in range(8):
			var pos := Vector3(float(file) - 3.5, 0.03, float(rank) - 3.5)
			_tiles.append(_mesh(board_root, tile_mesh,
				_light_tile if (file + rank) % 2 == 0 else _dark_tile, pos))
	_piece_root = Node3D.new()
	_piece_root.name = "ChessTokens"
	add_child(_piece_root)
	var coord_color := Color(0.91, 0.81, 0.58)
	for index in range(8):
		_coordinate_label(board_root, char(65 + index), Vector3(float(index) - 3.5, 0.04, 4.28), coord_color)
		_coordinate_label(board_root, str(8 - index), Vector3(-4.25, 0.04, float(index) - 3.5), coord_color)


func _coordinate_label(parent: Node3D, caption: String, at: Vector3, color: Color) -> void:
	var marker := Label3D.new()
	marker.text = caption
	marker.position = at
	marker.font_size = 52
	marker.pixel_size = 0.005
	marker.modulate = color
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(marker)


func _make_piece(code: String, cell: Vector2i) -> void:
	var side := code.substr(0, 1)
	var kind := code.substr(1, 1)
	var token := Node3D.new()
	token.name = ("Bianco" if side == "w" else "Nero") + "_" + kind
	token.position = Vector3(float(cell.x) - 3.5, 0.15, float(cell.y) - 3.5)
	token.set_meta("chess_piece", code)
	token.set_meta("chess_square", cell)
	token.set_meta("royal", game.is_royal(cell))
	token.set_meta("cursed", game.is_cursed(cell))
	_piece_root.add_child(token)
	_piece_nodes[cell.y * 8 + cell.x] = token
	var pale := side == "w"
	var main_color := Color(0.94, 0.91, 0.80) if pale else Color(0.18, 0.16, 0.26)
	var edge_color := Color(0.68, 0.48, 0.17) if pale else Color(0.45, 0.34, 0.66)
	var body := _material(main_color, 0.15)
	var trim := _material(edge_color, 0.45)
	var footing := CylinderMesh.new()
	footing.top_radius = 0.36
	footing.bottom_radius = 0.40
	footing.height = 0.18
	_mesh(token, footing, trim, Vector3(0, 0.04, 0))
	var crown := CylinderMesh.new()
	crown.top_radius = 0.26 if kind == "P" else 0.31
	crown.bottom_radius = 0.31
	crown.height = 0.31 if kind == "P" else 0.48
	var height := crown.height
	_mesh(token, crown, body, Vector3(0, 0.13 + height / 2.0, 0))
	var cap := SphereMesh.new()
	cap.radius = 0.13 if kind == "P" else 0.19
	cap.height = cap.radius * 2.0
	_mesh(token, cap, trim, Vector3(0, 0.13 + height + 0.08, 0))
	var symbol := Label3D.new()
	symbol.text = kind + (" ★" if game.is_royal(cell) and kind == "Q" else "") + (" ✖" if game.is_cursed(cell) else "")
	symbol.font_size = 90
	symbol.pixel_size = 0.0045
	symbol.modulate = Color(0.16, 0.12, 0.10) if pale else Color(1.0, 0.93, 0.76)
	symbol.outline_modulate = Color(0.06, 0.05, 0.09)
	symbol.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	symbol.no_depth_test = true
	symbol.position = Vector3(0, 0.74, 0)
	token.add_child(symbol)


func _build_interface() -> void:
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(screen)
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -370.0
	panel.offset_right = -16.0
	panel.offset_top = 16.0
	panel.offset_bottom = 730.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(key, 18)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 13)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "SCACCHI DEI MAGHI"
	heading.add_theme_font_size_override("font_size", 24)
	column.add_child(heading)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 19)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)
	_help_label = Label.new()
	_help_label.text = "Seleziona un token, poi una casella evidenziata.\nK Re · Q Regina · R Torre\nB Alfiere · N Cavallo · P Pedone"
	_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_help_label)
	var power_panel := VBoxContainer.new()
	power_panel.add_theme_constant_override("separation", 6)
	column.add_child(power_panel)
	var power_title := Label.new()
	power_title.text = "POTERI DEI PEZZI"
	power_title.add_theme_font_size_override("font_size", 19)
	power_panel.add_child(power_title)
	_power_summary = Label.new()
	_power_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	power_panel.add_child(_power_summary)
	var power_actions := HFlowContainer.new()
	power_panel.add_child(power_actions)
	for entry in [
		["dash", "Scatto · Pedone"], ["sweep", "Travolgi · Cavallo"],
		["wall_rank", "Muro orizzontale"], ["wall_file", "Muro verticale"],
		["revive", "Resuscita · Alfiere"], ["curse", "Maledici · Alfiere"],
		["coup", "Regina sovrana"]
	]:
		var button := Button.new()
		button.text = entry[1]
		button.pressed.connect(_activate_power.bind(entry[0]))
		_power_buttons[entry[0]] = button
		power_actions.add_child(button)
	var revival_actions := HFlowContainer.new()
	power_panel.add_child(revival_actions)
	for kind in ["Q", "R", "B", "N", "P", "K"]:
		var button := Button.new()
		button.text = "Riporta " + kind
		button.pressed.connect(_choose_revival.bind(kind))
		_revive_buttons[kind] = button
		revival_actions.add_child(button)
	var cancel_power := Button.new()
	cancel_power.name = "CancelPower"
	cancel_power.text = "Annulla potere"
	cancel_power.pressed.connect(_cancel_power)
	power_panel.add_child(cancel_power)
	_power_buttons["cancel"] = cancel_power
	_transform_box = VBoxContainer.new()
	column.add_child(_transform_box)
	var transform_title := Label.new()
	transform_title.text = "MAGIA: TRASFORMA UN PEZZO"
	_transform_box.add_child(transform_title)
	_transform_summary = Label.new()
	_transform_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_transform_box.add_child(_transform_summary)
	_transform_buttons = HFlowContainer.new()
	_transform_box.add_child(_transform_buttons)
	# Fixed buttons: never delete a Button while its pressed callback is running.
	for kind in ["Q", "R", "B", "N", "P"]:
		var option := Button.new()
		option.tooltip_text = "Trasforma un tuo pezzo (non il Re) in " + kind
		option.pressed.connect(_set_transform_kind.bind(kind))
		_transform_option_buttons[kind] = option
		_transform_buttons.add_child(option)
	var cancel_transform := Button.new()
	cancel_transform.text = "Annulla selezione trasformazione"
	cancel_transform.pressed.connect(_cancel_transformation)
	_transform_box.add_child(cancel_transform)
	cancel_transform.name = "CancelTransform"
	_promotion_box = VBoxContainer.new()
	_promotion_box.visible = false
	column.add_child(_promotion_box)
	var promotion_title := Label.new()
	promotion_title.text = "Promuovi il pedone:"
	_promotion_box.add_child(promotion_title)
	var options := HBoxContainer.new()
	_promotion_box.add_child(options)
	for entry in [["Q", "Regina"], ["R", "Torre"], ["B", "Alfiere"], ["N", "Cavallo"]]:
		var button := Button.new()
		button.text = entry[1]
		button.tooltip_text = "Promozione a " + entry[1]
		button.pressed.connect(_promote.bind(entry[0]))
		options.add_child(button)
	_undo_button = Button.new()
	_undo_button.text = "Annulla ultima azione"
	_undo_button.pressed.connect(_undo)
	column.add_child(_undo_button)
	var reset_button := Button.new()
	reset_button.text = "Nuova partita"
	reset_button.pressed.connect(_reset)
	column.add_child(reset_button)
	var back_button := Button.new()
	back_button.text = "Torna agli scenari"
	back_button.pressed.connect(_back_to_scenarios)
	column.add_child(back_button)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _promotion_box.visible:
			return
		var from_ray := _camera.project_ray_origin(event.position)
		var direction := _camera.project_ray_normal(event.position)
		if absf(direction.y) < 0.0001:
			return
		var distance := (0.1 - from_ray.y) / direction.y
		if distance < 0.0:
			return
		var position := from_ray + direction * distance
		var cell := Vector2i(floori(position.x + 4.0), floori(position.z + 4.0))
		if ChessRules.inside(cell):
			_select_cell(cell)
			get_viewport().set_input_as_handled()


func _select_cell(cell: Vector2i) -> void:
	if game.finished:
		return
	if _transform_kind != "":
		if game.transform(cell, _transform_kind):
			_transform_kind = ""
			_selected = NO_SQUARE
			_destinations.clear()
			_save()
		_refresh()
		return
	if _power_mode != "":
		if _selected != NO_SQUARE:
			var worked := false
			match _power_mode:
				"dash", "sweep":
					for candidate in _destinations:
						if candidate["to"] == cell:
							if bool(candidate.get("promotion", false)):
								_promotion_from = _selected
								_promotion_to = cell
								_promotion_is_power = true
								_promotion_box.visible = true
								return
							worked = game.play_power(_selected, cell)
							break
				"revive":
					worked = game.revive(_selected, cell, _power_kind)
				"curse":
					worked = game.curse(_selected, cell)
			if worked:
				_finish_action()
			else:
				_refresh()
		return
	if _selected != NO_SQUARE:
		for move in _destinations:
			if move["to"] == cell:
				if bool(move.get("promotion", false)):
					_promotion_from = _selected
					_promotion_to = cell
					_promotion_box.visible = true
					_help_label.text = "Scegli il pezzo in cui promuovere il pedone."
					return
				_play_move(_selected, cell)
				return
	if game.piece(cell).begins_with(game.turn):
		_selected = cell
		_destinations = game.legal_moves(cell)
	elif game.piece(cell).ends_with("Q") and not bool(game.coup_used[game.piece(cell).substr(0, 1)]):
		# Queen's coup can be activated even during the opponent's turn.
		_selected = cell
		_destinations.clear()
	else:
		_selected = NO_SQUARE
		_destinations.clear()
	_refresh()


func _activate_power(power: String) -> void:
	if game.finished or _selected == NO_SQUARE:
		return
	match power:
		"wall_rank", "wall_file":
			if game.activate_wall(_selected, "rank" if power == "wall_rank" else "file"):
				_finish_action()
		"coup":
			if game.queen_coup(_selected):
				_finish_action()
		"dash", "sweep":
			var code: String = game.piece(_selected)
			if code.begins_with(game.turn):
				_power_mode = power
				_destinations.clear()
				for move in game.power_moves(_selected):
					if move["power"] == power:
						_destinations.append(move)
		"revive":
			if game.can_revive(_selected):
				_power_mode = "revive_choose"
				_destinations.clear()
		"curse":
			if game.can_curse(_selected):
				_power_mode = "curse"
				_destinations.clear()
	_refresh()


func _choose_revival(kind: String) -> void:
	if _power_mode != "revive_choose" or kind not in game.available_revivals(_selected):
		return
	_power_mode = "revive"
	_power_kind = kind
	_refresh()


func _cancel_power() -> void:
	_power_mode = ""
	_power_kind = ""
	_destinations.clear()
	if _selected != NO_SQUARE and game.piece(_selected).begins_with(game.turn):
		_destinations = game.legal_moves(_selected)
	_refresh()


func _finish_action() -> void:
	_power_mode = ""
	_power_kind = ""
	_transform_kind = ""
	_selected = NO_SQUARE
	_destinations.clear()
	_promotion_is_power = false
	_promotion_box.visible = false
	_save()
	_refresh()


func _set_transform_kind(kind: String) -> void:
	if _promotion_box.visible or kind not in game.available_transformations():
		return
	_transform_kind = kind
	_power_mode = ""
	_selected = NO_SQUARE
	_destinations.clear()
	_refresh()


func _cancel_transformation() -> void:
	_transform_kind = ""
	_refresh()


func _reserve_description(side: String) -> String:
	var parts: Array[String] = []
	for kind in ["Q", "R", "B", "N", "P", "K"]:
		var count: int = game.captured_pieces[side].count(kind)
		if count:
			parts.append("%s×%d" % [kind, count])
	return ", ".join(parts) if not parts.is_empty() else "nessuno"


func _promote(kind: String) -> void:
	if _promotion_from != NO_SQUARE and _promotion_to != NO_SQUARE:
		if _promotion_is_power:
			if game.play_power(_promotion_from, _promotion_to, kind):
				_finish_action()
		else:
			_play_move(_promotion_from, _promotion_to, kind)
	_promotion_from = NO_SQUARE
	_promotion_to = NO_SQUARE
	_promotion_box.visible = false


func _play_move(from: Vector2i, to: Vector2i, promotion: String = "Q") -> void:
	if not game.play(from, to, promotion):
		return
	_finish_action()


func _reset() -> void:
	game.reset()
	_transform_kind = ""
	_power_mode = ""
	_power_kind = ""
	_promotion_is_power = false
	_selected = NO_SQUARE
	_destinations.clear()
	_promotion_from = NO_SQUARE
	_promotion_to = NO_SQUARE
	_promotion_box.visible = false
	_save()
	_refresh()


func _undo() -> void:
	if game.undo():
		_transform_kind = ""
		_power_mode = ""
		_power_kind = ""
		_selected = NO_SQUARE
		_destinations.clear()
		_promotion_from = NO_SQUARE
		_promotion_to = NO_SQUARE
		_promotion_box.visible = false
		_save()
		_refresh()


func _save() -> void:
	var manager := get_node_or_null("/root/CampaignManager")
	if manager != null:
		var error: Error = manager.call("save_active_runtime_state", {"wizard_chess": game.export_state()})
		if error != OK:
			push_warning("Scacchi dei Maghi: salvataggio non riuscito: " + error_string(error))


func _back_to_scenarios() -> void:
	get_tree().change_scene_to_file(SCENARIO_LIST)


func _refresh() -> void:
	var legal_targets: Dictionary = {}
	for move in _destinations:
		legal_targets[move["to"]] = true
	var checked_king: Vector2i = game.king_square(game.turn) if game.in_check(game.turn) else NO_SQUARE
	for rank in range(8):
		for file in range(8):
			var cell := Vector2i(file, rank)
			var tile: MeshInstance3D = _tiles[rank * 8 + file]
			var material: Material = _light_tile if (file + rank) % 2 == 0 else _dark_tile
			var barriers: Array[String] = game.wall_at(cell)
			if "w" in barriers:
				material = _wall_white
			if "b" in barriers:
				material = _wall_black
			if game.is_cursed(cell):
				material = _curse_tile
			if _power_mode == "revive" and cell != _selected and ChessRules.inside(_selected) and game.piece(cell) == ".":
				if maxi(absi(cell.x - _selected.x), absi(cell.y - _selected.y)) == 1 and not ChessRules._wall_blocks(game.walls, game.turn, _selected, cell):
					material = _legal_tile
			if _power_mode == "curse" and game.piece(cell).begins_with(ChessRules.opposite(game.turn)) and not game.is_royal(cell):
				material = _legal_tile
			if cell == checked_king:
				material = _checked_tile
			if _transform_kind != "" and game.piece(cell).begins_with(game.turn) and not game.is_royal(cell) and not game.is_cursed(cell):
				material = _transform_tile
			if legal_targets.has(cell):
				material = _legal_tile
			if cell == _selected:
				material = _selected_tile
			tile.material_override = material
	# Refresh only changed token meshes. Regenerating all 32 tokens and
	# their materials/labels on every click caused long GPU stalls.
	for rank in range(8):
		for file in range(8):
			var cell := Vector2i(file, rank)
			var index := rank * 8 + file
			var code: String = game.piece(cell)
			var existing: Node3D = _piece_nodes.get(index)
			if existing != null and is_instance_valid(existing):
				if String(existing.get_meta("chess_piece")) == code and bool(existing.get_meta("royal")) == game.is_royal(cell) and bool(existing.get_meta("cursed")) == game.is_cursed(cell):
					continue
				existing.free()
			_piece_nodes.erase(index)
			if code != ".":
				_make_piece(code, cell)
	_status_label.text = game.status + "\nMossa %d" % game.fullmove_number
	if game.transformed_this_turn and not game.finished:
		_status_label.text += "\nTrasformazione usata: completa la mossa."
	for side in game.active_transforms:
		var record: Dictionary = game.active_transforms[side]
		_status_label.text += "\n%s: %s temporaneo (torna %s al prossimo turno)." % [
			"Bianchi" if side == "w" else "Neri",
			game.piece(ChessRules._transform_square(record)).substr(1, 1),
			String(record["original"])
		]
	for side in ["w", "b"]:
		if bool(game.coup_used[side]):
			_status_label.text += "\nLa Regina %s è il Re ★." % ("bianca" if side == "w" else "nera")
	if not game.walls.is_empty():
		_status_label.text += "\nMuri magici attivi: %d" % game.walls.size()
	_undo_button.disabled = game.history.is_empty()
	var at := _selected
	var active_code: String = game.piece(at) if at != NO_SQUARE else "."
	var side: String = active_code.substr(0, 1) if active_code != "." else ""
	var belongs := side == game.turn
	var uid := game.piece_id(at)
	var kind: String = active_code.substr(1, 1) if active_code != "." else ""
	_power_buttons["dash"].visible = belongs and kind == "P" and not game._used(uid, "dash") and not game.power_moves(at).is_empty()
	_power_buttons["sweep"].visible = belongs and kind == "N" and not game._used(uid, "sweep") and not game.power_moves(at).is_empty()
	_power_buttons["wall_rank"].visible = belongs and kind == "R" and not game._used(uid, "wall")
	_power_buttons["wall_file"].visible = belongs and kind == "R" and not game._used(uid, "wall")
	_power_buttons["revive"].visible = belongs and game.can_revive(at) and not game.available_revivals(at).is_empty()
	_power_buttons["curse"].visible = belongs and game.can_curse(at)
	_power_buttons["coup"].visible = kind == "Q" and not bool(game.coup_used.get(side, true)) and not game.is_royal(at)
	for key in ["dash", "sweep", "wall_rank", "wall_file", "revive", "curse", "coup"]:
		_power_buttons[key].disabled = game.finished or _promotion_box.visible
	_power_buttons["cancel"].visible = _power_mode != ""
	for key in _revive_buttons:
		var revive_button: Button = _revive_buttons[key]
		revive_button.visible = _power_mode == "revive_choose" and key in game.available_revivals(_selected)
	_power_summary.text = "Seleziona un pezzo per vedere i poteri rimasti."
	if active_code != ".":
		_power_summary.text = "Pezzo: %s %s · %s" % [
			"Bianco" if side == "w" else "Nero", kind,
			"potere disponibile" if not game._data(uid).get("used", []).size() else "poteri già usati: " + ", ".join(game._data(uid).get("used", []))
		]
	if _power_mode != "":
		_power_summary.text += "\nPotere selezionato: %s" % _power_mode
	_transform_summary.text = "Bianchi persi: %s\nNeri persi: %s" % [
		_reserve_description("w"), _reserve_description("b")
	]
	var available := game.available_transformations()
	for name in _transform_option_buttons:
		var button: Button = _transform_option_buttons[name]
		button.visible = name in available
		button.text = "%s ×%d" % [name, game.captured_pieces[game.turn].count(name)]
		button.disabled = _promotion_box.visible
	var cancel_button := _transform_box.get_node("CancelTransform") as Button
	cancel_button.visible = _transform_kind != ""
	_transform_box.visible = not game.finished
	if not _promotion_box.visible:
		if _power_mode != "":
			_help_label.text = ("Scegli il pezzo da resuscitare." if _power_mode == "revive_choose" else "Clicca una casella verde per attivare il potere; usa Annulla potere per tornare alle mosse normali.")
		elif game.finished:
			_help_label.text = "Partita conclusa. Premi Nuova partita per ricominciare."
		elif _transform_kind != "":
			_help_label.text = "Clicca un tuo pezzo azzurro (non il Re) per trasformarlo in %s. Poi esegui la normale mossa." % _transform_kind
		elif game.available_transformations().is_empty():
			_help_label.text = "Seleziona un token, poi una casella verde.\nK Re · Q Regina · R Torre · B Alfiere · N Cavallo · P Pedone"
		else:
			_help_label.text = "Puoi trasformare un tuo pezzo fino al prossimo turno (una volta per turno), poi muovere. Oppure muovi subito."
