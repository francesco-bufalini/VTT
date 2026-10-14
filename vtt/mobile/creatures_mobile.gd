extends "res://vtt/standalone/creatures_standalone.gd"
## Touch shell for the current shared sheets, compendium and offline dice.
const SessionActions = preload("res://vtt/mobile/session_actions.gd")
var _session_actions: SessionActions
const MapController = preload("res://vtt/map_data_controller.gd")
const TouchLayout = preload("res://vtt/mobile/touch_layout.gd")
const FormulaValue = preload("res://vtt/formula_value.gd")
var map_data_controller: MapController
var _session_panel: PanelContainer
const Presence = preload("res://network/creature_presence.gd")
var _presence: Presence
var _session_picker: OptionButton
var _host_input: LineEdit
var _peer_list: VBoxContainer
var _exit_dialog: ConfirmationDialog
var _page_history: Array[int] = []
var _back_navigation := false
var _finger := -1
var _finger_start := Vector2.ZERO
var _finger_position := Vector2.ZERO
var _dragging := false
var _finger_started_msec := 0
var _help_panel: PanelContainer
var _help_text: RichTextLabel
var _help_close_button: Button
var _help_actions: HBoxContainer
var _help_edit_button: Button
var _help_bonus_button: Button
var _help_roll_button: Button
var _help_formula: Node
var _gesture_bars: Array[ScrollBar] = []
var _previous_mouse_emulation := true
var _previous_tooltip_delay := 0.5
var _last_back_msec := -1000
var _choice_panel: PanelContainer
var _choice_list: VBoxContainer
var _choice_filter: LineEdit
var _choice_owner_window: Window
var _connection_status: Label
var _map_summary: RichTextLabel
var _pages: Array[Control] = []
var _navigation_buttons: Array[Button] = []
var _page_drawer: PanelContainer
var _page_menu_button: Button
var _page_header_row: HBoxContainer
var _page_header: PanelContainer
var _page_header_contents: VBoxContainer
var _archive_selector: OptionButton
var _active_page := -1

# Embedded windows own their input viewport. Forward raw touch back to the
# same gesture dispatcher, translating its coordinates into the main viewport.
class WindowTouchRelay:
	extends Node
	var mobile: Node
	func _input(event: InputEvent) -> void:
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			var forwarded: InputEvent = event.duplicate()
			forwarded.position += Vector2(get_window().position)
			get_viewport().set_input_as_handled()
			mobile._input(forwarded)

func _install_window_touch(window: Window) -> void:
	if window is PopupMenu or window.has_node("MobileTouchRelay"):
		return
	var relay := WindowTouchRelay.new()
	relay.name = "MobileTouchRelay"
	relay.mobile = self
	window.add_child(relay)

func _enter_tree() -> void:
	get_tree().quit_on_go_back = false
	get_tree().root.set_meta("vtt_touch_layout", true)

func _ready() -> void:
	_configure_ui_scale()
	get_tree().quit_on_go_back = false
	get_tree().auto_accept_quit = false
	get_viewport().gui_embed_subwindows = true
	_previous_tooltip_delay = float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5))
	ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", 86400.0)
	_previous_mouse_emulation = Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = false
	if OS.has_feature("mobile"):
		get_window().size_changed.connect(_configure_ui_scale)
		get_tree().auto_accept_quit = false
	map_data_controller = MapController.new()
	map_data_controller.name = "MapDataController"
	add_child(map_data_controller)
	var manager := get_node("/root/CampaignManager")
	manager.selected_campaign_group_id = ""
	manager.active_campaign_id = ""
	super._ready()
	var sheet := creature_area as CreatureSheet
	var book := compendium as Compendium
	var roller := dice_roller as DiceRoller
	sheet.set_map_data_controller(map_data_controller)
	sheet.configure_touch_layout()
	book.configure_touch_layout()
	roller.configure_touch_layout()
	_build_choice_picker()
	_build_touch_help()
	_build_session_panel()
	roller.configure_mobile_connection(map_data_controller, Callable(sheet, "get_mobile_roll_creatures"), Callable(sheet, "_current"))

	_build_page_header()
	_build_archive_selector()
	_install_unified_sections(sheet)
	TouchLayout.scroll_body(_session_panel)
	TouchLayout.style_tree(_session_panel)

	_pages.assign([sheet.get_panel_control(), book.get_panel_control(), roller.panel, _session_panel])
	map_data_controller.status_changed.connect(func(message: String) -> void:
		_connection_status.text = message)
	map_data_controller.data_changed.connect(_show_map_data)
	resized.connect(_layout_pages)
	get_tree().node_added.connect(_on_touch_node_added)
	_select_page(0)
	_exit_dialog = ConfirmationDialog.new()
	_exit_dialog.title = "Uscire dall'app?"
	_exit_dialog.dialog_text = "Vuoi chiudere VTT Mobile? Le schede restano salvate sul dispositivo."
	_exit_dialog.ok_button_text = "Esci"
	_exit_dialog.cancel_button_text = "Resta nell'app"
	_exit_dialog.confirmed.connect(func() -> void: get_tree().quit())
	ui_root.add_child(_exit_dialog)
	TouchLayout.fit_dialog(_exit_dialog)
	for node: Node in ui_root.find_children("*", "Window", true, false):
		_install_window_touch(node as Window)
		if node is AcceptDialog:
			node.about_to_popup.connect(_fit_touch_dialog.bind(node))
	_presence = Presence.new()
	_presence.name = "CreaturePresence"
	_presence.auto_refresh = true
	add_child(_presence)
	_presence.peers_changed.connect(_show_online_peers)
	_presence.setup("1", _discovery_hosts)
	_presence.request_refresh()

