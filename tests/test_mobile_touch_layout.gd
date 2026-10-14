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
			if not check(panel.get_global_rect().end.x <= viewport_size.x + 1 and panel.get_global_rect().end.y <= nav.position.y + 1,
				"Panel must not cover navigation at %s, page %d: %s" % [viewport_size, page, panel.get_global_rect()]):
				return
			if not check(mobile._archive_selector.visible == (page == 0), "Archive picker must belong only to sheets"):
				return
			for button: Button in mobile._navigation_buttons:
				if not check(button.size.y >= 48, "Navigation must offer finger-sized targets"):
					return
		mobile._select_page(0)
		sheet.show_touch_library(false)
		for index: int in range(sheet._tabs.get_tab_count()):
			sheet._touch_section.item_selected.emit(index)
			await settle()
			if not check(sheet._tabs.current_tab == index, "Touch picker must select each real shared tab"):
				return
		if not check(sheet._name.custom_minimum_size.y >= 48 and sheet._rules_edition.custom_minimum_size.y >= 48,
			"Shared edit fields must be usable by touch"):
			return
		sheet.show_touch_library(true)
	mobile.queue_free()
	await settle()
	manager.selected_campaign_group_id = previous_campaign
	manager.active_campaign_id = previous_scenario
	print("PASS: touch page bounds, exclusive navigation, current sheet tabs, portrait/landscape and shared controls")
	quit()
