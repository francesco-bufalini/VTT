extends SceneTree

const BoardScript = preload("res://dnd_base.gd")

# Exercise the real placement controller without initializing a whole campaign.
class BareBoard extends BoardScript:
	func _ready() -> void:
		pass


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var board := BareBoard.new()
	for name: String in ["VolumetricGrid", "Tokens", "MeasurementTool"]:
		var spatial := Node3D.new()
		spatial.name = name
		board.add_child(spatial)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	board.add_child(camera)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	board.add_child(ui)
	var context := PopupMenu.new()
	context.name = "ContextMenu"
	ui.add_child(context)
	var color := ConfirmationDialog.new()
	color.name = "TokenColorDialog"
	ui.add_child(color)
	var content := ScrollContainer.new()
	content.name = "Content"
	color.add_child(content)
	var body := VBoxContainer.new()
	body.name = "VBox"
	content.add_child(body)
	var size := OptionButton.new()
	size.name = "SizeSelector"
	body.add_child(size)
	var measurement_label := Label.new()
	measurement_label.name = "MeasurementModeLabel"
	ui.add_child(measurement_label)
	root.add_child(board)
	board._build_identity_placement_hint()

	board._has_pending_spawn_position = true
	board._pending_spawn_position = Vector3(2, 0, 2)
	board._begin_sheet_spawn_without_dialog({
		"id": "offline-hero", "name": "Hero",
		"current_miniature_id": "hero_test"
	})
	assert(not board._has_pending_spawn_position,
		"Missing miniature must cancel the selected world position")
	assert(board._sheet_spawn_pending_record.is_empty()
		and board._creature_spawn_sheet_id.is_empty(),
		"Missing miniature must release all sheet-placement state")
	assert(board.identity_placement_panel.visible,
		"Missing miniature should briefly explain the cancellation")
	assert(board.identity_placement_label.text.contains("hero_test")
		and board.identity_placement_label.text.contains("annullato"))
	await create_timer(3.1).timeout
	assert(not board.identity_placement_panel.visible,
		"Placement failure notice must disappear without interaction")
	board.queue_free()
	await process_frame
	print("PASS: missing miniature cancels placement and leaves no persistent popup")
	quit()