func _fit_touch_dialog(dialog: AcceptDialog) -> void:
	TouchLayout.fit_dialog(dialog)
	for button: Button in [dialog.get_ok_button(), dialog.get_cancel_button() if dialog is ConfirmationDialog else null]:
		if button != null:
			button.clip_text = false
			button.custom_minimum_size.x = 120
	var viewport_size := get_viewport_rect().size
	dialog.size = Vector2i(minf(dialog.size.x, viewport_size.x - 16), minf(dialog.size.y, viewport_size.y - 48))

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

# The single drawer lives in the sheet and includes its tabs plus the
# standalone catalog, roller and session. No second global navigation menu.
func _build_navigation() -> void:
	pass

func _install_unified_sections(sheet: CreatureSheet) -> void:
	_page_drawer = sheet._touch_section_drawer
	_page_drawer.name = "MobileSectionsDrawer"
	var sections := _page_drawer.find_child("TouchSheetSections", true, false) as VBoxContainer
	for index: int in range(sheet._touch_section_buttons.size()):
		sheet._touch_section_buttons[index].pressed.connect(_open_sheet_section.bind(index))
	var subtitle := Label.new()
	subtitle.text = "ALTRE SEZIONI"
	sections.add_child(subtitle)
	for index: int in range(1, 4):
		var button := Button.new()
		button.text = ["", "Catalogo", "Dadi", "Partita"][index]
		button.custom_minimum_size.y = 48
		button.pressed.connect(_request_page.bind(index))
		sections.add_child(button)
		_navigation_buttons.append(button)
	TouchLayout.style_tree(_page_drawer)
	# The section title and the existing archive/actions now share ONE header;
	# do not keep the old sheet toolbar consuming another 48 dp underneath.
	var toolbar := (sheet._panel.get_child(0) as VBoxContainer).get_child(0) as HBoxContainer
	var library := Button.new()
	library.text = "Creature locali"
	library.pressed.connect(func() -> void:
		_page_drawer.hide()
		_select_page(0)
		sheet.show_touch_library(true))
	sections.add_child(library)
	sheet._options_menu.hide()
	var transfer_index := sheet._creature_context_menu.get_item_index(4)
	if transfer_index >= 0:
		sheet._creature_context_menu.remove_item(transfer_index)
	toolbar.hide()

func _open_sheet_section(index: int) -> void:
	_page_drawer.hide()
	_select_page(0)
	var sheet := creature_area as CreatureSheet
	sheet.show_touch_library(false)
	sheet._apply_touch_section.call_deferred(index)

func _request_page(index: int) -> void:
	# Let the touch release finish before hiding a drawer button.
	_select_page.call_deferred(index)


func _build_page_header() -> void:
	_page_menu_button = Button.new()
	_page_menu_button.name = "MobilePageMenu"
	_page_menu_button.text = "☰"
	_page_menu_button.tooltip_text = "Apri le sezioni"
	_page_menu_button.position = Vector2(2, 2)
	_page_menu_button.custom_minimum_size = Vector2(48, 48)
	_page_menu_button.z_index = 100
	_page_menu_button.pressed.connect(func() -> void:
		_page_drawer.visible = not _page_drawer.visible)
	ui_root.add_child(_page_menu_button)

