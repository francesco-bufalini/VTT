extends SceneTree
const Mobile = preload("res://vtt/mobile/creatures_mobile.tscn")

class CopyArchive extends "res://vtt/creature_archive.gd":
	var captured: Dictionary = {}
	func save(record: Dictionary) -> Error:
		captured = record.duplicate(true)
		return OK

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
	var importer := CopyArchive.new()
	var export_payload := {"format": "vtt_creature_export_v1", "version": 1, "creature": record}
	assert(importer.import_export_copy(export_payload) == OK)
	assert(importer.captured.id != record.id and importer.captured.classes == record.classes)
	assert(importer.captured.owner_id == load("res://vtt/creature_owner.gd").local_id())
	assert(importer.import_export_copy({}) == ERR_INVALID_DATA)
	print("PASS: portable creature export imports as an independent owned copy")
	sheet._records.assign([record])
	sheet._selected_id = record.id
	sheet._selected_kind = "character"
	sheet._load_form(record)
	sheet.show_touch_library(false)
	await settle()
	for index: int in range(sheet._tabs.get_tab_count()):
		sheet._touch_section_toggle.pressed.emit()
		await settle()
		assert(sheet._touch_section_drawer.visible, "Sheet drawer must open before selecting a section")
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
		assert(not sheet._touch_section_drawer.visible, "Selecting a section must close the drawer")
		assert(not sheet._touch_section.get_popup().visible, "Tab selection must never open a native popup")
		print("PASS: populated sheet touch tab ", index)
	assert(sheet._spellcasting_ui._view._touch_layout)
	for row: BoxContainer in sheet._spellcasting_ui._view._rows:
		assert(row.vertical, "Mobile spells and resources must stack")
	var picker := OptionButton.new()
	picker.position = Vector2(100, 100)
	picker.size = Vector2(200, 48)
	picker.z_index = 500
	picker.add_item("Prima")
	picker.add_item("Seconda")
	picker.add_item("Disabilitata")
	picker.set_item_disabled(2, true)
	mobile.ui_root.add_child(picker)
	await settle()
	mobile._dispatch_touch_tap(picker.get_global_rect().get_center())
	await settle()
	assert(mobile._choice_panel.visible and not picker.get_popup().visible, "Every OptionButton must use the touch choice panel")
	var changed := [0]
	picker.item_selected.connect(func(_i: int) -> void: changed[0] += 1)
	var choice := mobile._choice_list.get_child(1) as Button
	mobile._dispatch_touch_tap(choice.get_global_rect().get_center())
	await settle()
	assert(picker.selected == 1 and changed[0] == 1 and not mobile._choice_panel.visible, "Touch choice must preserve selection and emit once")
	var menu_button := MenuButton.new()
	menu_button.position = picker.position
	menu_button.size = picker.size
	menu_button.z_index = 501
	menu_button.text = "Menu"
	menu_button.get_popup().add_radio_check_item("Radio", 17)
	mobile.ui_root.add_child(menu_button)
	await settle()
	mobile._dispatch_touch_tap(menu_button.get_global_rect().get_center())
	await settle()
	assert(mobile._choice_panel.visible and not menu_button.get_popup().visible)
	var pressed_ids := []
	menu_button.get_popup().id_pressed.connect(func(id: int) -> void: pressed_ids.append(id))
	choice = mobile._choice_list.get_child(0) as Button
	mobile._dispatch_touch_tap(choice.get_global_rect().get_center())
	await settle()
	assert(pressed_ids == [17], "Radio menu must preserve its original action ID")
	var dialog := AcceptDialog.new()
	dialog.position = Vector2i(30, 200)
	dialog.size = Vector2i(350, 250)
	mobile.add_child(dialog)
	var nested_picker := OptionButton.new()
	nested_picker.custom_minimum_size = Vector2(200, 48)
	nested_picker.add_item("Uno")
	nested_picker.add_item("Due")
	dialog.add_child(nested_picker)
	dialog.popup()
	await settle()
	var nested_point := nested_picker.get_global_rect().get_center() + Vector2(dialog.position)
	mobile._dispatch_touch_tap(nested_point)
	await settle()
	assert(mobile._choice_panel.visible and not dialog.visible, "Selectors inside dialogs must use the same touch panel")
	choice = mobile._choice_list.get_child(1) as Button
	mobile._dispatch_touch_tap(choice.get_global_rect().get_center())
	await settle()
	assert(nested_picker.selected == 1 and dialog.visible, "Selecting an option must restore its dialog")
	mobile._go_back()
	assert(not dialog.visible, "Back must close dialogs attached directly to the mobile scene")
	dialog.queue_free()
	print("PASS: selector inside an embedded dialog")
	picker.queue_free()
	menu_button.queue_free()
	print("PASS: generic OptionButton and radio MenuButton real touch selection")
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
