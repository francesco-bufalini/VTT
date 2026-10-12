extends SceneTree

const BoardScript = preload("res://dnd_base.gd")
const TokenScene = preload("res://token.tscn")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# Test the actual signal binding used by individual context-menu rows.
	# No full map has to load to verify that each button edits its own ID.
	var board: Node3D = BoardScript.new()
	var target: CharacterBody3D = TokenScene.instantiate()
	root.add_child(target)
	var blinded := CheckButton.new()
	var poisoned := CheckButton.new()
	blinded.toggled.connect(
		Callable(board, "_on_token_condition_toggled").bind(target, "blinded")
	)
	poisoned.toggled.connect(
		Callable(board, "_on_token_condition_toggled").bind(target, "poisoned")
	)
	blinded.toggled.emit(true)
	assert(target.has_condition("blinded"))
	assert(not target.has_condition("poisoned"),
		"The Blinded row must not toggle another condition")
	poisoned.toggled.emit(true)
	assert(target.has_condition("blinded") and target.has_condition("poisoned"))
	blinded.toggled.emit(false)
	assert(not target.has_condition("blinded") and target.has_condition("poisoned"))

	# Closing the context menu must not recapture the mouse while its
	# condition/spell dialog is still displayed.
	var dialog := ConfirmationDialog.new()
	root.add_child(dialog)
	dialog.popup_centered(Vector2i(300, 200))
	board.set("_token_effect_dialog", dialog)
	board.set("_ui_owns_mouse", false)
	board.call("_finish_context_menu_close")
	assert(bool(board.get("_ui_owns_mouse")),
		"Token condition dialog must retain GUI/mouse ownership")
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	dialog.hide()
	dialog.queue_free()
	blinded.free()
	poisoned.free()
	target.queue_free()
	board.free()
	await process_frame
	print("PASS: context condition buttons and modal mouse ownership")
	quit()