func _select_page(index: int) -> void:
	if _pages.is_empty() or index == _active_page:
		return
	if _active_page >= 0 and not _back_navigation:
		_page_history.append(_active_page)
	var sheet := creature_area as CreatureSheet
	var book := compendium as Compendium
	var roller := dice_roller as DiceRoller
	_page_drawer.hide()
	sheet.close_touch_section_drawer()
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
	for i: int in range(_navigation_buttons.size()):
		_navigation_buttons[i].set_pressed_no_signal(i + 1 == index)

	_layout_pages()

func _layout_pages() -> void:
	# Floating controls share the side of the screen without reserving a column.
	if _page_menu_button != null:
		_page_menu_button.position = Vector2(2, maxf(2, get_viewport_rect().size.y * 0.5 - 50))
	if _session_actions != null:
		_session_actions.reopen_button.position = _page_menu_button.position + Vector2(0, 54)
	var header_height := 0.0
	if _page_header != null:
		header_height = maxf(header_height, _page_header.get_combined_minimum_size().y)
		_page_header.offset_bottom = header_height
	if _page_drawer != null:
		_page_drawer.offset_top = header_height + 6.0
	for index: int in range(_pages.size()):
		var page := _pages[index]
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.offset_left = 2
		page.offset_right = -2
		page.offset_top = header_height + 6.0
		page.offset_bottom = -2

func _on_touch_node_added(node: Node) -> void:
	if is_ancestor_of(node):
		call_deferred("_style_added_control", weakref(node))

func _style_added_control(reference: WeakRef) -> void:
	var node: Node = reference.get_ref()
	if is_instance_valid(node) and not node.is_queued_for_deletion():
		TouchLayout.style_control(node)
		if node is Window:
			_install_window_touch(node as Window)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST] and _active_page >= 0:
		_request_go_back()

func _request_go_back() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_back_msec < 250:
		return
	_last_back_msec = now
	_go_back()

func _go_back() -> void:
	if _help_panel != null and _help_panel.visible:
		_help_panel.hide()
		return
	if _choice_panel != null and _choice_panel.visible:
		_close_touch_choices()
		return
	if _session_actions != null and _session_actions.close_overlay():
		return
	if _page_drawer != null and _page_drawer.visible:
		_page_drawer.hide()
		return
	if _active_page == 0 and (creature_area as CreatureSheet).close_touch_section_drawer():
		return
	# Close the current popup before changing the screen underneath it.
	var windows := ui_root.find_children("*", "Window", true, false)
	for index: int in range(windows.size() - 1, -1, -1):
		var popup := windows[index] as Window
		if popup.visible:
			popup.hide()
			return
	if _active_page == 1 and (compendium as Compendium).close_touch_details():
		return
	var sheet := creature_area as CreatureSheet
	if _active_page == 0 and not sheet.is_touch_library_visible():
		sheet.show_touch_library(true)
		return
	if not _page_history.is_empty():
		_back_navigation = true
		_select_page(_page_history.pop_back())
		_back_navigation = false
		return
	_exit_dialog.popup_centered_clamped(Vector2i(340, 180), 0.9)

func _input(event: InputEvent) -> void:
	if _session_actions != null and _session_actions.handle_snapshot_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_BACK:
		get_viewport().set_input_as_handled()
		_request_go_back()
	elif event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
		if event.pressed and _finger == -1:
			_finger = event.index
			_finger_started_msec = Time.get_ticks_msec()
			_finger_start = event.position
			_finger_position = event.position
			_dragging = false
			_gesture_bars = _touch_scroll_bars(event.position)
		elif not event.pressed and event.index == _finger:
			var tap: bool = not _dragging and not event.canceled
			_finger = -1
			_gesture_bars.clear()
			if tap:
				if _help_panel != null and _help_panel.visible:
					# ScreenTouch input is consumed above, so a synthetic mouse click
					# is not reliable for an overlay button. Dispatch it directly.
					for action: Button in [_help_close_button, _help_edit_button, _help_bonus_button, _help_roll_button]:
						if action != null and action.visible and action.get_global_rect().has_point(event.position):
							action.pressed.emit()
							break
				elif Time.get_ticks_msec() - _finger_started_msec >= 550:
					call_deferred("_explain_touch", event.position)
				else:
					_dispatch_touch_tap(event.position)
	elif event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		if event.index != _finger:
			return
		if not _dragging and event.position.distance_to(_finger_start) >= 10:
			_dragging = true
		if _dragging:
			TouchLayout.scroll_gesture(_gesture_bars, _finger_position.y - event.position.y)
		_finger_position = event.position

