extends Control

const MAIN_MENU_SCENE_PATH := "res://vtt/menu/main_menu.tscn"
const MenuBackdrop = preload("res://vtt/menu/menu_backdrop.gd")
const MenuStyle = preload("res://vtt/menu/menu_style.gd")

var _status_label: Label
var _cards_grid: GridContainer
var _edit_dialog: ConfirmationDialog
var _edit_name_input: LineEdit
var _edit_description_input: TextEdit
var _pending_campaign_group_id: String = ""


func _ready() -> void:
	_build_ui()
	_build_edit_dialog()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _cards_grid != null:
		_update_grid_columns()


func _update_grid_columns() -> void:
	if _cards_grid == null:
		return
	# Reserve margins, scrollbar and gaps; never truncate the card actions.
	var usable_width: float = maxf(1.0, size.x - 110.0)
	_cards_grid.columns = maxi(1, mini(3, int((usable_width + 18.0) / 333.0)))


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
	_cards_grid = cards
	_update_grid_columns()
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
	panel.custom_minimum_size = Vector2(315, 205)
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

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 10)
	layout.add_child(actions_row)

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
	actions_row.add_child(open_button)

	var edit_button: Button = MenuStyle.menu_button(
		"Modifica",
		Vector2(110, 40)
	)
	edit_button.pressed.connect(
		func() -> void:
			_request_edit_campaign(campaign)
	)
	actions_row.add_child(edit_button)

	return panel


func _build_edit_dialog() -> void:
	_edit_dialog = ConfirmationDialog.new()
	_edit_dialog.title = "Modifica campagna"
	_edit_dialog.ok_button_text = "Salva"
	_edit_dialog.cancel_button_text = "Annulla"
	_edit_dialog.min_size = Vector2i(560, 390)
	_edit_dialog.add_theme_constant_override("buttons_min_width", 100)
	_edit_dialog.add_theme_constant_override("buttons_min_height", 34)
	add_child(_edit_dialog)

	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(510, 285)
	body.add_theme_constant_override("separation", 10)
	_edit_dialog.add_child(body)

	var name_label := Label.new()
	name_label.text = "Nome campagna"
	name_label.add_theme_font_override("font", MenuStyle.menu_font())
	name_label.add_theme_font_size_override("font_size", 17)
	body.add_child(name_label)

	_edit_name_input = LineEdit.new()
	_edit_name_input.max_length = 100
	_edit_name_input.placeholder_text = "Nome della campagna"
	_edit_name_input.add_theme_font_override("font", MenuStyle.menu_font())
	body.add_child(_edit_name_input)

	var description_label := Label.new()
	description_label.text = "Descrizione"
	description_label.add_theme_font_override("font", MenuStyle.menu_font())
	description_label.add_theme_font_size_override("font_size", 17)
	body.add_child(description_label)

	_edit_description_input = TextEdit.new()
	_edit_description_input.custom_minimum_size = Vector2(0, 145)
	_edit_description_input.placeholder_text = "Descrizione della campagna"
	_edit_description_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_edit_description_input.add_theme_font_override(
		"font",
		MenuStyle.menu_font()
	)
	body.add_child(_edit_description_input)

	var hint := Label.new()
	hint.text = "Le modifiche vengono salvate e non cambiano gli scenari contenuti."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_override("font", MenuStyle.menu_font())
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override(
		"font_color",
		Color(0.80, 0.78, 0.73, 0.86)
	)
	body.add_child(hint)

	_edit_dialog.confirmed.connect(_confirm_edit_campaign)


func _request_edit_campaign(campaign: Dictionary) -> void:
	_pending_campaign_group_id = String(campaign.get("id", ""))
	if _pending_campaign_group_id.is_empty():
		_set_status("Impossibile modificare questa campagna.")
		return

	_edit_name_input.text = String(campaign.get("name", ""))
	_edit_description_input.text = String(
		campaign.get("description", "")
	)

	_edit_dialog.reset_size()
	_edit_dialog.popup_centered_clamped(Vector2i(560, 390), 0.92)
	_edit_name_input.call_deferred("grab_focus")
	_edit_name_input.call_deferred("select_all")


func _confirm_edit_campaign() -> void:
	if _pending_campaign_group_id.is_empty():
		_set_status("Nessuna campagna selezionata.")
		return

	var new_name: String = _edit_name_input.text.strip_edges()
	if new_name.is_empty():
		_set_status("Il nome della campagna non può essere vuoto.")
		return

	var manager: Node = _campaign_manager()
	if manager == null:
		_set_status("CampaignManager non disponibile.")
		return

	var error: Error = int(
		manager.call(
			"update_campaign_group",
			_pending_campaign_group_id,
			new_name,
			_edit_description_input.text
		)
	)
	if error != OK:
		_set_status(
			"Errore modifica campagna: %s" % error_string(error)
		)
		return

	_pending_campaign_group_id = ""
	get_tree().reload_current_scene()


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
