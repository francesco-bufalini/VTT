extends SceneTree
const Mobile = preload("res://vtt/mobile/creatures_mobile.tscn")

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		quit(1)
	return value

func settle() -> void:
	for index: int in range(8):
		await process_frame

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.gui_embed_subwindows = true
	var manager := root.get_node("CampaignManager")
	var previous_campaign: String = manager.selected_campaign_group_id
	var previous_scenario: String = manager.active_campaign_id
	# Read an empty temporary scope; never write or delete real creature archives.
	manager.selected_campaign_group_id = "touch_layout_%d" % Time.get_ticks_usec()
	manager.active_campaign_id = ""
	var mobile := Mobile.instantiate()
	root.add_child(mobile)
	await settle()
	if not check(not quit_on_go_back, "Android Back must never automatically quit"):
		return
	var sheet: Node = mobile.creature_area
	if not check(mobile.map_data_controller.source_name() == "offline", "Mobile must start without a network connection"):
		return
	if not check(mobile._archive_selector.item_count >= 1, "The local archive selector must remain available"):
		return
	if not check(root.find_children("*", "Node3D", true, false).is_empty(), "Mobile must not instantiate a board"):
		return
	if not check(sheet._tabs.get_tab_count() == 7 and not sheet._tabs.tabs_visible,
		"All current sheet tabs must remain accessible through the touch picker"):
		return
	if not check(sheet._statistics_columns.vertical, "Statistics must stack on mobile"):
		return
	for viewport_size: Vector2i in [Vector2i(360, 640), Vector2i(640, 360), Vector2i(480, 960), Vector2i(960, 480)]:
		root.size = viewport_size
		for page: int in range(4):
			mobile._select_page(page)
			await settle()
			var nav := mobile.ui_root.get_node("StandaloneNavigation") as Control
			if not check(nav.get_global_rect().end.x <= viewport_size.x + 1 and nav.get_global_rect().end.y <= viewport_size.y + 1,
				"Touch navigation must fit %s: %s" % [viewport_size, nav.get_global_rect()]):
				return
			var visible_pages := 0
			for candidate: Control in mobile._pages:
				visible_pages += int(candidate.visible)
			if not check(visible_pages == 1, "Exactly one mobile page must be visible"):
				return
			var panel := mobile._pages[page] as Control
			if not check(panel.get_global_rect().end.x <= viewport_size.x + 1 and panel.get_global_rect().end.y <= viewport_size.y + 1 and panel.get_global_rect().position.y >= 52,
				"Mobile page must fill the space below the compact header at %s, page %d: %s" % [viewport_size, page, panel.get_global_rect()]):
				return
			if not check(mobile._archive_selector.visible == (page == 0), "Archive picker must belong only to sheets"):
				return
			if not check(not nav.visible, "The global page drawer must be collapsed by default"):
				return
			for button: Button in mobile._navigation_buttons:
				if not check(button.size.y >= 48, "Navigation must offer finger-sized targets"):
					return
		mobile._select_page(0)
		sheet.show_touch_library(false)
		if not check(sheet._touch_library_view != null and not sheet._touch_library_view.visible,
			"Library scroller must be hidden while the editor is open"):
			return
		if not check(sheet._touch_section_drawer != null and not sheet._touch_section_drawer.visible,
			"Sheet section buttons must begin in a collapsed side drawer"):
			return
		if not check(not sheet._panel.has_node("TouchScroll"),
			"Editor must not be wrapped in an outer mobile scroller"):
			return
		for index: int in range(sheet._tabs.get_tab_count()):
			sheet._touch_section_buttons[index].pressed.emit()
			await settle()
			if not check(sheet._tabs.current_tab == index, "Touch picker must select each real shared tab"):
				return
		if not check(sheet._name.custom_minimum_size.y >= 48 and sheet._rules_edition.custom_minimum_size.y >= 48,
			"Shared edit fields must be usable by touch"):
			return
		var traits: Node = sheet._traits_ui
		if not check(not traits._touch_filters.visible and traits._scroll.size.y > 0,
			"Traits should have a usable scroll area with filters collapsed"):
			return
		traits._touch_filter_toggle.pressed.emit()
		if not check(traits._touch_filters.visible, "Trait filters must open on demand"):
			return
		traits._touch_filter_toggle.pressed.emit()
		sheet.show_touch_library(true)
	# Drive real raw touch events through the viewport: a drag never becomes a click.
	var gesture_scroll := ScrollContainer.new()
	gesture_scroll.position = Vector2(20, 120)
	gesture_scroll.size = Vector2(300, 220)
	gesture_scroll.z_index = 100
	mobile.ui_root.add_child(gesture_scroll)
	var gesture_body := VBoxContainer.new()
	gesture_scroll.add_child(gesture_body)
	var clicks := [0]
	for index: int in range(15):
		var button := Button.new()
		button.text = "Touch test %d" % index
		button.custom_minimum_size = Vector2(280, 48)
		button.pressed.connect(func() -> void: clicks[0] += 1)
		gesture_body.add_child(button)
	await settle()
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = Vector2(80, 250)
	down.pressed = true
	root.push_input(down, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(80, 160)
	drag.relative = Vector2(0, -90)
	root.push_input(drag, true)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = drag.position
	root.push_input(up, true)
	await settle()
	if not check(gesture_scroll.scroll_vertical >= 80 and clicks[0] == 0, "Dragging over a button must scroll without clicking: scroll=%d clicks=%d" % [gesture_scroll.scroll_vertical, clicks[0]]):
		return
	down.position = Vector2(80, 190)
	up.position = down.position
	root.push_input(down, true)
	root.push_input(up, true)
	await settle()
	if not check(clicks[0] == 1, "A stationary tap must click exactly once on release"):
		return
	gesture_scroll.queue_free()
	mobile._page_history.clear()
	mobile._select_page(0)
	sheet.show_touch_library(false)
	sheet._touch_section_toggle.pressed.emit()
	if not check(sheet._touch_section_drawer.visible, "Section toggle must open the side drawer"):
		return
	mobile._go_back()
	if not check(not sheet._touch_section_drawer.visible and not sheet.is_touch_library_visible(),
		"Android Back must close the section drawer without leaving the editor"):
		return
	mobile._page_menu_button.pressed.emit()
	if not check(mobile._page_drawer.visible, "Page menu must open the global navigation drawer"):
		return
	mobile._go_back()
	if not check(not mobile._page_drawer.visible, "Android Back must close global navigation first"):
		return
	mobile._select_page(3)
	mobile._go_back()
	if not check(mobile._active_page == 0, "Back must return to the previous page"):
		return
	sheet.show_touch_library(false)
	mobile._go_back()
	if not check(sheet.is_touch_library_visible(), "Back must close the creature editor first"):
		return
	mobile._go_back()
	if not check(mobile._exit_dialog.visible, "Back at the root must ask before exiting"):
		return
	mobile._last_back_msec = -1000
	mobile._request_go_back()
	# A duplicate Android delivery must not reopen/close the warning twice.
	mobile._request_go_back()
	if not check(not mobile._exit_dialog.visible, "Duplicate Back delivery must be ignored"):
		return
	mobile._exit_dialog.hide()
	mobile.queue_free()
	await settle()
	manager.selected_campaign_group_id = previous_campaign
	manager.active_campaign_id = previous_scenario
	print("PASS: touch page bounds, exclusive navigation, current sheet tabs, portrait/landscape and shared controls")
	quit()