func _touch_scroll_bars(at: Vector2) -> Array[ScrollBar]:
	var scroll_root: Node = ui_root
	var point := at
	for node: Node in ui_root.find_children("*", "Window", true, false):
		var window := node as Window
		if window.visible and not window is PopupMenu:
			scroll_root = window
			point = at - Vector2(window.position)
	return TouchLayout.scroll_bars_at(scroll_root, point)

func _touch_modal_root() -> Control:
	if _help_panel.visible:
		return _help_panel
	if _choice_panel.visible:
		return _choice_panel
	if _session_actions != null:
		if _session_actions.picker.visible:
			return _session_actions.picker
		if _session_actions.viewer.visible:
			return _session_actions.viewer
	if _page_drawer.visible:
		return _page_drawer
	return null

func _dispatch_touch_tap(at: Vector2) -> void:
	# Resolve buttons in the active embedded window directly. Its viewport
	# uses window-local coordinates; root synthetic clicks can miss Cancel.
	var active_window: Window = get_window()
	for node: Node in ui_root.find_children("*", "Window", true, false):
		var popup := node as Window
		if popup.visible and not popup is PopupMenu:
			active_window = popup
	var point := at
	if active_window != get_window():
		point -= Vector2(active_window.position)
	var modal: Control = _touch_modal_root() if active_window == get_window() else null
	var buttons: Array[BaseButton] = []
	if active_window is ConfirmationDialog:
		var cancel: Button = active_window.get_cancel_button()
		if not cancel.disabled and cancel.is_visible_in_tree() and cancel.get_global_rect().has_point(point):
			active_window.canceled.emit()
			active_window.hide()
			return
	if active_window is AcceptDialog:
		var accept: Button = active_window.get_ok_button()
		if not accept.disabled and accept.is_visible_in_tree() and accept.get_global_rect().has_point(point):
			accept.pressed.emit()
			return
	for node: Node in active_window.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if modal != null and not modal.is_ancestor_of(button):
			continue
		if button.get_window() != active_window or not button.is_visible_in_tree() or button.disabled:
			continue
		if not button.get_global_rect().has_point(point):
			continue
		var parent := button.get_parent()
		var clipped := false
		while parent is Control:
			if parent.clip_contents and not parent.get_global_rect().has_point(point):
				clipped = true
				break
			parent = parent.get_parent()
		if not clipped:
			buttons.append(button)
	buttons.sort_custom(func(a: BaseButton, b: BaseButton) -> bool:
		return TouchLayout._effective_z(a) > TouchLayout._effective_z(b))
	if not buttons.is_empty():
		var button := buttons[0]
		if button is OptionButton:
			_show_touch_choices(button.get_popup(), button)
		elif button is MenuButton:
			_show_touch_choices(button.get_popup())
		else:
			if button.toggle_mode:
				button.button_pressed = not button.button_pressed
			button.pressed.emit()
		return
	var fields: Array[Control] = []
	for node: Node in active_window.find_children("*", "Control", true, false):
		if not (node is LineEdit or node is ItemList):
			continue
		var control := node as Control
		if modal != null and not modal.is_ancestor_of(control):
			continue
		if control.get_window() != active_window or not control.is_visible_in_tree() or not control.get_global_rect().has_point(point):
			continue
		var ancestor := control.get_parent()
		var clipped := false
		while ancestor is Control:
			if ancestor.clip_contents and not ancestor.get_global_rect().has_point(point):
				clipped = true
				break
			ancestor = ancestor.get_parent()
		if not clipped:
			fields.append(control)
	fields.sort_custom(func(a: Control, b: Control) -> bool:
		return TouchLayout._effective_z(a) > TouchLayout._effective_z(b))
	if not fields.is_empty():
		active_window.grab_focus()
		var control := fields[0]
		if control is LineEdit and control.editable:
			control.grab_focus()
			if control.clear_button_enabled and point.x >= control.get_global_rect().end.x - 32 and not control.text.is_empty():
				control.clear()
				control.text_changed.emit("")
			control.caret_column = control.text.length()
			if control.virtual_keyboard_enabled and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
				DisplayServer.virtual_keyboard_show(control.text, Rect2(), control.virtual_keyboard_type, control.max_length, control.caret_column, control.caret_column)
			return
		if control is ItemList:
			var index: int = control.get_item_at_position(point - control.global_position, true)
			if index >= 0 and control.is_item_selectable(index) and not control.is_item_disabled(index):
				control.select(index)
				control.item_selected.emit(index)
			return
	# Embedded fields and ItemLists need events in their own viewport,
	# including local coordinates for focus, keyboard and row selection.
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = at
	active_window.push_input(motion, true)
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = at
		click.button_index = MOUSE_BUTTON_LEFT
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		click.pressed = pressed
		active_window.push_input(click, true)
	var leave := InputEventMouseMotion.new()
	leave.position = Vector2(-100, -100)
	leave.global_position = leave.position
	active_window.push_input(leave, true)

