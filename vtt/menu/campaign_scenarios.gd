extends Control

const ACTION_RENAME := 1
const ACTION_DELETE := 2
const ACTIVE_CAMPAIGNS_SCENE_PATH := "res://vtt/menu/active_campaigns.tscn"
const FOREST_PRESET_ID := "forest_mountains"
const FOREST_PRESET_PATH := (
	"res://assets/presets/forest_mountains/forest_mountains_preset.glb"
)
const PIRATE_SHIP_PRESET_ID := "sirens_light_pirate_ship"
const PIRATE_SHIP_PRESET_PATH := (
	"res://assets/presets/pirate_ship/sirens_light_pirate_ship_preset.glb"
)
const MenuBackdrop = preload("res://vtt/menu/menu_backdrop.gd")
const MenuStyle = preload("res://vtt/menu/menu_style.gd")

var _status_label: Label
var _rename_dialog: ConfirmationDialog
var _rename_input: LineEdit
var _delete_dialog: ConfirmationDialog
var _create_dialog: ConfirmationDialog
var _create_name_input: LineEdit
var _create_preset: OptionButton

var _campaign_group_id: String = ""
var _campaign_group_name: String = ""
var _pending_scenario_id: String = ""
var _pending_scenario_name: String = ""


func _ready() -> void:
	if not _resolve_campaign_group():
		get_tree().change_scene_to_file(ACTIVE_CAMPAIGNS_SCENE_PATH)
		return
	_build_ui()
	_build_action_dialogs()
	_build_create_dialog()


func _resolve_campaign_group() -> bool:
	var manager: Node = _campaign_manager()
	if manager == null:
		return false

	var selected_value: Variant = manager.call(
		"get_selected_campaign_group"
	)
	if selected_value is Dictionary:
		var selected: Dictionary = selected_value as Dictionary
		if not selected.is_empty():
			_campaign_group_id = String(selected.get("id", ""))
			_campaign_group_name = String(
				selected.get("name", "Campagna")
			)
			return not _campaign_group_id.is_empty()

	var groups_value: Variant = manager.call("list_campaign_groups")
	if not groups_value is Array:
		return false
	var groups: Array = groups_value as Array
	if groups.is_empty() or not groups[0] is Dictionary:
		return false

	var fallback: Dictionary = groups[0] as Dictionary
	_campaign_group_id = String(fallback.get("id", ""))
	_campaign_group_name = String(fallback.get("name", "Campagna"))
	if _campaign_group_id.is_empty():
		return false
	return int(
		manager.call("select_campaign_group", _campaign_group_id)
	) == OK


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
	title.text = "Scenari della campagna"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MenuStyle.apply_title_style(title, 44)
	header.add_child(title)

	var create_button: Button = MenuStyle.menu_button(
		"Crea scenario",
		Vector2(170, 42)
	)
	create_button.pressed.connect(_request_create_scenario)
	header.add_child(create_button)

	var back: Button = MenuStyle.menu_button(
		"Indietro",
		Vector2(130, 42)
	)
	back.pressed.connect(
		func() -> void:
			get_tree().change_scene_to_file(
				ACTIVE_CAMPAIGNS_SCENE_PATH
			)
	)
	header.add_child(back)

	_status_label = Label.new()
	_status_label.add_theme_font_override(
		"font",
		MenuStyle.menu_font()
	)
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

	var scenarios: Array[Dictionary] = _list_scenarios()
	_status_label.text = "%s · %d scenari" % [
		_campaign_group_name,
		scenarios.size()
	]

	if scenarios.is_empty():
		return

	for scenario: Dictionary in scenarios:
		cards.add_child(_scenario_card(scenario))


