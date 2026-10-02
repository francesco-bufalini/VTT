extends Control

const MAIN_MENU_SCENE_PATH := "res://vtt/menu/main_menu.tscn"
const MenuBackdrop = preload("res://vtt/menu/menu_backdrop.gd")
const MenuStyle = preload("res://vtt/menu/menu_style.gd")

var _status_label: Label


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var backdrop: Control = MenuBackdrop.new()
	backdrop.name = "MenuBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	move_child(backdrop, 0)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 34)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	layout.add_child(header)

	var title := Label.new()
	title.text = "Campagne attive"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MenuStyle.apply_title_style(title, 48)
	header.add_child(title)

	var back: Button = MenuStyle.menu_button(
		"Indietro",
		Vector2(130, 42)
	)
	back.pressed.connect(
		func() -> void:
			get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	)
	header.add_child(back)

	_status_label = Label.new()
	_status_label.add_theme_font_override("font", MenuStyle.menu_font())
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override(
		"font_color",
		Color(0.86, 0.80, 0.69, 0.95)
	)
	layout.add_child(_status_label)

	var separator := HSeparator.new()
	separator.modulate = Color(0.56, 0.43, 0.24, 0.52)
	layout.add_child(separator)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_theme_constant_override("scrollbar_margin_left", 12)
	layout.add_child(scroll)

	var cards_margin := MarginContainer.new()
	cards_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_margin.add_theme_constant_override("margin_top", 10)
	cards_margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(cards_margin)

	var cards := GridContainer.new()
	cards.columns = 3
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("h_separation", 18)
	cards.add_theme_constant_override("v_separation", 18)
	cards_margin.add_child(cards)

	var campaigns: Array[Dictionary] = _list_campaign_groups()
	_status_label.text = "%d campagne attive" % campaigns.size()
	if campaigns.is_empty():
		return

	for campaign: Dictionary in campaigns:
		cards.add_child(_campaign_card(campaign))


func _campaign_card(campaign: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(350, 205)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		MenuStyle.menu_panel_style()
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 11)
	margin.add_child(layout)

	var name_label := Label.new()
	name_label.text = String(campaign.get("name", "Campagna"))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_override("font", MenuStyle.menu_font())
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override(
		"font_color",
		Color(0.94, 0.85, 0.64)
	)
	layout.add_child(name_label)

	var count_label := Label.new()
	var scenario_count: int = int(campaign.get("scenario_count", 0))
	count_label.text = "%d scenari" % scenario_count
	count_label.add_theme_font_override("font", MenuStyle.menu_font())
	count_label.add_theme_font_size_override("font_size", 16)
	count_label.add_theme_color_override(
		"font_color",
		Color(0.83, 0.75, 0.62, 0.92)
	)
	layout.add_child(count_label)

	var description := Label.new()
	description.text = String(campaign.get("description", ""))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.max_lines_visible = 2
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_font_override("font", MenuStyle.menu_font())
	description.add_theme_font_size_override("font_size", 15)
	description.add_theme_color_override(
		"font_color",
		Color(0.80, 0.78, 0.73, 0.92)
	)
	layout.add_child(description)

	var open_button: Button = MenuStyle.menu_button(
		"Apri campagna",
		Vector2(0, 40)
	)
	open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_button.pressed.connect(
		func() -> void:
			_open_campaign_group(
				String(campaign.get("id", ""))
			)
	)
	layout.add_child(open_button)

	return panel


func _open_campaign_group(campaign_group_id: String) -> void:
	var manager: Node = _campaign_manager()
	if manager == null:
		_set_status("CampaignManager non disponibile.")
		return

	var error: Error = int(
		manager.call("open_campaign_group", campaign_group_id)
	)
	if error != OK:
		_set_status(
			"Errore apertura campagna: %s"
			% error_string(error)
		)


func _campaign_manager() -> Node:
	var manager: Node = get_node_or_null("/root/CampaignManager")
	if manager == null:
		push_error("CampaignManager autoload non disponibile.")
	return manager


func _list_campaign_groups() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var manager: Node = _campaign_manager()
	if manager == null:
		return result

	var value: Variant = manager.call("list_campaign_groups")
	if value is Array:
		for item: Variant in value:
			if item is Dictionary:
				result.append((item as Dictionary).duplicate(true))
	return result


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
