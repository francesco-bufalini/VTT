extends SceneTree
const Dialogs = preload("res://vtt/quick_custom_catalog_dialog.gd")
const Store = preload("res://vtt/quick_custom_catalog.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var parent := Control.new()
	root.add_child(parent)
	root.gui_embed_subwindows = true
	root.set_meta("vtt_touch_layout", true)
	root.size = Vector2i(360, 640)
	var creations: Array = []
	for category: String in ["feats", "backgrounds", "items"]:
		Dialogs.create_popup(parent, category, func(row: Dictionary) -> void: creations.append(row))
		var dialog := parent.get_child(0) as ConfirmationDialog
		assert(dialog != null and dialog.visible and dialog.get_ok_button().disabled,
			"Custom content forms must open completely, with empty-name saving disabled")
		await process_frame
		await process_frame
		assert(dialog.size.x <= 348 and dialog.position.x >= 0,
			"Creation dialogs must fit a phone-sized screen")
		dialog.hide()
		await process_frame
		assert(is_instance_valid(dialog), "Temporary hiding for mobile choice selection must not destroy the form")
		dialog.show()
		dialog.canceled.emit()
		dialog.hide()
		await process_frame
		assert(not is_instance_valid(dialog), "Cancel must release the custom form")
	assert(creations.is_empty())
	# A rejected save must preserve the form, including its description.
	Dialogs.create_popup(parent, "items", func(row: Dictionary) -> void: creations.append(row))
	var form_dialog := parent.get_child(0) as ConfirmationDialog
	var fields := form_dialog.find_children("*", "LineEdit", true, false)
	var title_field := fields[0] as LineEdit
	var body := form_dialog.find_children("*", "TextEdit", true, false)[0] as TextEdit
	assert(title_field.max_length == 120 and not form_dialog.dialog_hide_on_ok)
	var unique_name := "Homebrew regression " + str(Time.get_ticks_usec())
	var existing := Store.create("items", unique_name, "Original")
	assert(not existing.is_empty())
	title_field.text = unique_name
	body.text = "Keep this draft after a duplicate-name error"
	form_dialog.confirmed.emit()
	await process_frame
	assert(is_instance_valid(form_dialog) and form_dialog.visible and creations.is_empty())
	assert(body.text == "Keep this draft after a duplicate-name error")
	for child: Node in form_dialog.get_children():
		if child is AcceptDialog:
			child.queue_free()
	await process_frame
	title_field.text = unique_name + " corrected"
	form_dialog.confirmed.emit()
	await process_frame
	assert(not is_instance_valid(form_dialog) and creations.size() == 1)
	assert(Store.remove(creations[0]) and Store.remove(existing))
	# Oversized writes must leave the previous package byte-for-byte intact.
	var previous := FileAccess.get_file_as_string(Store.PATH)
	assert(Store.create("items", unique_name, "x".repeat(2 * 1024 * 1024)).is_empty())
	assert(FileAccess.get_file_as_string(Store.PATH) == previous)

	Dialogs.delete_popup(parent, {"id": "homebrew:" + Store.NAMESPACE + ":regression", "name": "Synthetic"}, Callable())
	var deletion := parent.get_child(0) as ConfirmationDialog
	assert(deletion != null and deletion.visible)
	deletion.close_requested.emit()
	await process_frame
	assert(not is_instance_valid(deletion))
	var warning := AcceptDialog.new()
	parent.add_child(warning)
	Dialogs._free_on_close(warning)
	warning.confirmed.emit()
	await process_frame
	assert(not is_instance_valid(warning), "Acknowledging a warning must release it")
	parent.queue_free()
	await process_frame
	print("PASS: custom content forms, cancel/close cleanup and temporary mobile hiding, failed-save draft preservation and bounded catalog writes")
	quit()
