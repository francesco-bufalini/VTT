extends Node

signal interaction_changed(active: bool)
var board: Node3D
var active: bool = false
var _tokens: Array[CharacterBody3D] = []
var _origins: Array[Vector3] = []
var _targets: Array[Vector3] = []
var _anchor: Vector3
var _valid: bool = false
var _was_captured: bool = false
var _preview: MultiMeshInstance3D
var _material: StandardMaterial3D
var _support: Node3D
var _press_position: Vector2
var _moved: bool = false
var _anchor_token: CharacterBody3D
var _undo_state: Dictionary = {}

func setup(owner_board: Node3D) -> void:
	board = owner_board
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = _material
	_preview = MultiMeshInstance3D.new()
	_preview.multimesh = MultiMesh.new()
	_preview.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_preview.multimesh.mesh = box
	board.add_child(_preview)
	_preview.visible = false

func handle_event(event: InputEvent) -> bool:
	if active:
		if event is InputEventMouseMotion:
			if event.position.distance_to(_press_position) > 4:
				_moved = true
			update_preview(event.position)
			return true
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			finish(false)
			return true
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			finish(_moved and _valid)
			return true
		return event is InputEventKey or event is InputEventMouseButton
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT or event.ctrl_pressed:
		return false
	if board._ui_owns_mouse or board.color_dialog.visible or board.measurement_tool.is_measurement_mode():
		return false
	var point: Vector2 = (
		board._screen_center()
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		else event.position
	)
	# Il drag deve partire dal token, non dal primo collider 3D incontrato.
	# È essenziale sulle mappe multiquota (es. Siren's Light), dove una vista
	# zenitale può attraversare ponti e sovrastrutture prima della miniatura.
	var hit: Dictionary = {}
	if bool(board.call("is_2d_view_enabled")):
		hit = board._raycast_token_from_screen(point, true)
	else:
		hit = board._raycast_from_screen(point, 0xFFFFFFFF, true)
	if hit.is_empty():
		return false
	var target: Node = board._find_interaction_target(hit.collider)
	if (
		target == null
		or not target.is_in_group("dnd_token")
		or not (target is CharacterBody3D)
		or not target.has_method("snap_destination")
		or not target.has_method("get_footprint_extent")
	):
		return false
	var target_token: CharacterBody3D = target as CharacterBody3D
	if not board._selected_tokens.has(target_token):
		board._interact_or_select_under_mouse(point, event.shift_pressed, false)
	begin(board._selected_tokens, target_token)
	_press_position = point
	if _was_captured:
		board.get_viewport().warp_mouse(point)
	return true

func begin(tokens: Array[CharacterBody3D], anchor_token: CharacterBody3D) -> void:
	_tokens = tokens.duplicate()
	_undo_state = {}
	if board != null and board.has_method("begin_token_move_transaction"):
		var history_value: Variant = board.call(
			"begin_token_move_transaction",
			_tokens
		)
		if history_value is Dictionary:
			_undo_state = (history_value as Dictionary).duplicate(true)
	_origins.clear()
	for token in _tokens:
		_origins.append(token.global_position)
		token.set_physics_process(false)
	_anchor = anchor_token.global_position
	_anchor_token = anchor_token
	_support = anchor_token.grid_support
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	active = true
	_valid = false
	_moved = false
	interaction_changed.emit(true)

