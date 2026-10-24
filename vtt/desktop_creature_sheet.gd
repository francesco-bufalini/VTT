extends Node
## Owns only desktop presentation and the lifetime of its private IPC bridge.
const Archive = preload("res://vtt/creature_archive.gd")
const Host = preload("res://vtt/desktop_sheet_host.gd")
const Bridge = preload("res://vtt/desktop_sheet_archive.gd")
const SheetWindow = preload("res://vtt/desktop_sheet_window.gd")
var area: Node
var view: Control
var host: Node
var bridge := Bridge.new()
var active := false
var _loaded := false
var _file_dialog: FileDialog
var _file_request_id: Variant
var window: SheetWindow

static func supported() -> bool:
	return OS.get_name() in ["Windows", "macOS"] and DisplayServer.get_name() != "headless" and ClassDB.class_exists("WebView")

func open(sheet: Node) -> bool:
	if not supported(): return false
	area = sheet
	bridge.archive = area._archive
	bridge.changed = func(record: Dictionary) -> void:
		# The web library can edit a different creature from the old native form.
		if String(record.get("id", "")) == area._selected_id:
			area._replace_current_record(record)
		var effective: Dictionary = Archive.resolve_form(record)
		area._sync_token_health(effective)
		area._apply_sheet_properties(effective)
		area._apply_current_appearance(effective)
	if host == null:
		host = Host.new()
		add_child(host)
		if host.start() != OK:
			host.queue_free()
			host = null
			return false
	if view == null:
		window = SheetWindow.new()
		window.hide()
		add_child(window)
		window.close_requested.connect(request_close)
		view = ClassDB.instantiate("WebView") as Control
		# The native browser handles its own input. Its compensated Control rect
		# must not intercept Godot's embedded title bar or resize borders.
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.set("full_window_size", false)
		view.set("forward_input_events", false)
		view.set("incognito", true)
		view.set("devtools", OS.is_debug_build())
		view.set("url", host.origin())
		view.connect("ipc_message", _on_message)
		window.add_child(view)
		window.browser = view
	else:
		_loaded = false
		view.call("reload")
	(area._panel.get_child(0) as Control).hide()
	# Retain the native sheet's visibility/input contract, without its full-screen
	# background obscuring the table around the embedded window.
	area._panel.self_modulate.a = 0.0
	window.present()
	view.show()
	active = true
	view.call_deferred("focus")
	return true

func request_close() -> void:
	if is_instance_valid(_file_dialog): return
	if _loaded:
		view.call("eval", "globalThis.vttDesktopClose?.()")
	else:
		_finish(false)

func _finish(native: bool, creature_id: String = "") -> void:
	active = false
	# Hiding a native child WebView does not return keyboard focus to Godot.
	# Without this, Escape never reaches the board after leaving the sheet.
	view.call("focus_parent")
	view.hide()
	if is_instance_valid(window): window.dismiss()
	area._panel.self_modulate.a = 1.0
	(area._panel.get_child(0) as Control).show()
	if not creature_id.is_empty():
		for record: Dictionary in area._archive.list_owned():
			if String(record.id) == creature_id:
				area._selected_id = creature_id
				area._selected_kind = String(record.kind)
				break
	area._reload()
	if not native: area.hide_panel()
	view.call_deferred("focus_parent")

func _native_action(method: String, args: Dictionary) -> void:
	_finish(true, String(args.get("creatureId", "")))
	match method:
		"cast":
			area._show_sheet_tab("Poteri")
			var selection: Dictionary = args.get("selection", {})
			area._on_action_cast_requested(String(selection.get("id", "")), String(selection.get("grant_id", "")), String(selection.get("casting_class", "manual")))

func _send_reply(request_id: Variant, result: Dictionary) -> void:
	if not is_instance_valid(view): return
	var reply := result.duplicate()
	reply["id"] = request_id
	view.call("eval", "globalThis.vttDesktopReceive(%s)" % JSON.stringify(reply))

