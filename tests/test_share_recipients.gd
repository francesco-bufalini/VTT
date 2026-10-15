extends SceneTree

const ShareRecipients = preload("res://vtt/share_recipients_dialog.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
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
	host.queue_free()
	await process_frame
	print("PASS: recipient selection is opt-in and never sends to unchecked peers")
	quit()