func update_preview(screen_point: Vector2) -> void:
	var origin: Vector3 = board.camera.project_ray_origin(screen_point)
	var direction: Vector3 = board.camera.project_ray_normal(screen_point)
	var hit: Dictionary = board._raycast_from_screen(screen_point, 1 | 4, false)
	if not hit.is_empty():
		for token in _tokens:
			if token.is_ancestor_of(hit.collider):
				hit = {}
				break
	var position: Variant
	var support: Node3D = _support
	var tactical_support: Node3D = null
	var hit_normal := Vector3.ZERO
	if not hit.is_empty():
		hit_normal = Vector3(hit.normal)
		if hit.collider is Node3D and hit.collider.is_in_group("tactical_platform"):
			tactical_support = hit.collider as Node3D

	# Flying tokens normally stay on their current Y plane, but a deliberate
	# drag onto a tactical surface should rest on that surface without
	# requiring "Applica gravità". This is what makes the giant bodies and
	# sphere usable as terrain while keeping free-air placement intact.
	if (
		_anchor_token.flying
		and tactical_support != null
		and hit_normal.dot(Vector3.UP) > 0.35
	):
		position = (
			Vector3(hit.position)
			+ Vector3.UP * _token_half_height(_anchor_token)
		)
		support = tactical_support
	elif _anchor_token.flying:
		position = Plane(Vector3.UP, _anchor.y).intersects_ray(
			origin,
			direction
		)
	elif not hit.is_empty() and hit_normal.dot(Vector3.UP) > 0.7:
		position = (
			Vector3(hit.position)
			+ Vector3.UP * _token_half_height(_anchor_token)
		)
		support = tactical_support
	else:
		position = Plane(Vector3.UP, _anchor.y).intersects_ray(
			origin,
			direction
		)
	if position == null:
		_valid = false
		return
	preview_at(position, support)

func preview_at(position: Vector3, support: Node3D = null) -> bool:
	for token in _tokens:
		if is_instance_valid(support) and token.is_ancestor_of(support):
			return false
	_targets.clear()
	_valid = true
	var delta := position - _anchor
	for index in range(_tokens.size()):
		var token := _tokens[index]
		var target: Vector3 = token.snap_destination(_origins[index] + delta, support)
		_targets.append(target)
		if token.movement_validator.is_valid() and not token.movement_validator.call(token, target):
			_valid = false
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = token.collision_shape.shape
		query.transform = Transform3D(token.global_basis, target + Vector3.UP * 0.025)
		query.collision_mask = token.collision_mask
		query.exclude = token.get_movement_exclusions()
		if not board.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			_valid = false
	_material.albedo_color = Color(0.18,0.8,0.68,0.38) if _valid else Color(0.95,0.16,0.1,0.45)
	_preview.multimesh.instance_count = _targets.size()
	for index in range(_targets.size()):
		var token := _tokens[index]
		var extent: Vector2 = token.get_footprint_extent()
		var center: Vector3 = _targets[index] - Vector3.UP * (_token_half_height(token) - 0.04)
		_preview.multimesh.set_instance_transform(index, Transform3D(token.global_basis.scaled_local(Vector3(extent.x, 0.07, extent.y)),center))
	_preview.visible = true
	_support = support
	return _valid

func _token_half_height(token: CharacterBody3D) -> float:
	if token == null or not is_instance_valid(token):
		return board.cell_size * 0.5
	var height_cells: Variant = token.get("token_height_cells")
	if height_cells is float or height_cells is int:
		return maxf(float(height_cells), 0.01) * board.cell_size * 0.5
	return board.cell_size * 0.5


func finish(commit: bool) -> void:
	var committed_move: bool = commit and _valid and _moved
	var moved_tokens: Array[CharacterBody3D] = _tokens.duplicate()
	var movement_origins: Array[Vector3] = _origins.duplicate()
	for index in range(_tokens.size()):
		var token := _tokens[index]
		if not is_instance_valid(token):
			continue
		if committed_move:
			token.global_position = _targets[index]
			if token.has_method("snap_horizontal_to_grid"):
				token.call("snap_horizontal_to_grid")
			# Il supporto del carro/piattaforma e' indipendente dalla gravita.
			token.grid_support = _support
			if is_instance_valid(token.grid_support):
				token._support_transform = token.grid_support.global_transform
			token.velocity = Vector3.ZERO
		token.set_physics_process(true)
	_tokens.clear()
	if committed_move and board.item_controller != null:
		board.item_controller.flush_motion(moved_tokens)
	_preview.visible = false
	active = false
	if (
		committed_move
		and not _undo_state.is_empty()
		and board.has_method("commit_undo_transaction")
	):
		board.call("commit_undo_transaction", _undo_state)
	_undo_state = {}
	if _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	interaction_changed.emit(false)
	if (
		committed_move
		and board != null
		and board.has_method("check_opportunity_attacks_after_movement")
	):
		board.call_deferred(
			"check_opportunity_attacks_after_movement",
			moved_tokens,
			movement_origins
		)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and active:
		finish(false)