func _exit_tree() -> void:
	Input.emulate_mouse_from_touch = _previous_mouse_emulation
	ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", _previous_tooltip_delay)
	get_tree().root.remove_meta("vtt_touch_layout")

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
	var session_row := HBoxContainer.new()
	column.add_child(session_row)
	var session_label := Label.new()
	session_label.text = "Partita"
	session_row.add_child(session_label)
	_session_picker = OptionButton.new()
	_session_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for number: int in range(1, 6):
		_session_picker.add_item("Partita %d%s" % [number, " · predefinita" if number == 1 else ""])
	_session_picker.item_selected.connect(func(index: int) -> void:
		map_data_controller.disconnect_remote()
		_presence.set_session_key(str(index + 1))
		dice_roller.set_session_key(str(index + 1))
		_refresh_online_peers())
	session_row.add_child(_session_picker)
	var refresh := Button.new()
	refresh.text = "Aggiorna utenti online"
	refresh.pressed.connect(_refresh_online_peers)
	column.add_child(refresh)
	var direct_row := HBoxContainer.new()
	column.add_child(direct_row)
	_host_input = LineEdit.new()
	_host_input.placeholder_text = "IP desktop · emulatore: 10.0.2.2"
	_host_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_input.text_submitted.connect(func(_text: String) -> void: _connect_host_address())
	direct_row.add_child(_host_input)
	var direct_button := Button.new()
	direct_button.text = "Collega IP"
	direct_button.pressed.connect(_connect_host_address)
	direct_row.add_child(direct_button)
	_peer_list = VBoxContainer.new()
	column.add_child(_peer_list)
	var hint := Label.new()
	hint.text = "Con lo stesso numero di partita, scegli un desktop sulla rete locale o via Tailscale. Se non appare, inserisci il suo IPv4. Nell'emulatore Android sullo stesso PC usa 10.0.2.2."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
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
	_session_actions = SessionActions.new()
	add_child(_session_actions)
	_session_actions.setup(self, map_data_controller, creature_area, column)
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
# The storage selector belongs to the sheet header, on its own line.
# It does not overlap the sheet or crowd the permanent navigation buttons.
func _build_archive_selector() -> void:
	pass


func _discovery_hosts() -> Array[String]:
	var known: Array[String] = []
	if _host_input != null:
		var manual_ip := _host_input.text.strip_edges()
		if manual_ip.is_valid_ip_address() and not manual_ip.contains(":"):
			known.append(manual_ip)
	for peer: Dictionary in _presence.get_online_peers():
		known.append(String(peer.get("ip", "")))
	return Presence.discovery_targets(known)


func _connect_host_address() -> void:
	var host := _host_input.text.strip_edges()
	if not host.is_valid_ip_address() or host.contains(":"):
		_connection_status.text = "Inserisci un indirizzo IPv4 valido del desktop"
		return
	var error := map_data_controller.connect_remote(host, str(_session_picker.selected + 1))
	if error != OK:
		_connection_status.text = "Connessione non avviata: " + error_string(error)
	else:
		_presence.request_refresh()

func _refresh_online_peers() -> void:
	_connection_status.text = "Ricerca degli utenti online…"
	_presence.request_refresh()
	_show_online_peers()

