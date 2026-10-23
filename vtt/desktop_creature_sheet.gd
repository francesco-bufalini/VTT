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
	return true

func request_close() -> void:
	if _loaded:
		view.call("eval", "globalThis.vttDesktopClose?.()")
	else:
		_finish(false)

func _finish(native: bool) -> void:
	active = false
	# Hiding a native child WebView does not return keyboard focus to Godot.
	# Without this, Escape never reaches the board after leaving the sheet.
	view.call("focus_parent")
	view.hide()
	(area._panel.get_child(0) as Control).show()
	area._reload()
	if not native: area.hide_panel()
	view.call_deferred("focus_parent")

func _on_message(raw: String) -> void:
	if not active or raw.length() > 2 * 1024 * 1024: return
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
		"close", "native": reply = {"value": true}
		_: reply = bridge.dispatch(method, message.get("args", {}))
	reply["id"] = message.get("id")
	view.call("eval", "globalThis.vttDesktopReceive(%s)" % JSON.stringify(reply))
	if method in ["close", "native"]: _finish(method == "native")
