extends Node
## Owns only desktop presentation and the lifetime of its private IPC bridge.
const Host = preload("res://vtt/desktop_sheet_host.gd")
const Bridge = preload("res://vtt/desktop_sheet_archive.gd")
var area: Node
var view: Control
var host: Node
var bridge := Bridge.new()
var active := false
var _loaded := false

static func supported() -> bool:
	return OS.get_name() == "Windows" and DisplayServer.get_name() != "headless" and ClassDB.class_exists("WebView")

func open(sheet: Node) -> bool:
	if not supported(): return false
	area = sheet
	bridge.archive = area._archive
	bridge.changed = func(record: Dictionary) -> void:
		# The web library can edit a different creature from the old native form.
		if String(record.get("id", "")) == area._selected_id:
			area._replace_current_record(record)
		area._sync_token_health(record)
		area._apply_sheet_properties(record)
	if host == null:
		host = Host.new()
		add_child(host)
		if host.start() != OK:
			host.queue_free()
			host = null
			return false
	if view == null:
		view = ClassDB.instantiate("WebView") as Control
		# WRY must use the real window size, independent of Godot UI stretching.
		view.set("full_window_size", true)
		view.set("forward_input_events", false)
		view.set("incognito", true)
		view.set("devtools", OS.is_debug_build())
		view.set("url", host.origin())
		view.connect("ipc_message", _on_message)
		area._panel.add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		_loaded = false
		view.call("reload")
	(area._panel.get_child(0) as Control).hide()
	view.show()
	active = true
	view.call_deferred("focus")
	return true

func request_close() -> void:
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
		"import": area._show_creature_import_picker()
		"backup":
			area._batch_export_pending = area._archive.list_owned()
			area._export_dialog.title = "Esporta archivio creature"
			area._export_dialog.current_file = "archivio_creature.json"
			preload("res://vtt/dialog_layout.gd").popup(area._export_dialog, Vector2i(820, 550))
		"cast":
			area._show_sheet_tab("Poteri")
			var selection: Dictionary = args.get("selection", {})
			area._on_action_cast_requested(String(selection.get("id", "")), String(selection.get("grant_id", "")), String(selection.get("casting_class", "manual")))

func _download(args: Dictionary) -> Dictionary:
	var text := String(args.get("text", ""))
	if text.to_utf8_buffer().size() > 16 * 1024 * 1024 or not JSON.parse_string(text) is Dictionary:
		return {"error": "Esportazione JSON non valida o troppo grande."}
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.title = "Esporta creature VTT"
	dialog.add_filter("*.json", "Archivio VTT")
	dialog.current_file = String(args.get("filename", "creatura.json")).get_file()
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(text)
			file.close()
		else:
			area._set_status("Esportazione non riuscita: " + error_string(FileAccess.get_open_error()))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.8)
	return {"value": true}

func _on_message(raw: String) -> void:
	if not active or raw.to_utf8_buffer().size() > 24 * 1024 * 1024: return
	var value: Variant = JSON.parse_string(raw)
	if not value is Dictionary: return
	var message: Dictionary = value
	if not message.get("args", {}) is Dictionary: return
	var method := String(message.get("method", ""))
	var reply: Dictionary
	match method:
		"ready":
			_loaded = true
			reply = {"value": true}
		"selected": reply = {"value": area._selected_id}
		"download": reply = _download(message.get("args", {}))
		"close", "native", "import", "backup", "cast": reply = {"value": true}
		_: reply = bridge.dispatch(method, message.get("args", {}))
	reply["id"] = message.get("id")
	view.call("eval", "globalThis.vttDesktopReceive(%s)" % JSON.stringify(reply))
	if method in ["close", "native"]: _finish(method == "native", String(message.get("args", {}).get("creatureId", "")))
	elif method in ["import", "backup", "cast"]: _native_action.call_deferred(method, message.get("args", {}))