func _show_online_peers() -> void:
	for child: Node in _peer_list.get_children():
		_peer_list.remove_child(child)
		child.queue_free()
	var peers := _presence.get_online_peers()
	for peer: Dictionary in peers:
		var button := Button.new()
		var desktop := String(peer.get("device", "desktop")) == "desktop"
		button.text = "%s · %s" % [peer.get("label", "Giocatore"), "Desktop" if desktop else "Mobile"]
		button.disabled = not desktop
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(func() -> void:
			var error := map_data_controller.connect_remote(String(peer.ip), str(_session_picker.selected + 1))
			if error != OK:
				_connection_status.text = "Connessione non avviata: " + error_string(error))
		_peer_list.add_child(button)
		TouchLayout.style_control(button)
	if peers.is_empty():
		var empty := Label.new()
		empty.text = "Nessun utente trovato. Usa Aggiorna dopo aver aperto VTT sul desktop."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_peer_list.add_child(empty)

func _build_choice_picker() -> void:
	_choice_panel = PanelContainer.new()
	_choice_panel.name = "MobileChoicePicker"
	_choice_panel.z_index = 200
	_choice_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_choice_panel.offset_left = 12
	_choice_panel.offset_right = -12
	_choice_panel.offset_top = 60
	_choice_panel.offset_bottom = -8
	ui_root.add_child(_choice_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_choice_panel.add_child(column)
	var close := Button.new()
	close.text = "Annulla · Torna indietro"
	close.pressed.connect(_close_touch_choices)
	column.add_child(close)
	_choice_filter = LineEdit.new()
	_choice_filter.placeholder_text = "Cerca un'opzione…"
	_choice_filter.text_changed.connect(func(query: String) -> void:
		for row: Button in _choice_list.get_children():
			row.visible = query.is_empty() or row.text.to_lower().contains(query.to_lower()))
	column.add_child(_choice_filter)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_choice_list = VBoxContainer.new()
	_choice_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_choice_list)
	TouchLayout.style_tree(_choice_panel)
	_choice_panel.hide()

func _show_touch_choices(menu: PopupMenu, option: OptionButton = null) -> void:
	var owner_node: Node = option if option != null else menu.get_parent()
	var owner_window := owner_node.get_window()
	if owner_window != get_window() and not owner_window is PopupMenu:
		_choice_owner_window = owner_window
		owner_window.hide()
	# Do not open an embedded native Window while dispatching synthetic input.
	_choice_filter.clear()
	for child: Node in _choice_list.get_children():
		_choice_list.remove_child(child)
		child.queue_free()
	for index: int in range(menu.item_count):
		if menu.is_item_separator(index):
			continue
		var row := Button.new()
		row.text = menu.get_item_text(index)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if option != null:
			row.text = ("● " if option.selected == index else "○ ") + row.text
		elif menu.is_item_checkable(index) or menu.is_item_radio_checkable(index):
			row.text = ("● " if menu.is_item_checked(index) else "○ ") + row.text
		row.disabled = menu.is_item_disabled(index)
		row.pressed.connect(_choose_touch_option.bind(menu, option, index))
		_choice_list.add_child(row)
		TouchLayout.style_control(row)
	_choice_panel.show()

func _choose_touch_option(menu: PopupMenu, option: OptionButton, index: int) -> void:
	if not is_instance_valid(menu) or index < 0 or index >= menu.item_count or menu.is_item_disabled(index):
		return
	var submenu := String(menu.get_item_submenu(index))
	if not submenu.is_empty():
		var nested := menu.get_node_or_null(submenu) as PopupMenu
		if nested != null:
			_show_touch_choices(nested)
		return
	_close_touch_choices()
	if is_instance_valid(option):
		option.select(index)
		option.item_selected.emit(index)
	else:
		menu.id_pressed.emit(menu.get_item_id(index))
		menu.index_pressed.emit(index)

func show_touch_popup(menu: PopupMenu) -> void:
	_show_touch_choices(menu)

func _close_touch_choices() -> void:
	_choice_panel.hide()
	if is_instance_valid(_choice_owner_window):
		_choice_owner_window.show()
	_choice_owner_window = null