func _complete_file_request(result: Dictionary) -> void:
	if not is_instance_valid(_file_dialog): return
	var dialog := _file_dialog
	_file_dialog = null
	_send_reply(_file_request_id, result)
	_file_request_id = null
	dialog.queue_free()
	if active:
		view.show()
		view.call_deferred("focus")

func _open_file_dialog(dialog: FileDialog, request_id: Variant) -> void:
	_file_dialog = dialog
	_file_request_id = request_id
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	# A separate desktop window keeps the picker above the native WebView2 child.
	dialog.use_native_dialog = false
	dialog.force_native = true
	dialog.transient = true
	dialog.exclusive = true
	dialog.add_filter("*.json", "Creature VTT · JSON")
	dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	add_child(dialog)
	dialog.canceled.connect(func() -> void: _complete_file_request({"value": {"canceled": true}}))
	# WebView2 is a native child window and can cover Godot's modal surface.
	# Retain the loaded page, but return native focus for the chooser's lifetime.
	view.call("focus_parent")
	view.hide()
	dialog.popup_centered_ratio(0.8)

func _import_paths(paths: PackedStringArray) -> Dictionary:
	var previous: Dictionary = {}
	for record: Dictionary in area._archive.list_owned(): previous[String(record.id)] = true
	var failures: Array[String] = []
	for path: String in paths:
		var error: Error = area._import_export_path(path)
		if error != OK: failures.append(path.get_file() + ": " + error_string(error))
	var imported: Array[String] = []
	for record: Dictionary in area._archive.list_owned():
		if not previous.has(String(record.id)): imported.append(String(record.id))
	return {"value": {"canceled": false, "imported": imported.size(), "creatureIds": imported, "failures": failures}}

func _begin_import(request_id: Variant) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	dialog.title = "Importa creature o archivio VTT"
	dialog.files_selected.connect(func(paths: PackedStringArray) -> void: _complete_file_request(_import_paths(paths)))
	_open_file_dialog(dialog, request_id)

func _write_export(path: String, text: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return {"error": "Esportazione non riuscita: " + error_string(FileAccess.get_open_error())}
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return {"error": "Esportazione non riuscita: " + error_string(error)}
	return {"value": {"saved": true, "filename": path.get_file()}}

func _begin_download(args: Dictionary, request_id: Variant) -> void:
	var text := String(args.get("text", ""))
	if text.to_utf8_buffer().size() > 16 * 1024 * 1024 or not JSON.parse_string(text) is Dictionary:
		_send_reply(request_id, {"error": "Esportazione JSON non valida o troppo grande."})
		return
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.title = "Esporta creature VTT"
	dialog.current_file = String(args.get("filename", "creatura.json")).get_file()
	dialog.file_selected.connect(func(path: String) -> void:
		_complete_file_request(_write_export(path, text)))
	_open_file_dialog(dialog, request_id)

func _on_message(raw: String) -> void:
	if not active or raw.to_utf8_buffer().size() > 24 * 1024 * 1024: return
	var value: Variant = JSON.parse_string(raw)
	if not value is Dictionary: return
	var message: Dictionary = value
	if not message.get("args", {}) is Dictionary: return
	var method := String(message.get("method", ""))
	if method in ["import", "download"]:
		if is_instance_valid(_file_dialog):
			_send_reply(message.get("id"), {"error": "Completa prima la scelta del file già aperta."})
		elif method == "import": _begin_import(message.get("id"))
		else: _begin_download(message.get("args", {}), message.get("id"))
		return
	var reply: Dictionary
	match method:
		"ready":
			_loaded = true
			reply = {"value": true}
		"selected": reply = {"value": area._selected_id}
		"close", "native", "cast": reply = {"value": true}
		_: reply = bridge.dispatch(method, message.get("args", {}))
	reply["id"] = message.get("id")
	view.call("eval", "globalThis.vttDesktopReceive(%s)" % JSON.stringify(reply))
	if method in ["close", "native"]: _finish(method == "native", String(message.get("args", {}).get("creatureId", "")))
	elif method == "cast": _native_action.call_deferred(method, message.get("args", {}))
