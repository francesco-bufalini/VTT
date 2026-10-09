extends SceneTree

const DialogLayout = preload("res://vtt/dialog_layout.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Test primo avvio"
	dialog.min_size = Vector2i(320, 160)
	root.add_child(dialog)
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(400, 220)
	dialog.add_child(body)
	var caption := Label.new()
	caption.text = "Dati da confermare"
	body.add_child(caption)
	var field := LineEdit.new()
	field.placeholder_text = "Campo"
	body.add_child(field)

	DialogLayout.popup(dialog, Vector2i(430, 310), 0.92)
	assert(dialog.visible, "The first opening must display the dialog")
	assert(dialog.wrap_controls, "Content must set the dialog minimum size")
	assert(dialog.get_ok_button().visible, "Confirm must be visible on first open")
	assert(dialog.get_cancel_button().visible, "Cancel must be visible on first open")
	await process_frame
	assert(dialog.size.y >= ceili(dialog.get_contents_minimum_size().y),
		"The native footer must fit after first-frame layout")
	dialog.hide()

	# Custom-button dialogs (the initiative picker) hide the native footer.
	dialog.get_ok_button().hide()
	dialog.get_cancel_button().hide()
	DialogLayout.popup(dialog, Vector2i(430, 310))
	assert(not dialog.get_ok_button().visible and not dialog.get_cancel_button().visible,
		"The shared popup must preserve deliberately hidden native buttons")
	dialog.hide()
	dialog.queue_free()
	quit()
