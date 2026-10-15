extends SceneTree
const Dialogs = preload("res://vtt/quick_custom_catalog_dialog.gd")
const Store = preload("res://vtt/quick_custom_catalog.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var parent := Control.new()
	root.add_child(parent)
	var creations: Array = []
	for category: String in ["feats", "backgrounds", "items"]:
		Dialogs.create_popup(parent, category, func(row: Dictionary) -> void: creations.append(row))
		var dialog := parent.get_child(0) as ConfirmationDialog
		assert(dialog != null and dialog.visible and dialog.get_ok_button().disabled,
			"Custom content forms must open completely, with empty-name saving disabled")
		dialog.hide()
		await process_frame
		assert(is_instance_valid(dialog), "Temporary hiding for mobile choice selection must not destroy the form")
		dialog.show()
		dialog.canceled.emit()
		dialog.hide()
		await process_frame
		assert(not is_instance_valid(dialog), "Cancel must release the custom form")
	assert(creations.is_empty())
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
	print("PASS: custom content forms, cancel/close cleanup and temporary mobile hiding without catalog writes")
	quit()