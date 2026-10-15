extends RefCounted

# A shared, opt-in recipient picker for inventory items and documents.
# Individual transports are already recipient-addressed and ACK-verified.
const DialogLayout = preload("res://vtt/dialog_layout.gd")


static func choose(host: Control, peers: Array, subject: String,
		on_send: Callable) -> ConfirmationDialog:
	var choices: Array[Dictionary] = []
	var seen: Dictionary = {}
	for value: Variant in peers:
		if not value is Dictionary:
			continue
		var peer: Dictionary = value
		var id: String = String(peer.get("id", "")).strip_edges()
		if id.is_empty() or seen.has(id):
			continue
		seen[id] = true
		choices.append(peer)
	if choices.is_empty():
		return null

	var dialog := ConfirmationDialog.new()
	dialog.title = "Destinatari del %s" % subject
	dialog.ok_button_text = "Invia"
	dialog.cancel_button_text = "Annulla"
	dialog.get_ok_button().disabled = true
	host.add_child(dialog)

	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 310
	content.add_theme_constant_override("separation", 8)
	dialog.add_child(content)
	var hint := Label.new()
	hint.text = "Seleziona uno o più utenti online. Nessuno è selezionato automaticamente."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)

	var checks: Dictionary = {}
	for peer: Dictionary in choices:
		var id: String = String(peer.get("id", "")).strip_edges()
		var label: String = String(peer.get("label", "Giocatore")).strip_edges()
		if label.is_empty():
			label = "Giocatore"
		var check := CheckBox.new()
		check.text = "%s (%s)" % [label, id.substr(0, 8)]
		check.tooltip_text = String(peer.get("device", ""))
		check.custom_minimum_size.y = 36
		checks[id] = check
		content.add_child(check)
		check.toggled.connect(func(_pressed: bool) -> void:
			var any_selected := false
			for candidate: CheckBox in checks.values():
				if candidate.button_pressed:
					any_selected = true
					break
			dialog.get_ok_button().disabled = not any_selected
		)

	dialog.confirmed.connect(func() -> void:
		var recipients: Array[String] = []
		for id: String in checks:
			var check: CheckBox = checks[id]
			if check.button_pressed:
				recipients.append(id)
		if not recipients.is_empty() and on_send.is_valid():
			on_send.call(recipients)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	DialogLayout.popup(dialog, Vector2i(440, 330))
	return dialog
