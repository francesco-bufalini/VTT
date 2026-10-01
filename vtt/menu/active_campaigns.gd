extends Control

const ACTION_RENAME := 1
const ACTION_DELETE := 2
const MAIN_MENU_SCENE_PATH := "res://vtt/menu/main_menu.tscn"

var _status_label: Label
var _rename_dialog: ConfirmationDialog
var _rename_input: LineEdit
var _delete_dialog: ConfirmationDialog

var _pending_campaign_id: String = ""
var _pending_campaign_name: String = ""


func _ready() -> void:
	_build_ui()
	_build_action_dialogs()


func _build_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.045, 0.05, 0.065, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)

	var header: HBoxContainer = HBoxContainer.new()
	layout.add_child(header)

	var title: Label = Label.new()
	title.text = "Campagne attive"
	title.add_theme_font_size_override("font_size", 32)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var back: Button = Button.new()
	back.text = "Indietro"
	back.custom_minimum_size = Vector2(110, 38)
	back.pressed.connect(
		func() -> void:
			get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	)
	header.add_child(back)

	_status_label = Label.new()
	_status_label.modulate = Color(0.72, 0.75, 0.82, 1.0)
	layout.add_child(_status_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)

	var cards: GridContainer = GridContainer.new()
	cards.columns = 3
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("h_separation", 14)
	cards.add_theme_constant_override("v_separation", 14)
	scroll.add_child(cards)

	var campaigns: Array[Dictionary] = _list_campaigns()
	if campaigns.is_empty():
		_status_label.text = "Non ci sono campagne disponibili."
		return

	_status_label.text = "%d campagne/scenari disponibili" % campaigns.size()
	for campaign: Dictionary in campaigns:
		cards.add_child(_campaign_card(campaign))


func _campaign_card(campaign: Dictionary) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 238)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	var preview: ColorRect = ColorRect.new()
	preview.custom_minimum_size = Vector2(276, 120)
	preview.color = (
		Color(0.14, 0.18, 0.25, 1.0)
		if bool(campaign.get("builtin", false))
		else Color(0.13, 0.23, 0.18, 1.0)
	)
	layout.add_child(preview)

	var preview_label: Label = Label.new()
	preview_label.text = "ANTEPRIMA"
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(preview_label)

	var name_row: HBoxContainer = HBoxContainer.new()
	layout.add_child(name_row)

	var name_label: Label = Label.new()
	name_label.text = String(campaign.get("name", "Campagna"))
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_row.add_child(name_label)

	var actions: MenuButton = MenuButton.new()
	actions.text = "⋮"
	actions.tooltip_text = "Gestisci campagna"
	actions.custom_minimum_size = Vector2(38, 34)
	name_row.add_child(actions)

	var popup: PopupMenu = actions.get_popup()
	popup.add_item("Rinomina", ACTION_RENAME)
	popup.add_item("Elimina", ACTION_DELETE)

	var builtin: bool = bool(campaign.get("builtin", false))
	if builtin:
		popup.set_item_disabled(popup.get_item_index(ACTION_RENAME), true)
		popup.set_item_disabled(popup.get_item_index(ACTION_DELETE), true)
		actions.tooltip_text = "Scenario incorporato: rinomina ed eliminazione disabilitate"

	popup.id_pressed.connect(
		func(action_id: int) -> void:
			_on_card_action(action_id, campaign)
	)

	var description: Label = Label.new()
	description.text = String(campaign.get("description", ""))
	description.modulate = Color(0.7, 0.73, 0.8, 1.0)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.max_lines_visible = 2
	layout.add_child(description)

	var open_button: Button = Button.new()
	open_button.text = "Apri"
	open_button.custom_minimum_size = Vector2(0, 36)
	open_button.pressed.connect(
		func() -> void:
			_open_campaign(String(campaign.get("id", "")))
	)
	layout.add_child(open_button)

	return panel


func _build_action_dialogs() -> void:
	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "Rinomina campagna"
	_rename_dialog.ok_button_text = "Rinomina"
	_rename_dialog.cancel_button_text = "Annulla"
	_rename_dialog.min_size = Vector2i(430, 200)
	add_child(_rename_dialog)

	var rename_body: VBoxContainer = VBoxContainer.new()
	rename_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rename_body.offset_left = 18
	rename_body.offset_top = 18
	rename_body.offset_right = -18
	rename_body.offset_bottom = -68
	_rename_dialog.add_child(rename_body)

	var rename_label: Label = Label.new()
	rename_label.text = "Nuovo nome:"
	rename_body.add_child(rename_label)

	_rename_input = LineEdit.new()
	_rename_input.max_length = 80
	rename_body.add_child(_rename_input)
	_rename_dialog.confirmed.connect(_confirm_rename)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Elimina campagna"
	_delete_dialog.ok_button_text = "Elimina"
	_delete_dialog.cancel_button_text = "Annulla"
	_delete_dialog.min_size = Vector2i(460, 200)
	add_child(_delete_dialog)
	_delete_dialog.confirmed.connect(_confirm_delete)


func _on_card_action(action_id: int, campaign: Dictionary) -> void:
	if bool(campaign.get("builtin", false)):
		return

	_pending_campaign_id = String(campaign.get("id", ""))
	_pending_campaign_name = String(campaign.get("name", "Campagna"))

	match action_id:
		ACTION_RENAME:
			_rename_input.text = _pending_campaign_name
			_rename_input.select_all()
			_rename_dialog.reset_size()
			_rename_dialog.popup_centered_clamped(Vector2i(430, 200), 0.92)
			_rename_input.call_deferred("grab_focus")
		ACTION_DELETE:
			_delete_dialog.dialog_text = (
				"Vuoi eliminare definitivamente la campagna \"%s\"?\n"
				+ "Il salvataggio non potrà essere recuperato."
			) % _pending_campaign_name
			_delete_dialog.reset_size()
			_delete_dialog.popup_centered_clamped(Vector2i(460, 200), 0.92)


func _confirm_rename() -> void:
	var new_name: String = _rename_input.text.strip_edges()
	if new_name.is_empty():
		_set_status("Il nome della campagna non può essere vuoto.")
		return

	var error: Error = int(_campaign_manager().call(
		"rename_campaign",
		_pending_campaign_id,
		new_name
	))
	if error != OK:
		_set_status("Errore rinomina: %s" % error_string(error))
		return

	get_tree().reload_current_scene()


func _confirm_delete() -> void:
	var error: Error = int(_campaign_manager().call("delete_campaign", _pending_campaign_id))
	if error != OK:
		_set_status("Errore eliminazione: %s" % error_string(error))
		return

	get_tree().reload_current_scene()


func _open_campaign(campaign_id: String) -> void:
	var error: Error = int(_campaign_manager().call("open_campaign", campaign_id))
	if error != OK:
		_set_status("Errore apertura campagna: %s" % error_string(error))



func _campaign_manager() -> Node:
	var manager: Node = get_node_or_null("/root/CampaignManager")
	if manager == null:
		push_error("CampaignManager autoload non disponibile.")
	return manager


func _list_campaigns() -> Array[Dictionary]:
	var manager: Node = _campaign_manager()
	var result: Array[Dictionary] = []
	if manager == null:
		return result
	var value: Variant = manager.call("list_campaigns")
	if value is Array:
		for item: Variant in value:
			if item is Dictionary:
				result.append(item as Dictionary)
	return result


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
