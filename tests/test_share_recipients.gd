extends SceneTree

const ShareRecipients = preload("res://vtt/share_recipients_dialog.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# Exercise a narrow touch viewport, not only the default desktop window.
	root.gui_embed_subwindows = true
	root.set_meta("vtt_touch_layout", true)
	root.size = Vector2i(360, 640)
	var host := Control.new()
	root.add_child(host)
	var delivered: Array = []
	var peers := [
		{"id": "peer-anna", "label": "Anna", "device": "desktop"},
		{"id": "peer-bruno", "label": "Bruno", "device": "mobile"}
	]
	var dialog: ConfirmationDialog = ShareRecipients.choose(
		host, peers, "oggetto", func(selected: Array[String]) -> void:
			delivered.append(selected)
	)
	assert(dialog != null and dialog.get_ok_button().disabled,
		"Sending must require explicit recipient selection")
	await process_frame
	await process_frame
	assert(dialog.position.x >= 0 and dialog.position.y >= 0
		and dialog.position.x + dialog.size.x <= root.size.x
		and dialog.position.y + dialog.size.y <= root.size.y,
		"Recipient popup must stay within a 360x640 mobile screen")
	assert(dialog.get_ok_button().is_visible_in_tree(),
		"Native Invia control must remain visible and reachable")
	var checks := dialog.find_children("*", "CheckBox", true, false)
	assert(checks.size() == 2)
	assert(not (checks[0] as CheckBox).button_pressed and not (checks[1] as CheckBox).button_pressed)
	(checks[1] as CheckBox).button_pressed = true
	assert(not dialog.get_ok_button().disabled)
	dialog.confirmed.emit()
	assert(delivered.size() == 1 and delivered[0] == ["peer-bruno"],
		"Only checked peer IDs may be passed to document/item transport")
	await process_frame
	assert(not is_instance_valid(dialog))
	var multiple := ShareRecipients.choose(host, peers, "documento",
		func(selected: Array[String]) -> void: delivered.append(selected))
	var multiple_checks := multiple.find_children("*", "CheckBox", true, false)
	for check: CheckBox in multiple_checks:
		check.button_pressed = true
	multiple.hide()
	multiple.confirmed.emit()
	assert(delivered.size() == 2 and delivered[1] == ["peer-anna", "peer-bruno"],
		"Multiple recipients must preserve exactly the selected peer IDs")
	await process_frame
	host.queue_free()
	await process_frame
	print("PASS: recipient selection is opt-in and never sends to unchecked peers")
	quit()
