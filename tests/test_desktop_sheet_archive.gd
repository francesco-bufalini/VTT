extends SceneTree
const Archive = preload("res://vtt/creature_archive.gd")
const Bridge = preload("res://vtt/desktop_sheet_archive.gd")
const Host = preload("res://vtt/desktop_sheet_host.gd")
const Shell = preload("res://vtt/desktop_creature_sheet.gd")
const SheetWindow = preload("res://vtt/desktop_sheet_window.gd")
class FakeView extends Control:
	var parent_focus_calls := 0
	var eval_calls: Array[String] = []
	func focus_parent() -> void: parent_focus_calls += 1
	func eval(script: String) -> void: eval_calls.append(script)
class FakeArea extends Node:
	var _panel := PanelContainer.new()
	var _archive: RefCounted
	var _selected_id := ""
	var _selected_kind := "character"
	var closed := false
	func _reload() -> void: pass
	func hide_panel() -> void: closed = true

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# Native child bounds must follow the actual surface, including editor
	# downscaling and Retina upscaling, rather than the logical UI resolution.
	for scale: float in [0.75, 1.0, 1.5, 2.0]:
		var transform := Transform2D(Vector2(scale, 0), Vector2(0, scale), Vector2(120, 80))
		var bounds := SheetWindow.native_bounds(transform, Vector2(960, 640))
		assert(bounds == Rect2(120, 80, 960 * scale, 640 * scale))
	var frame := SheetWindow.new()
	frame.hide()
	root.add_child(frame)
	frame.present()
	assert(frame.is_embedded(), "Creature window must stay inside the game on every desktop platform")
	var original_frame_size := frame.size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(640, 400)
	frame._fit()
	assert(frame.size.x <= 576 and frame.size.y <= 320, "Clamp after shrinking the preview")
	var detached_browser := FakeView.new()
	frame.browser = detached_browser
	frame._sync_browser() # Teardown can detach the native child before its frame.
	detached_browser.free()
	frame.dismiss()
	frame.queue_free()
	assert(original_frame_size.x > 0)
	var archive := Archive.new()
	archive.setup()
	var path := "user://desktop_sheet_test_%d.json" % Time.get_ticks_usec()
	archive._storage.path = path
	var original: Dictionary = archive.create_character()
	original.name = "Desktop fixture"
	original["additional_traits"] = "Preserve campaign notes"
	assert(archive.save(original) == OK)
	var bridge := Bridge.new()
	bridge.archive = archive
	var args := {"scope": "default", "type": "creature", "id": original.id}
	var first: Dictionary = bridge.dispatch("get", args).value
	assert(first.data.name == "Desktop fixture")
	var changed: Dictionary = first.data.duplicate(true)
	changed.name = "Web edit"
	args.merge({"data": changed, "expectedRevision": first.revision})
	var saved := bridge.dispatch("put", args)
	assert(not saved.has("error"), str(saved))
	assert(archive.list_owned()[0].name == "Web edit")
	assert(archive.list_owned()[0].additional_traits == "Preserve campaign notes")
	assert(bridge.dispatch("put", args).has("error"), "Reject stale web write")
	var native: Dictionary = archive.list_owned()[0]
	native.name = "Concurrent native edit"
	assert(archive.save(native) == OK)
	args.expectedRevision = saved.value.revision
	assert(bridge.dispatch("put", args).has("error"), "Reject native concurrent edit")
	assert(bridge.dispatch("delete", args).has("error"), "Reject stale delete")
	assert(archive.list_owned()[0].name == "Concurrent native edit")
	var fresh: Dictionary = bridge.dispatch("get", args).value
	args.expectedRevision = fresh.revision
	args.data = fresh.data.duplicate(true)
	args.data.owner_id = "foreign"
	assert(bridge.dispatch("put", args).has("error"), "Reject changed owner")
	args.data = fresh.data.duplicate(true)
	args.data.kind = "monster"
	assert(bridge.dispatch("put", args).has("error"), "Reject changed kind")
	args.data = fresh.data.duplicate(true)
	args.expectedRevision = "1"
	assert(bridge.dispatch("put", args).has("error"), "Reject malformed revisions")
	bridge.settings_path = path + ".cfg"
	assert(bridge.dispatch("setting", {"key": "desktop-test", "value": 7}).value == 7)
	var reopened := Bridge.new()
	reopened.settings_path = bridge.settings_path
	assert(reopened.dispatch("setting", {"key": "desktop-test"}).value == 7)
	var fake_area := FakeArea.new()
	fake_area._archive = archive
	fake_area._selected_kind = "monster"
	fake_area._panel.add_child(Control.new())
	root.add_child(fake_area)
	fake_area.add_child(fake_area._panel)
	var fake_view := FakeView.new()
	fake_area._panel.add_child(fake_view)
	var shell := Shell.new()
	root.add_child(shell)
	shell.area = fake_area
	shell.view = fake_view
	shell.active = true
	shell._finish(false, original.id)
	assert(fake_view.parent_focus_calls == 1 and fake_area.closed and not shell.active)
	assert(fake_area._selected_id == original.id)
	assert(fake_area._selected_kind == "character", "Restore kind as well as ID when switching from a monster")
	await process_frame
	assert(fake_view.parent_focus_calls == 2, "Restore Godot keyboard focus after hiding the native child window")
	# A malformed IPC reply object must not be interpreted as the creature ID.
	# Previously this crashed at desktop_creature_sheet.gd:204 while closing.
	shell.active = true
	fake_area.closed = false
	shell._on_message(JSON.stringify({"id": 37, "method": "close", "args": {"creatureId": {"id": 37, "value": true}}}))
	assert(fake_area.closed and not shell.active, "Invalid IDs must not prevent closing")
	assert(fake_area._selected_id == original.id, "Invalid IDs must not change selected creature")
	assert(fake_view.eval_calls.size() == 1, "Close receives an IPC acknowledgment")
	shell.active = true
	fake_area.closed = false
	shell._on_message(JSON.stringify({"id": 38, "method": "native", "args": {"creatureId": {"id": 37, "value": true}}}))
	assert(not fake_area.closed and not shell.active, "Native return must tolerate invalid IDs")
	assert(fake_area._selected_id == original.id)
	shell.active = true
	shell._on_message(JSON.stringify({"id": 39, "method": {"id": 37, "value": true}, "args": {}}))
	assert(shell.active, "Malformed methods must not close the sheet")
	assert(fake_view.eval_calls.size() == 3)
	shell.queue_free()
	fake_area.queue_free()
	assert(not Shell.supported(), "Headless keeps native UI")
	var host := Host.new()
	root.add_child(host)
	assert(host.start() == OK)
	assert(host._server.get_local_port() != 8765, "Never use mobile server port")
	host._stop_listener()
	host.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bridge.settings_path))
	print("PASS: desktop native archive, stale write/delete, identity, campaign notes and isolated host")
	quit()
