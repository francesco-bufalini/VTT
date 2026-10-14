extends "res://vtt/standalone/creatures_standalone.gd"
## Touch shell for the current shared sheets, compendium and offline dice.
const MapController = preload("res://vtt/map_data_controller.gd")
const TouchLayout = preload("res://vtt/mobile/touch_layout.gd")
var map_data_controller: MapController
var _session_panel: PanelContainer
var _host_input: LineEdit
var _session_input: LineEdit
var _connection_status: Label
var _map_summary: RichTextLabel
var _archive_selector: OptionButton
var _pages: Array[Control] = []
var _navigation_buttons: Array[Button] = []
var _page_title: Label
var _connection_badge: Label
var _active_page := -1

func _ready() -> void:
	_configure_ui_scale()
	if OS.has_feature("mobile"):
		get_window().size_changed.connect(_configure_ui_scale)
		get_tree().auto_accept_quit = false
	map_data_controller = MapController.new()
	map_data_controller.name = "MapDataController"
	add_child(map_data_controller)
	super._ready()
	var sheet := creature_area as CreatureSheet
	var book := compendium as Compendium
	var roller := dice_roller as DiceRoller
	sheet.set_map_data_controller(map_data_controller)
	sheet.configure_touch_layout()
	book.configure_touch_layout()
	roller.configure_touch_layout()
	_build_session_panel()
	_build_archive_selector()
	_build_page_header()
	TouchLayout.scroll_body(_session_panel)
	TouchLayout.style_tree(_session_panel)
	TouchLayout.style_control(_archive_selector)
	_host_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	_session_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_pages.assign([sheet.get_panel_control(), book.get_panel_control(), roller.panel, _session_panel])
	map_data_controller.status_changed.connect(func(message: String) -> void:
		_connection_status.text = message)
	map_data_controller.data_changed.connect(_show_map_data)
	map_data_controller.data_changed.connect(func(data: Dictionary) -> void:
		_connection_badge.text = "Offline" if data.is_empty() else "Collegato")
	resized.connect(_layout_pages)
	get_tree().node_added.connect(_on_touch_node_added)
	_select_page(0)

func _configure_ui_scale() -> void:
	if not OS.has_feature("mobile"):
		return
	var window := get_window()
	var physical := window.size
	if physical.x <= 0 or physical.y <= 0:
		return
	# Use Android display density so targets measure 48 dp, including HD phones.
	var dpi := DisplayServer.screen_get_dpi()
	var factor := 160.0 / float(dpi) if dpi >= 120 else 400.0 / float(mini(physical.x, physical.y))
	var logical := Vector2i(roundi(physical.x * factor), roundi(physical.y * factor))
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if window.content_scale_size != logical:
		window.content_scale_size = logical

func _build_navigation() -> void:
	var navigation := HBoxContainer.new()
	navigation.name = "StandaloneNavigation"
	navigation.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	navigation.offset_left = 8
	navigation.offset_right = -8
	navigation.offset_top = -72
	navigation.offset_bottom = -8
	navigation.z_index = 50
	navigation.add_theme_constant_override("separation", 4)
	ui_root.add_child(navigation)
	var group := ButtonGroup.new()
	for index: int in range(4):
		var button := Button.new()
		button.text = ["Schede", "Catalogo", "Dadi", "Partita"][index]
		button.custom_minimum_size.y = 56
		button.add_theme_font_size_override("font_size", 16)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(_select_page.bind(index))
		navigation.add_child(button)
		_navigation_buttons.append(button)

func _build_page_header() -> void:
	var header := PanelContainer.new()
	header.name = "MobilePageHeader"
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 52
	header.z_index = 40
	ui_root.add_child(header)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	header.add_child(margin)
	var row := HBoxContainer.new()
	margin.add_child(row)
	_page_title = Label.new()
	_page_title.add_theme_font_size_override("font_size", 22)
	_page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_page_title)
	_connection_badge = Label.new()
	_connection_badge.text = "Offline"
	_connection_badge.add_theme_font_size_override("font_size", 16)
	row.add_child(_connection_badge)

func _select_page(index: int) -> void:
	if _pages.is_empty() or index == _active_page:
		return
	var sheet := creature_area as CreatureSheet
	var book := compendium as Compendium
	var roller := dice_roller as DiceRoller
	if sheet.is_panel_open() and index != 0:
		sheet.hide_panel()
	if index != 1:
		book.hide_panel()
	if index != 2:
		roller.hide_panel()
	if index != 3:
		_session_panel.hide()
	_active_page = index
	match index:
		0: sheet.show_panel()
		1: book.show_panel()
		2: roller.show_panel()
		3: _session_panel.show()
	_navigation_buttons[index].button_pressed = true
	_page_title.text = ["Le mie schede", "Compendio", "Dadi e registro", "La partita"][index]
	_archive_selector.visible = index == 0
	_layout_pages()

func _layout_pages() -> void:
	for index: int in range(_pages.size()):
		var page := _pages[index]
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.offset_left = 8
		page.offset_right = -8
		page.offset_top = 116 if index == 0 else 60
		page.offset_bottom = -80

func _on_touch_node_added(node: Node) -> void:
	if is_ancestor_of(node):
		call_deferred("_style_added_control", weakref(node))

func _style_added_control(reference: WeakRef) -> void:
	var node: Node = reference.get_ref()
	if is_instance_valid(node) and not node.is_queued_for_deletion():
		TouchLayout.style_control(node)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _active_page >= 0:
		if _active_page != 0:
			_select_page(0)
		else:
			(creature_area as CreatureSheet).show_touch_library(true)

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
	close_button.pressed.connect(_select_page.bind(0))
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
	_archive_selector.z_index = 40
	_archive_selector.offset_left = 12
	_archive_selector.offset_right = -12
	_archive_selector.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_archive_selector.offset_top = 60
	_archive_selector.offset_bottom = 108
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
