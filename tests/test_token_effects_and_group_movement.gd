extends SceneTree

const TokenScene = preload("res://token.tscn")


func _initialize() -> void:
	call_deferred("run")


func _spawn(board: Node3D, display_name: String, position: Vector3) -> CharacterBody3D:
	var token: CharacterBody3D = TokenScene.instantiate()
	# Keep the regression independent of the user's private creature archive.
	token.set_meta("creature_owner_id", "regression-foreign-owner")
	token.set_meta("creature_id", display_name)
	board.tokens_root.add_child(token)
	token.set_display_name(display_name)
	token.global_position = position
	token.set_flying(true)
	return token


func run() -> void:
	var board: Node3D = load("res://dnd_base.tscn").instantiate()
	root.add_child(board)
	await process_frame
	await process_frame
	var leader := _spawn(board, "Capogruppo", Vector3(30.5, 12.0, 30.5))
	var follower := _spawn(board, "Alleato di un altro giocatore", Vector3(33.5, 12.0, 30.5))
	var unrelated := _spawn(board, "Estraneo", Vector3(40.5, 12.0, 30.5))
	var links: Node = board.mount_controller
	assert(links.mount(follower, leader))
	assert(links.get_motion_tokens([leader]).size() == 2)
	assert(links.get_motion_tokens([leader, follower]).size() == 2)
	await physics_frame
	await physics_frame

	# A selected leader cannot drag an unselected follower inside a wall.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	shape.shape = box
	wall.add_child(shape)
	board.add_child(wall)
	wall.global_position = follower.global_position + Vector3.RIGHT
	await physics_frame
	await physics_frame
	var drag: Node = board.token_drag
	var dragged_tokens: Array[CharacterBody3D] = [leader]
	drag.begin(dragged_tokens, leader)
	assert(drag._tokens.has(follower), "Drag preview must include unselected companions")
	assert(not drag.preview_at(leader.global_position + Vector3.RIGHT),
		"A wall under the follower must invalidate the entire formation preview")
	drag.finish(false)
	var leader_origin: Vector3 = leader.global_position
	var follower_origin: Vector3 = follower.global_position
	board._selected_tokens.assign([leader])
	board._move_selected(Vector2i.RIGHT)
	assert(leader.global_position.is_equal_approx(leader_origin)
		and follower.global_position.is_equal_approx(follower_origin),
		"A blocked companion must stop a keyboard move without splitting the formation")
	wall.queue_free()
	await physics_frame
	await physics_frame

	# Tactical validators also apply to followers, horizontally and vertically.
	follower.movement_validator = func(_token: CharacterBody3D, _destination: Vector3) -> bool: return false
	board._move_selected(Vector2i.RIGHT)
	board._move_selected_vertical(1)
	assert(leader.global_position.is_equal_approx(leader_origin))
	assert(follower.global_position.is_equal_approx(follower_origin))
	follower.movement_validator = Callable()

	# Moving from the follower carries the whole formation exactly once.
	board._selected_tokens.assign([follower, leader])
	board._move_selected(Vector2i.RIGHT)
	assert(leader.global_position.is_equal_approx(leader_origin + Vector3.RIGHT))
	assert(follower.global_position.is_equal_approx(follower_origin + Vector3.RIGHT))
	assert(unrelated.global_position.is_equal_approx(Vector3(40.5, 12.0, 30.5)))
	assert(board.undo_last_action())
	assert(leader.global_position.is_equal_approx(leader_origin))
	assert(follower.global_position.is_equal_approx(follower_origin))
	assert(board.redo_last_action())
	assert(leader.global_position.is_equal_approx(leader_origin + Vector3.RIGHT))

	# Commit and undo the actual drag, initiated on an unselected follower.
	leader_origin = leader.global_position
	follower_origin = follower.global_position
	dragged_tokens.assign([follower])
	drag.begin(dragged_tokens, follower)
	assert(drag.preview_at(follower_origin + Vector3.FORWARD))
	drag._moved = true
	drag.finish(true)
	assert(leader.global_position.is_equal_approx(leader_origin + Vector3.FORWARD))
	assert(follower.global_position.is_equal_approx(follower_origin + Vector3.FORWARD))
	assert(board.undo_last_action())
	assert(leader.global_position.is_equal_approx(leader_origin))
	assert(follower.global_position.is_equal_approx(follower_origin))

	# The leader can end the link through the real context action, with undo.
	board._selected_tokens.assign([leader])
	board._on_context_menu_id_pressed(board.CONTEXT_STOP_MOVING_TOGETHER)
	assert(not links.is_mounted(follower))
	assert(not follower.get_collision_exceptions().has(leader))
	assert(board.undo_last_action())
	links.refresh_all()
	assert(links.is_mounted(follower))

	# Use the real dialog signal on a foreign token, showing its display name.
	board._open_token_conditions_dialog(follower)
	var dialog: ConfirmationDialog = board._context_effect_dialog
	assert(follower.get_display_name() in dialog.title)
	assert(not dialog.get_cancel_button().visible,
		"Live changes must not offer an ineffective Cancel button")
	var search: LineEdit = dialog.find_child("ConditionSearch", true, false)
	var checks: Array[Node] = dialog.find_children("*", "CheckButton", true, false)
	var condition: CheckButton
	for check: CheckButton in checks:
		if "blinded" in check.text.to_lower() or "accecato" in check.text.to_lower():
			condition = check
	assert(condition != null)
	search.text = condition.text
	search.text_changed.emit(search.text)
	assert(condition.visible)
	assert(checks.any(func(check: Node) -> bool: return not check.visible))
	var history_size: int = board._undo_stack.size()
	condition.button_pressed = true
	assert(follower.has_condition("blinded"))
	assert(not leader.has_condition("blinded") and not unrelated.has_condition("blinded"))
	assert(board._undo_stack.size() == history_size + 1)
	dialog.hide()
	assert(board.undo_last_action())
	assert(not follower.has_condition("blinded"))
	assert(board.redo_last_action())
	assert(follower.has_condition("blinded"))

	# Effect addition/removal are reversible and duplicate additions are no-ops.
	board._on_token_active_spell_added(follower, "bless")
	assert("bless" in follower.get_active_spell_ids())
	history_size = board._undo_stack.size()
	board._on_token_active_spell_added(follower, "bless")
	assert(board._undo_stack.size() == history_size)
	assert(board.undo_last_action())
	assert(not "bless" in follower.get_active_spell_ids())
	assert(board.redo_last_action())
	assert("bless" in follower.get_active_spell_ids())
	board._on_token_active_spell_removed(follower, "bless", null)
	assert(not "bless" in follower.get_active_spell_ids())
	assert(board.undo_last_action())
	assert("bless" in follower.get_active_spell_ids())
	assert(leader.get_active_spell_ids().is_empty() and unrelated.get_active_spell_ids().is_empty())
	board._open_token_active_spells_dialog(follower)
	dialog = board._context_effect_dialog
	search = dialog.find_child("ActiveSpellSearch", true, false)
	var picker: OptionButton = dialog.find_child("ActiveSpellPicker", true, false)
	search.text = "shield of faith"
	search.text_changed.emit(search.text)
	assert(picker.item_count > 0)
	assert("·" in picker.get_item_text(0), "Spell choices must identify their source")
	var picked_spell: String = String(picker.get_selected_metadata())
	dialog.confirmed.emit()
	dialog.hide()
	assert(picked_spell in follower.get_active_spell_ids())
	assert(board.undo_last_action())
	assert(not picked_spell in follower.get_active_spell_ids())

	# Opportunity notices include unselected followers carried by the group.
	follower.global_position = leader.global_position + Vector3(3, 0, 3)
	assert(links.mount(follower, leader))
	var enemy := _spawn(board, "Nemico", follower.global_position - Vector3(2, 0, 0))
	enemy.set_party_id("enemy")
	var before_distance: float = board._tactical_distance_to_position_feet(enemy, follower, follower.global_position)
	var after_distance: float = board._tactical_distance_to_position_feet(enemy, follower, follower.global_position + Vector3.RIGHT)
	assert(after_distance > before_distance)
	enemy.set_reach_feet((before_distance + after_distance) * 0.5, true)
	board._selected_tokens.assign([leader])
	board.opportunity_label.text = ""
	await physics_frame
	await physics_frame
	board._move_selected(Vector2i.RIGHT)
	assert(follower.get_display_name() in board.opportunity_label.text,
		"Opportunity attacks must consider all companions, including unselected ones")

	# Mixed footprints use one snapped pivot delta in both preview and commit.
	links.dismount(follower)
	follower.set_size_category("Large", 2.0)
	assert(links.mount(follower, leader))
	leader_origin = leader.global_position
	follower_origin = follower.global_position
	var destination := follower_origin + Vector3(0.3, 5.0, 1.2)
	var translation: Vector3 = follower.snap_destination(destination) - follower_origin
	dragged_tokens.assign([leader, follower])
	drag.begin(dragged_tokens, follower)
	assert(drag.preview_at(destination))
	assert(drag._targets[drag._tokens.find(leader)].is_equal_approx(leader_origin + translation))
	assert(drag._targets[drag._tokens.find(follower)].is_equal_approx(follower_origin + translation))
	drag._moved = true
	drag.finish(true)
	assert(leader.global_position.is_equal_approx(leader_origin + translation))
	assert(follower.global_position.is_equal_approx(follower_origin + translation))
	board.queue_free()
	await process_frame
	print("PASS: foreign token effects, searchable dialog, undo/redo, group drag and nudge collisions, leader detachment")
	quit()
