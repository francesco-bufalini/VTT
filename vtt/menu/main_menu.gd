extends Control

var _options_dialog: AcceptDialog


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.055, 0.06, 0.075, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 520)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_top", 38)
	margin.add_theme_constant_override("margin_bottom", 38)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	margin.add_child(layout)

	var title := Label.new()
	title.text = "VTT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 54)
	layout.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Virtual Tabletop"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.72, 0.75, 0.82, 1.0)
	layout.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 34)
	layout.add_child(spacer)

	var active_button := _menu_button("Campagne attive")
	active_button.pressed.connect(_open_active_campaigns)
	layout.add_child(active_button)

	var new_button := _menu_button("Nuova campagna")
	new_button.pressed.connect(_create_new_campaign)
	layout.add_child(new_button)

	var options_button := _menu_button("Opzioni")
	options_button.pressed.connect(_show_options_placeholder)
	layout.add_child(options_button)

	var hint := Label.new()
	hint.text = "Le impostazioni audio, grafica e comandi verranno sviluppate nella prossima iterazione."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.58, 0.61, 0.68, 1.0)
	layout.add_child(hint)

	_options_dialog = AcceptDialog.new()
	_options_dialog.title = "Opzioni"
	_options_dialog.dialog_text = (
		"Sezione predisposta.\n"
		+ "Audio, grafica e comandi saranno aggiunti successivamente."
	)
	add_child(_options_dialog)


func _menu_button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(360, 62)
	button.add_theme_font_size_override("font_size", 22)
	return button


func _open_active_campaigns() -> void:
	get_tree().change_scene_to_file(CampaignManager.ACTIVE_CAMPAIGNS_SCENE)


func _create_new_campaign() -> void:
	var campaign_id := CampaignManager.create_campaign()
	if campaign_id.is_empty():
		_show_error("Impossibile creare la campagna.")
		return

	var error := CampaignManager.open_campaign(campaign_id)
	if error != OK:
		_show_error("Impossibile aprire la nuova campagna: %s" % error_string(error))


func _show_options_placeholder() -> void:
	_options_dialog.popup_centered(Vector2i(460, 190))


func _show_error(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Errore"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered(Vector2i(480, 180))
	dialog.close_requested.connect(dialog.queue_free)
