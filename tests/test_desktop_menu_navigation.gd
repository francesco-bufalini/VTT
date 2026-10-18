extends SceneTree

const Area = preload("res://vtt/creature_area.gd")

class Sheet extends Area:
	var fixture: Dictionary = {}
	func _current() -> Dictionary:
		return fixture

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(800, 600)
	var board := Node3D.new()
	root.add_child(board)
	var ui := CanvasLayer.new()
	board.add_child(ui)
	var sheet := Sheet.new()
	board.add_child(sheet)
	sheet.board_root = board
	sheet.ui_root = ui
	sheet.fixture = {"id": "desktop_navigation", "kind": "character", "name": "Prova",
		"rules_version": "2014", "class": "Bard", "class_source": "PHB", "level": 3,
		"classes": [{"name": "Bard", "source": "PHB", "level": 3}],
		"abilities": {"str": 10, "dex": 14, "con": 12, "int": 10, "wis": 12, "cha": 16}}
	sheet._build_ui()
	assert(not sheet._creature_batch_selection_row.visible
		and not sheet._creature_batch_actions_row.visible,
		"Bulk controls must not take space before any checkboxes are selected")
	sheet._records = [{"id": "test-bulk", "kind": "character", "name": "Test"}]
	sheet._creature_batch_ids["character:test-bulk"] = true
	sheet._update_creature_batch_actions()
	assert(sheet._creature_batch_selection_row.visible
		and sheet._creature_batch_actions_row.visible,
		"All four bulk controls must appear after selecting a creature")
	sheet._creature_batch_ids.clear()
	sheet._update_creature_batch_actions()
	assert(not sheet._creature_batch_selection_row.visible
		and not sheet._creature_batch_actions_row.visible,
		"All four bulk controls must disappear when no creature remains selected")
	sheet._records.clear()
	assert(sheet._delete_dialog.get_parent() == ui,
		"Creature deletion confirmation belongs to the UI canvas")
	sheet._confirm_delete()
	var deletion: ConfirmationDialog = sheet._delete_dialog
	assert(deletion.visible, "Creature deletion must open a confirmation")
	assert(deletion.position.x >= 0 and deletion.position.y >= 0
		and deletion.position.x + deletion.size.x <= root.size.x
		and deletion.position.y + deletion.size.y <= root.size.y,
		"Deletion confirmation must fit immediately on desktop")
	await process_frame
	assert(deletion.position.x >= 0 and deletion.position.y >= 0
		and deletion.position.x + deletion.size.x <= root.size.x
		and deletion.position.y + deletion.size.y <= root.size.y,
		"Deletion confirmation must remain on screen after layout")
	deletion.hide()
	assert(not sheet._creature_import_button.tooltip_text.is_empty())
	assert(sheet._creature_import_picker.file_mode == FileDialog.FILE_MODE_OPEN_FILES)
	assert(sheet._creature_import_picker.files_selected.is_connected(sheet._import_export_files))

	sheet._traits_ui.load_record(sheet.fixture)
	sheet._traits_ui._set_all_expanded(true)
	assert(not sheet._traits_ui._cards.is_empty())
	var expected: Dictionary = {"Origini e benefici": 0, "Competenze": 1, "Bonus": 3,
		"Utilizzi e tracker": 4, "Incantesimi da origini": 6}
	var tested: Dictionary = {}
	for node: Node in sheet._traits_ui.find_children("*", "Button", true, false):
		var button := node as Button
		if not expected.has(button.text) or tested.has(button.text):
			continue
		button.pressed.emit()
		assert(sheet._tabs.get_tab_control(sheet._tabs.current_tab).name == "Modifica personaggio")
		assert(sheet._editor_section_picker.selected == int(expected[button.text]))
		assert(not button.tooltip_text.is_empty())
		tested[button.text] = true
	assert(tested.size() == expected.size())
	board.queue_free()
	await process_frame
	print("PASS: desktop option explanations and trait links open the correct editors")
	quit()