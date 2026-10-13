extends "res://vtt/standalone/creatures_standalone.gd"
## Mobile-only navigation and remote-session controls; sheet rules stay shared.
const MapController = preload("res://vtt/map_data_controller.gd")
var map_data_controller: MapController
var _session_panel: PanelContainer
var _host_input: LineEdit
var _session_input: LineEdit
var _connection_status: Label
var _map_summary: RichTextLabel
var _archive_selector: OptionButton

func _ready() -> void:
	map_data_controller = MapController.new()
	map_data_controller.name = "MapDataController"
	add_child(map_data_controller)
	super._ready()
	creature_area.call("set_map_data_controller", map_data_controller)
	_build_session_panel()
	_build_archive_selector()
	(ui_root.get_node("CreatureSheet") as Control).offset_top = 104
	map_data_controller.status_changed.connect(func(message: String) -> void: _connection_status.text = message)
	map_data_controller.data_changed.connect(_show_map_data)

func _build_navigation() -> void:
	super._build_navigation()
	var navigation := ui_root.get_node("StandaloneNavigation") as HBoxContainer
	navigation.z_index = 40
	for child: Node in navigation.get_children():
		(child as Control).custom_minimum_size.y = 48
		(child as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var button := Button.new()
	button.text = "Partita"
	button.custom_minimum_size.y = 48
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void: _session_panel.visible = not _session_panel.visible)
	navigation.add_child(button)

func _build_session_panel() -> void:
	_session_panel = PanelContainer.new()
	_session_panel.name = "MobileSession"
	_session_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_session_panel.offset_top = 104
	_session_panel.z_index = 40
	ui_root.add_child(_session_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_session_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "Collega le schede alla partita"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(heading)
	_host_input = LineEdit.new()
	_host_input.placeholder_text = "Indirizzo Tailscale del VTT desktop"
	_host_input.custom_minimum_size.y = 48
	column.add_child(_host_input)
	_session_input = LineEdit.new()
	_session_input.placeholder_text = "Codice sessione della board"
	_session_input.custom_minimum_size.y = 48
	column.add_child(_session_input)
	var connect_button := Button.new()
	connect_button.text = "Connetti"
	connect_button.custom_minimum_size.y = 48
	connect_button.pressed.connect(func() -> void:
		var error := map_data_controller.connect_remote(_host_input.text.strip_edges(), _session_input.text)
		if error != OK:
			_connection_status.text = "Connessione non avviata: " + error_string(error)
	)
	column.add_child(connect_button)
	var disconnect_button := Button.new()
	disconnect_button.text = "Disconnetti"
	disconnect_button.custom_minimum_size.y = 48
	disconnect_button.pressed.connect(func() -> void:
		map_data_controller.disconnect_remote()
		_connection_status.text = "Schede offline"
	)
	column.add_child(disconnect_button)
	_connection_status = Label.new()
	_connection_status.text = "Schede offline"
	_connection_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_connection_status)
	_map_summary = RichTextLabel.new()
	_map_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_map_summary)
	var close_button := Button.new()
	close_button.text = "Torna alle schede"
	close_button.custom_minimum_size.y = 48
	close_button.pressed.connect(func() -> void: _session_panel.hide())
	column.add_child(close_button)
	_session_panel.hide()

func _show_map_data(data: Dictionary) -> void:
	_map_summary.clear()
	if data.is_empty():
		return
	var combat: Dictionary = data.get("combat", {})
	_map_summary.add_text("Combattimento: %s · Round %d\n" % ["attivo" if combat.get("active", false) else "inattivo", int(combat.get("round", 1))])
	var index := 0
	for entry: Dictionary in combat.get("entries", []):
		_map_summary.add_text("%s%s · %d\n" % ["→ " if index == int(combat.get("active_index", -1)) else "", entry.get("name", ""), int(entry.get("initiative", 0))])
		index += 1
	_map_summary.add_text("\nToken sulla mappa\n")
	for token: Dictionary in data.get("tokens", []):
		_map_summary.add_text("%s: %s\n" % [token.name, ", ".join(token.conditions)])
# Select the same local storage scope used by desktop, without opening a board.
func _build_archive_selector() -> void:
	_archive_selector = OptionButton.new()
	_archive_selector.name = "LocalCreatureArchive"
	_archive_selector.z_index = 31
	_archive_selector.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_archive_selector.offset_top = 50
	_archive_selector.offset_bottom = 98
	_archive_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ui_root.add_child(_archive_selector)
	_archive_selector.add_item("Creature locali · Generale")
	_archive_selector.set_item_metadata(0, {"campaign": "", "scenario": ""})
	var manager := get_node("/root/CampaignManager")
	for group: Dictionary in manager.list_campaign_groups():
		_archive_selector.add_item("Campagna · " + String(group.get("name", "")))
		_archive_selector.set_item_metadata(_archive_selector.item_count - 1, {"campaign": String(group.id), "scenario": ""})
	for scenario: Dictionary in manager.list_campaigns():
		_archive_selector.add_item("Scenario · " + String(scenario.get("name", "")))
		_archive_selector.set_item_metadata(_archive_selector.item_count - 1, {"campaign": "", "scenario": String(scenario.id)})
	for index in range(_archive_selector.item_count):
		var scope: Dictionary = _archive_selector.get_item_metadata(index)
		if scope.campaign == manager.selected_campaign_group_id and (not scope.campaign.is_empty() or scope.scenario == manager.active_campaign_id):
			_archive_selector.select(index)
			break
	_archive_selector.item_selected.connect(_select_local_archive)

func _select_local_archive(index: int) -> void:
	var was_open: bool = creature_area.is_panel_open()
	# Save under the old scope before changing it; do not copy or migrate files.
	if was_open:
		creature_area.hide_panel()
	var scope: Dictionary = _archive_selector.get_item_metadata(index)
	var manager := get_node("/root/CampaignManager")
	manager.selected_campaign_group_id = String(scope.campaign)
	manager.active_campaign_id = String(scope.scenario)
	if was_open:
		creature_area.show_panel()
