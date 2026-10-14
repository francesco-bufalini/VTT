extends SceneTree
const Mobile = preload("res://vtt/mobile/creatures_mobile.tscn")

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for i: int in range(6):
		await process_frame

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(480, 960)
	var manager := root.get_node("CampaignManager")
	manager.selected_campaign_group_id = "navigation_%d" % Time.get_ticks_usec()
	manager.active_campaign_id = ""
	var mobile := Mobile.instantiate()
	root.add_child(mobile)
	await settle()
	assert(not quit_on_go_back)
	var sheet: Node = mobile.creature_area
	var store = load("res://vtt/player_character_store.gd").new()
	var record: Dictionary = store.create_character()
	record.kind = "character"
	record.name = "Navigation wizard"
	record.classes = [{"name": "Wizard", "level": 5, "source": "PHB"}]
	record.prepared_spells = [{"id": "fireball|phb", "name": "Fireball", "level": 3}]
	sheet._records.assign([record])
	sheet._selected_id = record.id
	sheet._selected_kind = "character"
	sheet._load_form(record)
	sheet.show_touch_library(false)
	await settle()
	for index: int in range(sheet._tabs.get_tab_count()):
		var button := sheet._touch_section_buttons[index] as Button
		var point := button.get_global_rect().get_center()
		var down := InputEventScreenTouch.new()
		down.index = 0
		down.position = point
		down.pressed = true
		var up := InputEventScreenTouch.new()
		up.index = 0
		up.position = point
		root.push_input(down, true)
		root.push_input(up, true)
		await settle()
		assert(sheet._tabs.current_tab == index, "Real tap must change the populated sheet tab")
		assert(not sheet._touch_section.get_popup().visible, "Tab selection must never open a native popup")
		print("PASS: populated sheet touch tab ", index)
	assert(sheet._spellcasting_ui._view._touch_layout)
	for row: BoxContainer in sheet._spellcasting_ui._view._rows:
		assert(row.vertical, "Mobile spells and resources must stack")
	mobile._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	mobile._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert(sheet.is_touch_library_visible() and not mobile._exit_dialog.visible, "Duplicate Back must perform only one navigation step")
	mobile._last_back_msec = -1000
	mobile._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	mobile._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert(mobile._exit_dialog.visible, "Root Back warning must survive duplicate delivery")
	mobile.queue_free()
	await settle()
	print("PASS: populated mobile spell navigation and Android Back duplicate delivery")
	quit()
