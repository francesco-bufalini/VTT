extends SceneTree

class TestBoard extends Node3D:
	var board_sync: Node
	func list_available_miniatures() -> Array[Dictionary]:
		return []
	func release_camera_control() -> void:
		pass
	func capture_camera_control() -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.gui_embed_subwindows = true
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var board := TestBoard.new()
	root.add_child(board)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	board.add_child(ui)
	var area: Node = load("res://vtt/creature_area.gd").new()
	board.add_child(area)
	area.setup(board)
	# Build only an in-memory record; this test never saves or deletes an archive.
	var store = load("res://vtt/player_character_store.gd").new()
	var record: Dictionary = store.create_character()
	record["kind"] = "character"
	record["name"] = "Layout check"
	record["proficiency_origins"] = [{"id": "manual:layout", "name": "A long proficiency origin for alignment", "disabled": false}]
	record["proficiency_choices"] = [{"kind": "skill", "key": "perception", "origin_id": "manual:layout", "expertise": true}]
	area._panel.show()
	area._records.assign([record])
	area._selected_id = record["id"]
	area._selected_kind = "character"
	area._load_form(record)
	area._tabs.current_tab = 1
	var locale = load("res://vtt/creature_gui_locale.gd")
	for language: String in ["it", "en"]:
		area._creature_language = language
		locale.apply(area._panel, language)
		assert("vulnerabil" in area._editor_section_picker.get_item_text(5).to_lower())
		for selection: int in range(6):
			area._select_details_editor(selection)
			for width: int in [1600, 1200, 1000, 800]:
				root.size = Vector2i(width, 900)
				for frame: int in range(8):
					await process_frame
				var columns: HBoxContainer = area._statistics_columns
				var left: ScrollContainer = columns.get_child(0)
				var right: ScrollContainer = columns.get_child(1)
				var needed_left: float = left.get_child(0).get_combined_minimum_size().x
				var needed_right: float = right.get_child(0).get_combined_minimum_size().x
				if needed_left + needed_right + 9.0 <= columns.size.x:
					assert(not right.get_h_scroll_bar().visible, "Combat must fit whenever both columns can fit")
				if selection > 0:
					var editor: Control = [area._proficiencies_ui, area._feats_ui, area._bonuses_ui, area._trackers_ui, area._damage_defenses_ui][selection - 1]
					var editor_columns: HBoxContainer = editor.get_node("EditorColumns")
					assert(absf(editor_columns.get_child(1).global_position.x - right.global_position.x) <= 1.0, "Editor and statistics divider must align")
				var grid: GridContainer = area._abilities_grid
				assert(grid.columns == 4)
				for row: int in range(6):
					for column: int in range(4):
						assert(is_equal_approx(grid.get_child(column).position.x, grid.get_child(4 + row * 4 + column).position.x), "Ability rows must align with headers")
	# Optional image output when running with a rendering backend.
	if not OS.get_cmdline_user_args().is_empty():
		root.size = Vector2i(1400, 1000)
		area._select_details_editor(1)
		for capture_frame: int in range(10):
			await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]) == OK)
	board.queue_free()
	await process_frame
	await process_frame
	print("PASS: aligned statistics and editor columns in both languages at four window sizes")
	quit()
