extends SceneTree

const Area = preload("res://vtt/creature_area.gd")

class Sheet extends Area:
	var fixture: Dictionary = {}
	func _current() -> Dictionary:
		return fixture

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
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
	var popup: PopupMenu = sheet._options_menu.get_popup()
	for id: int in [1, 2, 3, 4, 5, 6, 7, 8, 9]:
		assert(not popup.get_item_tooltip(popup.get_item_index(id)).is_empty())
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
		assert(sheet._tabs.current_tab == 2)
		assert(sheet._editor_section_picker.selected == int(expected[button.text]))
		assert(not button.tooltip_text.is_empty())
		tested[button.text] = true
	assert(tested.size() == expected.size())
	board.queue_free()
	await process_frame
	print("PASS: desktop option explanations and trait links open the correct editors")
	quit()