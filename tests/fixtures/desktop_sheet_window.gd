extends SceneTree
## Interactive smoke fixture. Uses a disposable archive, never personal sheets.
class Board extends Node3D:
	var ui_owns_mouse := false
	func release_camera_control() -> void:
		ui_owns_mouse = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	func capture_camera_control() -> void:
		ui_owns_mouse = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not ui_owns_mouse:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			print("PASS: Escape reached native board and released pointer")
	func list_available_miniatures() -> Array[Dictionary]: return []
var path: String
var area: Node

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.title = "VTT Desktop PWA - isolated verification"
	root.size = Vector2i(1440, 960)
	root.gui_embed_subwindows = true
	var board := Board.new()
	root.add_child(board)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	board.add_child(ui)
	var back := Button.new()
	back.text = "Tavolo di prova · Apri creature (Esc rilascia il puntatore)"
	back.position = Vector2(20, 60)
	ui.add_child(back)
	back.pressed.connect(func() -> void: area.show_panel())
	area = load("res://vtt/creature_area.gd").new()
	area._selection_config_path = "user://desktop_web_test_selection.cfg"
	board.add_child(area)
	area.setup(board, ui, false, false)
	path = "user://desktop_window_test_%d.json" % Time.get_ticks_usec()
	area._archive._storage.path = path
	var record: Dictionary = area._archive.create_character()
	record.name = "Lyria · Verifica desktop"
	record.additional_traits = "Scheda sintetica per verificare la transizione desktop."
	record.abilities = {"str": 12, "dex": 16, "con": 14, "int": 18, "wis": 12, "cha": 10}
	record.current_hp = 28
	record.max_hp = 32
	record.max_hp_base = 32
	assert(area._archive.save(record) == OK)
	area._reload()
	area.show_panel()
	if "--window-smoke" in OS.get_cmdline_user_args():
		await verify_window()
		quit()
	elif "--dialog-smoke" in OS.get_cmdline_user_args():
		root.title = "VTT Desktop PWA - dialog verification"
		verify_file_dialogs()
	else:
		get_tree_timeout()

func wait_for_sheet() -> void:
	var end := Time.get_ticks_msec() + 20000
	while (area._desktop_web_sheet == null or not area._desktop_web_sheet._loaded) and Time.get_ticks_msec() < end:
		await process_frame
	assert(area._desktop_web_sheet != null and area._desktop_web_sheet._loaded)

func check_native_bounds() -> void:
	await process_frame
	await process_frame
	var shell: Node = area._desktop_web_sheet
	var frame: Window = shell.window
	assert(frame.is_embedded() and not shell.view.get("full_window_size"))
	var rect := frame.get_screen_transform() * Rect2(Vector2.ZERO, Vector2(frame.size))
	assert(shell.view.size.distance_to(rect.size) < 2.0, "Native surface must use physical pixels")
	assert(shell.view.get_screen_position().distance_to(rect.position) < 2.0, "Native browser must follow the embedded frame")
	assert(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(Rect2(Vector2(frame.position), Vector2(frame.size))))

func verify_window() -> void:
	await wait_for_sheet()
	var shell: Node = area._desktop_web_sheet
	var frame: Window = shell.window
	await check_native_bounds()
	frame.position += Vector2i(-40, 20)
	frame.size = Vector2i(960, 640)
	await check_native_bounds()
	root.size = Vector2i(1024, 720)
	await check_native_bounds()
	shell.request_close()
	var end := Time.get_ticks_msec() + 10000
	while shell.active and Time.get_ticks_msec() < end: await process_frame
	assert(not shell.active and not frame.visible and not area._panel.visible)
	assert(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	area.show_panel()
	await wait_for_sheet()
	await check_native_bounds()
	print("PASS: real embedded WebView bounds, moving, resizing, scaled preview, close and reopen")

func _finalize() -> void:
	if not path.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func verify_file_dialogs() -> void:
	var end := Time.get_ticks_msec() + 30000
	while (area._desktop_web_sheet == null or not area._desktop_web_sheet._loaded) and Time.get_ticks_msec() < end:
		await process_frame
	var shell: Node = area._desktop_web_sheet
	assert(shell != null and shell._loaded)
	shell._begin_import(999001)
	assert(shell._file_dialog.force_native and not shell._file_dialog.is_embedded())
	while is_instance_valid(shell._file_dialog): await process_frame
	assert(shell.active and area._panel.visible)
	print("PASS: native import chooser canceled without leaving WebView")
	shell._begin_download({"text": "{\"format\":\"vtt_creature_batch_export_v1\",\"version\":1,\"entries\":[]}", "filename": "desktop-dialog-test.json"}, 999002)
	while is_instance_valid(shell._file_dialog): await process_frame
	assert(shell.active and area._panel.visible)
	print("PASS: native save chooser canceled without leaving WebView")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit()

func get_tree_timeout() -> void:
	await create_timer(600).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit()