func _build_touch_help() -> void:
	_help_panel = PanelContainer.new()
	_help_panel.name = "TouchHelp"
	_help_panel.z_index = 250
	ui_root.add_child(_help_panel)
	_help_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help_panel.offset_left = 8
	_help_panel.offset_right = -8
	_help_panel.offset_top = 48
	_help_panel.offset_bottom = -8
	var column := VBoxContainer.new()
	_help_panel.add_child(column)
	_help_close_button = Button.new()
	_help_close_button.text = "Chiudi spiegazione"
	_help_close_button.pressed.connect(_close_touch_help)
	column.add_child(_help_close_button)
	_help_actions = HBoxContainer.new()
	_help_actions.add_theme_constant_override("separation", 6)
	column.add_child(_help_actions)
	_help_edit_button = Button.new()
	_help_edit_button.text = "Modifica"
	_help_edit_button.tooltip_text = "Modifica i valori di base"
	_help_edit_button.pressed.connect(_touch_formula_action.bind("edit"))
	_help_actions.add_child(_help_edit_button)
	_help_bonus_button = Button.new()
	_help_bonus_button.text = "Bonus"
	_help_bonus_button.tooltip_text = "Gestisci bonus e origini"
	_help_bonus_button.pressed.connect(_touch_formula_action.bind("bonus"))
	_help_actions.add_child(_help_bonus_button)
	_help_roll_button = Button.new()
	_help_roll_button.text = "Tira"
	_help_roll_button.tooltip_text = "Esegui il tiro"
	_help_roll_button.pressed.connect(_touch_formula_action.bind("roll"))
	_help_actions.add_child(_help_roll_button)
	for action: Button in [_help_edit_button, _help_bonus_button, _help_roll_button]:
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_actions.hide()
	_help_text = RichTextLabel.new()
	_help_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_help_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_text.selection_enabled = true
	column.add_child(_help_text)
	TouchLayout.style_tree(_help_panel)
	_help_panel.hide()

func _close_touch_help() -> void:
	_help_panel.hide()
	_help_formula = null


func _show_touch_help(message: String, formula: Node = null) -> void:
	_help_formula = formula if is_instance_valid(formula) else null
	var display_text := message
	if _help_formula != null:
		# Desktop mouse gestures have accessible on-screen equivalents below.
		display_text = display_text.replace("\nDoppio clic per modificare i valori consentiti.", "")
		display_text = display_text.replace("\nClic destro per gestire i bonus e le loro origini.", "")
		display_text = display_text.replace("\nClic sinistro per tirare nel roller.", "")
		var fields: Variant = _help_formula.get("_fields")
		_help_edit_button.visible = fields is Array and not (fields as Array).is_empty()
		_help_bonus_button.show()
		_help_roll_button.visible = bool(_help_formula.get("roll_on_click"))
		_help_actions.show()
	else:
		_help_actions.hide()
	_help_text.text = display_text
	_help_text.scroll_to_line(0)
	_help_panel.show()


func _touch_formula_action(kind: String) -> void:
	var formula: Node = _help_formula
	_close_touch_help()
	if not is_instance_valid(formula):
		return
	match kind:
		"edit":
			formula.call("open_editor")
		"bonus":
			formula.emit_signal("bonus_requested", String(formula.get("target_key")))
		"roll":
			formula.emit_signal("roll_requested", String(formula.get("target_key")))


func _explain_touch(point: Vector2) -> void:
	var captions := get_tree().root.get_node_or_null("ScrollableCaptions")
	if captions == null:
		return
	var hint: Dictionary = captions.touch_hint_details_at(point)
	var message: String = String(hint.get("text", ""))
	if message.strip_edges().is_empty():
		return
	var target: Node = hint.get("target") as Control
	var formula: Node = null
	while target != null:
		if target is FormulaValue:
			formula = target
			break
		target = target.get_parent()
	_show_touch_help(message, formula)

func list_available_miniatures() -> Array[Dictionary]:
	# Selection stores catalog identities; no 3D scene needs to be loaded on a phone.
	var packs := get_node_or_null("/root/TokenPackManager")
	var result: Array[Dictionary] = []
	if packs != null:
		result.assign(packs.get_entries())
	return result


func show_mobile_attack_range(record: Dictionary, attack: Dictionary) -> void:
	_session_actions.request_attack_snapshot(record, attack)

func start_mobile_spell(record: Dictionary, spell: Dictionary, level: int, context: Dictionary, choice: int) -> bool:
	return _session_actions.begin_mobile_spell(record, spell, level, context, choice)
