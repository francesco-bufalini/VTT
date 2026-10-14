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
	if not check(mobile._archive_selector == null and manager.selected_campaign_group_id.is_empty() and manager.active_campaign_id.is_empty(), "Mobile must use the general archive without a picker"):
		return
	if not check(root.find_children("*", "Node3D", true, false).is_empty(), "Mobile must not instantiate a board"):
		return
	if not check(sheet._tabs.get_tab_count() == 8 and not sheet._tabs.tabs_visible,
		"All current sheet tabs must remain accessible through the touch picker"):
		return
	assert(sheet._tabs.get_tab_title(1) == "Caratteristiche e abilità")
	assert(sheet._tabs.get_tab_title(2) == "Battaglia")
	assert(sheet._tabs.get_tab_control(2).is_ancestor_of(sheet._hp))
	assert(not sheet._tabs.get_tab_control(1).is_ancestor_of(sheet._hp))
	assert(sheet._tabs.get_tab_control(2).is_ancestor_of(sheet._attack_rows))
	if not check(sheet._statistics_columns.vertical, "Statistics must stack on mobile"):
		return
	for viewport_size: Vector2i in [Vector2i(360, 640), Vector2i(640, 360), Vector2i(480, 960), Vector2i(960, 480)]:
		root.size = viewport_size
		for page: int in range(4):
			mobile._select_page(page)
			await settle()
			var nav := mobile.ui_root.get_node("MobileSectionsDrawer") as Control
			if not check(nav.get_global_rect().end.x <= viewport_size.x + 1 and nav.get_global_rect().end.y <= viewport_size.y + 1,
				"Unified sections drawer must fit %s: %s" % [viewport_size, nav.get_global_rect()]):
				return
			var visible_pages := 0
			for candidate: Control in mobile._pages:
				visible_pages += int(candidate.visible)
			if not check(visible_pages == 1, "Exactly one mobile page must be visible"):
				return
			var panel := mobile._pages[page] as Control
			if not check(panel.get_global_rect().end.x <= viewport_size.x + 1 and panel.get_global_rect().end.y <= viewport_size.y + 1 and panel.get_global_rect().position.x <= 3,
				"Mobile page must use the full width beneath the floating menu button at %s, page %d: %s" % [viewport_size, page, panel.get_global_rect()]):
				return
			if not check(not sheet._options_menu.is_visible_in_tree(), "Mobile options must be hidden"):
				return
			if not check(not nav.visible, "Sections drawer must be collapsed by default"):
				return
			mobile._page_menu_button.pressed.emit()
			await settle()
			for button: Button in mobile._navigation_buttons:
				if not check(button.size.y >= 48, "Navigation must offer finger-sized targets"):
					return
			mobile._page_drawer.hide()
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
		# Statistics must fit inside their tab even after the touch Condition fixes.
		sheet._tabs.current_tab = 1
		await settle()
		var statistics_bounds: Rect2 = sheet._tabs.get_global_rect()
		for column: Control in sheet._statistics_columns.get_children():
			if not check(column.get_global_rect().end.x <= statistics_bounds.end.x + 3.0,
				"Statistics column must stay inside mobile viewport at %s" % viewport_size):
				return
		if not check(sheet._name.custom_minimum_size.y >= 48 and sheet._rules_edition.custom_minimum_size.y >= 48,
			"Shared edit fields must be usable by touch"):
			return
		var trait_index := -1
		for tab: int in range(sheet._tabs.get_tab_count()):
			if sheet._tabs.get_tab_control(tab).name == "Tratti":
				trait_index = tab
				break
		if not check(trait_index >= 0, "The shared Traits tab must still exist"):
			return
		sheet._tabs.current_tab = trait_index
		await settle()
		var traits: Node = sheet._traits_ui
		if not check(not traits._touch_filters.visible and traits._scroll.size.y > 32,
			"Traits should have a usable scroll area with filters collapsed"):
			return
		traits._touch_filter_toggle.pressed.emit()
		if not check(traits._touch_filters.visible, "Trait filters must open on demand"):
			return
		traits._touch_filter_toggle.pressed.emit()
		sheet.show_touch_library(true)
	# Drive real raw touch events through the viewport: a drag never becomes a click.
	var gesture_scroll := ScrollContainer.new()
	# Keep the gesture fixture clear of the floating navigation icon.
	gesture_scroll.position = Vector2(70, 120)
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
	# Tap a real, fully visible button rather than an assumed coordinate:
	# button positions vary as the responsive theme and font metrics change.
	var target_button := gesture_body.get_child(3) as Button
	var target_center := target_button.get_global_rect().get_center()
	if not check(gesture_scroll.get_global_rect().has_point(target_center),
		"Test target must be visible after scrolling"):
		return
	down.position = target_center
	up.position = target_center
	root.push_input(down, true)
	root.push_input(up, true)
	await settle()
	if not check(clicks[0] == 1, "A stationary tap must click exactly once on release (clicks=%d, target=%s, help=%s, duration=%dms)" % [clicks[0], target_center, mobile._help_panel.visible, Time.get_ticks_msec() - mobile._finger_started_msec]):
		return
	gesture_scroll.queue_free()
	# The long-press help overlay must be dismissible with a real finger tap.
	var formula: Node = null
	for candidate: Variant in sheet._formula_values.values():
		if candidate is Node:
			formula = candidate
			break
	if not check(formula != null, "Statistics must have formula controls for touch help"):
		return
	mobile._show_touch_help("Test formula\nClic destro per gestire i bonus e le loro origini.\nClic sinistro per tirare nel roller.", formula)
	await settle()
	if not check(mobile._help_actions.visible and mobile._help_bonus_button.visible
		and not "Clic destro" in mobile._help_text.text and not "Clic sinistro" in mobile._help_text.text,
		"Formula explanations must use visible touch actions instead of mouse instructions"):
		return
	var help_close_point: Vector2 = mobile._help_close_button.get_global_rect().get_center()
	var help_down := InputEventScreenTouch.new()
	help_down.index = 0
	help_down.position = help_close_point
	help_down.pressed = true
	var help_up := InputEventScreenTouch.new()
	help_up.index = 0
	help_up.position = help_close_point
	root.push_input(help_down, true)
	root.push_input(help_up, true)
	await settle()
	if not check(not mobile._help_panel.visible, "A single touch must close the explanation popup"):
		return
	mobile._page_history.clear()
	mobile._select_page(0)
	sheet.show_touch_library(false)
	sheet._touch_section_toggle.pressed.emit()
	if not check(sheet._touch_section_drawer.visible, "Section toggle must open the unified drawer"):
		return
	mobile._go_back()
	if not check(not sheet._touch_section_drawer.visible and not sheet.is_touch_library_visible(),
		"Android Back must close the section drawer without leaving the editor"):
		return
	mobile._page_menu_button.pressed.emit()
	if not check(mobile._page_drawer.visible, "Page menu must open the unified sections drawer"):
		return
	mobile._go_back()
	if not check(not mobile._page_drawer.visible, "Android Back must close the sections drawer first"):
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
	print("PASS: touch page bounds, unified sections, current sheet tabs, portrait/landscape and shared controls")
	quit()
