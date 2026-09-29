extends Control

var _status_label: Label


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.045, 0.05, 0.065, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)

	var title := Label.new()
	title.text = "Campagne attive"
	title.add_theme_font_size_override("font_size", 36)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var back := Button.new()
	back.text = "Indietro"
	back.custom_minimum_size = Vector2(130, 42)
	back.pressed.connect(
		func() -> void:
			get_tree().change_scene_to_file(CampaignManager.MAIN_MENU_SCENE)
	)
	header.add_child(back)

	_status_label = Label.new()
	_status_label.modulate = Color(0.72, 0.75, 0.82, 1.0)
	layout.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)

	var cards := GridContainer.new()
	cards.columns = 3
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("h_separation", 18)
	cards.add_theme_constant_override("v_separation", 18)
	scroll.add_child(cards)

	var campaigns := CampaignManager.list_campaigns()
	if campaigns.is_empty():
		_status_label.text = "Non ci sono campagne disponibili."
		return

	_status_label.text = "%d campagne/scenari disponibili" % campaigns.size()
	for campaign: Dictionary in campaigns:
		cards.add_child(_campaign_card(campaign))


func _campaign_card(campaign: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 260)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var preview := ColorRect.new()
	preview.custom_minimum_size = Vector2(292, 140)
	preview.color = (
		Color(0.14, 0.18, 0.25, 1.0)
		if bool(campaign.get("builtin", false))
		else Color(0.13, 0.23, 0.18, 1.0)
	)
	layout.add_child(preview)

	var preview_label := Label.new()
	preview_label.text = "ANTEPRIMA"
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(preview_label)

	var name_label := Label.new()
	name_label.text = String(campaign.get("name", "Campagna"))
	name_label.add_theme_font_size_override("font_size", 22)
	layout.add_child(name_label)

	var description := Label.new()
	description.text = String(campaign.get("description", ""))
	description.modulate = Color(0.7, 0.73, 0.8, 1.0)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(description)

	var open_button := Button.new()
	open_button.text = "Apri"
	open_button.custom_minimum_size = Vector2(0, 40)
	open_button.pressed.connect(
		func() -> void:
			_open_campaign(String(campaign.get("id", "")))
	)
	layout.add_child(open_button)

	return panel


func _open_campaign(campaign_id: String) -> void:
	var error := CampaignManager.open_campaign(campaign_id)
	if error != OK:
		_status_label.text = "Errore apertura campagna: %s" % error_string(error)
