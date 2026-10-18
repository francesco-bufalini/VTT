extends SceneTree

# Undo/redo must cover implicit map edits as well as explicit transactions.
# Runs headlessly: no user:// automatic save is read or overwritten.
func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var board: Node3D = load("res://dnd_base.tscn").instantiate()
	root.add_child(board)
	await process_frame
	await process_frame
	var sync: Node = board.board_sync
	sync.set_auto_sync_enabled(false)
	sync.listen(false, "map-history-regression")

	var token: CharacterBody3D = load("res://token.tscn").instantiate()
	board.tokens_root.add_child(token)
	token.set_display_name("Original")
	token.set_flying(true)
	token.global_position = Vector3(10.5, 8.0, 10.5)
	var initial: Dictionary = sync.create_snapshot()
	assert(not initial.is_empty(), "A valid initial snapshot is required")
	board._reset_map_history_baseline(initial)
	assert(board._undo_stack.is_empty() and board._redo_stack.is_empty())

	# Ctrl+Z should also work immediately, before any disk debounce fires.
	token.set_condition("stunned", true)
	assert(board.undo_last_action(),
		"Unsaved implicit token edits must be undoable without waiting for disk")
	assert(not token.has_condition("stunned"))
	assert(board.redo_last_action())
	assert(token.has_condition("stunned"))
	token.set_condition("stunned", false)
	board._reset_map_history_baseline(sync.create_snapshot())

	# Direct token edits are normally missed by the older manual-only history.
	token.set_display_name("Changed")
	token.set_condition("poisoned", true)
	token.add_active_spell_id("bless")
	token.set_visual_front_quarter_turns(1)
	var modified: Dictionary = sync.create_snapshot()
	assert(initial != modified)
	board._on_map_autosave_committed(modified, initial, true)
	assert(board._undo_stack.size() == 1,
		"Debounced implicit edits must create one map snapshot checkpoint")
	assert(board.undo_last_action())
	assert(token.get_display_name() == "Original"
		and not token.has_condition("poisoned")
		and not token.get_active_spell_ids().has("bless")
		and token.get_visual_front_quarter_turns() == 0,
		"Undo must restore name, conditions, active spells and miniature orientation")
	assert(board.redo_last_action())
	assert(token.get_display_name() == "Changed"
		and token.has_condition("poisoned")
		and token.get_active_spell_ids().has("bless"),
		"Redo must restore token edits")
	var history_count: int = board._undo_stack.size()
	board._on_map_autosave_committed(modified, initial, true)
	assert(board._undo_stack.size() == history_count,
		"Undo/redo must not create a second checkpoint on disk flush")

	# The area editor already records a pre-action snapshot.
	board._reset_map_history_baseline(sync.create_snapshot())
	var before_area: Dictionary = sync.create_snapshot()
	board.measurement_tool.add_spell_aoe(
		Vector3(1, 2, 3), Vector3(4, 2, 3), "sphere", "fireball")
	assert(board.measurement_tool.serialize_persistent_aoes().size() == 1)
	var after_area: Dictionary = sync.create_snapshot()
	board._on_map_autosave_committed(after_area, before_area, true)
	assert(board._undo_stack.size() == 1,
		"Autosave must not duplicate the measurement tool's explicit undo")
	assert(board.undo_last_action())
	assert(board.measurement_tool.serialize_persistent_aoes().is_empty(),
		"Undo must remove the committed spell area")
	assert(board.redo_last_action())
	assert(board.measurement_tool.serialize_persistent_aoes().size() == 1,
		"Redo must recreate the committed spell area")

	# A token move also has an explicit transaction; keep it as one action.
	board._reset_map_history_baseline(sync.create_snapshot())
	var previous_position: Vector3 = token.global_position
	var before_move: Dictionary = board.begin_token_move_transaction([token])
	var preceding_snapshot: Dictionary = sync.create_snapshot()
	token.global_position += Vector3(1.0, 0.0, 0.0)
	board.commit_undo_transaction(before_move)
	board._on_map_autosave_committed(sync.create_snapshot(), preceding_snapshot, true)
	assert(board._undo_stack.size() == 1)
	assert(board.undo_last_action())
	assert(token.global_position.is_equal_approx(previous_position))
	assert(board.redo_last_action())
	assert(token.global_position.is_equal_approx(previous_position + Vector3.RIGHT))

	# A remote map must replace the local baseline, not become a local Ctrl+Z.
	board._reset_map_history_baseline(sync.create_snapshot())
	token.set_condition("stunned", true)
	var next_snapshot: Dictionary = sync.create_snapshot()
	board._on_map_autosave_committed(next_snapshot, {}, true)
	assert(board._undo_stack.size() == 1)
	board._on_map_autosave_committed(next_snapshot, next_snapshot, false)
	assert(board._undo_stack.is_empty() and board._redo_stack.is_empty())

	board.queue_free()
	await process_frame
	await process_frame
	print("PASS: automatic map snapshots, implicit and explicit undo/redo, remote baseline")
	quit()