func _scenario_card(scenario: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(350, 228)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		MenuStyle.menu_panel_style()
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	layout.add_child(name_row)

	var name_label := Label.new()
	name_label.text = String(scenario.get("name", "Scenario"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.add_theme_font_override(
		"font",
		MenuStyle.menu_font()
	)
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override(
		"font_color",
		Color(0.94, 0.85, 0.64)
	)
	name_row.add_child(name_label)

	var actions := MenuButton.new()
	actions.text = "⋮"
	actions.tooltip_text = "Gestisci scenario"
	actions.custom_minimum_size = Vector2(38, 34)
	actions.add_theme_font_override("font", MenuStyle.menu_font())
	actions.add_theme_color_override(
		"font_color",
		Color(0.90, 0.84, 0.71)
	)
	name_row.add_child(actions)

	var popup: PopupMenu = actions.get_popup()
	popup.add_item("Rinomina", ACTION_RENAME)
	popup.add_item("Elimina", ACTION_DELETE)

	var builtin: bool = bool(scenario.get("builtin", false))
	if builtin:
		popup.set_item_disabled(
			popup.get_item_index(ACTION_RENAME),
			true
		)
		popup.set_item_disabled(
			popup.get_item_index(ACTION_DELETE),
			true
		)
		actions.tooltip_text = (
			"Scenario incorporato: rinomina ed eliminazione disabilitate"
		)

	popup.id_pressed.connect(
		func(action_id: int) -> void:
			_on_card_action(action_id, scenario)
	)

	var type_label := Label.new()
	type_label.text = (
		"SCENARIO INCORPORATO"
		if builtin
		else "SCENARIO PERSONALIZZATO"
	)
	type_label.add_theme_font_override("font", MenuStyle.menu_font())
	type_label.add_theme_font_size_override("font_size", 13)
	type_label.add_theme_color_override(
		"font_color",
		Color(0.73, 0.61, 0.41, 0.92)
	)
	layout.add_child(type_label)

	var description := Label.new()
	description.text = String(scenario.get("description", ""))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.max_lines_visible = 3
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_font_override(
		"font",
		MenuStyle.menu_font()
	)
	description.add_theme_font_size_override("font_size", 15)
	description.add_theme_color_override(
		"font_color",
		Color(0.80, 0.78, 0.73, 0.92)
	)
	layout.add_child(description)

	var open_button: Button = MenuStyle.menu_button(
		"Apri scenario",
		Vector2(0, 40)
	)
	open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_button.pressed.connect(
		func() -> void:
			_open_scenario(String(scenario.get("id", "")))
	)
	layout.add_child(open_button)

	return panel


func _build_action_dialogs() -> void:
	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "Rinomina scenario"
	_rename_dialog.ok_button_text = "Rinomina"
	_rename_dialog.cancel_button_text = "Annulla"
	_rename_dialog.min_size = Vector2i(430, 200)
	add_child(_rename_dialog)

	var rename_body := VBoxContainer.new()
	rename_body.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	rename_body.offset_left = 18
	rename_body.offset_top = 18
	rename_body.offset_right = -18
	rename_body.offset_bottom = -68
	_rename_dialog.add_child(rename_body)

	var rename_label := Label.new()
	rename_label.text = "Nuovo nome dello scenario:"
	rename_body.add_child(rename_label)

	_rename_input = LineEdit.new()
	_rename_input.max_length = 80
	rename_body.add_child(_rename_input)
	_rename_dialog.confirmed.connect(_confirm_rename)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Elimina scenario"
	_delete_dialog.ok_button_text = "Elimina"
	_delete_dialog.cancel_button_text = "Annulla"
	_delete_dialog.min_size = Vector2i(460, 200)
	add_child(_delete_dialog)
	_delete_dialog.confirmed.connect(_confirm_delete)


func _build_create_dialog() -> void:
	_create_dialog = ConfirmationDialog.new()
	_create_dialog.title = "Crea scenario"
	_create_dialog.ok_button_text = "Crea"
	_create_dialog.cancel_button_text = "Annulla"
	_create_dialog.min_size = Vector2i(500, 300)
	_create_dialog.add_theme_constant_override("buttons_min_width", 100)
	_create_dialog.add_theme_constant_override("buttons_min_height", 34)
	add_child(_create_dialog)

	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(445, 175)
	body.add_theme_constant_override("separation", 10)
	_create_dialog.add_child(body)

	var name_label := Label.new()
	name_label.text = "Nome scenario"
	body.add_child(name_label)

	_create_name_input = LineEdit.new()
	_create_name_input.placeholder_text = "Es. Porto di Meletis"
	_create_name_input.max_length = 80
	body.add_child(_create_name_input)

	var preset_label := Label.new()
	preset_label.text = "Preset iniziale"
	body.add_child(preset_label)

	_create_preset = OptionButton.new()
	_create_preset.custom_minimum_size = Vector2(0, 38)
	body.add_child(_create_preset)
	_populate_create_presets()

	var hint := Label.new()
	hint.text = (
		"Il preset appartiene allo scenario, non alla campagna. "
		+ "Puoi creare altri scenari con preset diversi nella stessa campagna."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.72, 0.75, 0.82, 1.0)
	body.add_child(hint)

	_create_dialog.confirmed.connect(_confirm_create_scenario)


func _populate_create_presets() -> void:
	if _create_preset == null:
		return
	_create_preset.clear()
	_create_preset.add_item("Vuoto bianco")
	_create_preset.set_item_metadata(0, "")
	if FileAccess.file_exists(FOREST_PRESET_PATH):
		var forest_index := _create_preset.item_count
		_create_preset.add_item("Foresta e montagne")
		_create_preset.set_item_metadata(forest_index, FOREST_PRESET_ID)
	if FileAccess.file_exists(PIRATE_SHIP_PRESET_PATH):
		var ship_index := _create_preset.item_count
		_create_preset.add_item("The Siren's Light")
		_create_preset.set_item_metadata(ship_index, PIRATE_SHIP_PRESET_ID)
	_create_preset.select(0)


func _request_create_scenario() -> void:
	_create_name_input.clear()
	_populate_create_presets()
	_create_dialog.reset_size()
	_create_dialog.popup_centered_clamped(Vector2i(500, 300), 0.92)
	_create_name_input.call_deferred("grab_focus")


func _confirm_create_scenario() -> void:
	var scenario_name: String = _create_name_input.text.strip_edges()
	if scenario_name.is_empty():
		_set_status("Inserisci un nome per lo scenario.")
		return
	var manager: Node = _campaign_manager()
	if manager == null:
		_set_status("CampaignManager non disponibile.")
		return

	var preset_id := ""
	if _create_preset != null and _create_preset.selected >= 0:
		preset_id = String(
			_create_preset.get_item_metadata(_create_preset.selected)
		).strip_edges()

	var scenario_id: String = String(
		manager.call(
			"create_scenario",
			_campaign_group_id,
			scenario_name,
			preset_id
		)
	)
	if scenario_id.is_empty():
		_set_status("Impossibile creare lo scenario.")
		return
	get_tree().reload_current_scene()


func _on_card_action(
	action_id: int,
	scenario: Dictionary
) -> void:
	if bool(scenario.get("builtin", false)):
		return

	_pending_scenario_id = String(scenario.get("id", ""))
	_pending_scenario_name = String(
		scenario.get("name", "Scenario")
	)

	match action_id:
		ACTION_RENAME:
			_rename_input.text = _pending_scenario_name
			_rename_input.select_all()
			_rename_dialog.reset_size()
			_rename_dialog.popup_centered_clamped(
				Vector2i(430, 200),
				0.92
			)
			_rename_input.call_deferred("grab_focus")
		ACTION_DELETE:
			_delete_dialog.dialog_text = (
				"Vuoi eliminare definitivamente lo scenario \"%s\"?\n"
				+ "Il salvataggio non potrà essere recuperato."
			) % _pending_scenario_name
			_delete_dialog.reset_size()
			_delete_dialog.popup_centered_clamped(
				Vector2i(460, 200),
				0.92
			)


func _confirm_rename() -> void:
	var new_name: String = _rename_input.text.strip_edges()
	if new_name.is_empty():
		_set_status("Il nome dello scenario non può essere vuoto.")
		return

	var manager: Node = _campaign_manager()
	if manager == null:
		return
	var error: Error = int(manager.call(
		"rename_campaign",
		_pending_scenario_id,
		new_name
	))
	if error != OK:
		_set_status("Errore rinomina: %s" % error_string(error))
		return
	get_tree().reload_current_scene()


func _confirm_delete() -> void:
	var manager: Node = _campaign_manager()
	if manager == null:
		return
	var error: Error = int(manager.call(
		"delete_campaign",
		_pending_scenario_id
	))
	if error != OK:
		_set_status("Errore eliminazione: %s" % error_string(error))
		return
	get_tree().reload_current_scene()


func _open_scenario(scenario_id: String) -> void:
	var manager: Node = _campaign_manager()
	if manager == null:
		_set_status("CampaignManager non disponibile.")
		return
	var error: Error = int(manager.call(
		"open_scenario",
		_campaign_group_id,
		scenario_id
	))
	if error != OK:
		_set_status(
			"Errore apertura scenario: %s"
			% error_string(error)
		)


func _campaign_manager() -> Node:
	var manager: Node = get_node_or_null("/root/CampaignManager")
	if manager == null:
		push_error("CampaignManager autoload non disponibile.")
	return manager


func _list_scenarios() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var manager: Node = _campaign_manager()
	if manager == null:
		return result

	var value: Variant = manager.call(
		"list_campaign_scenarios",
		_campaign_group_id
	)
	if value is Array:
		for item: Variant in value:
			if item is Dictionary:
				result.append((item as Dictionary).duplicate(true))
	return result


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
