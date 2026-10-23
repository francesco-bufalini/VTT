extends SceneTree
const Archive = preload("res://vtt/creature_archive.gd")
const Bridge = preload("res://vtt/desktop_sheet_archive.gd")
const Host = preload("res://vtt/desktop_sheet_host.gd")
const Shell = preload("res://vtt/desktop_creature_sheet.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
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
	assert(not Shell.supported(), "Headless keeps native UI")
	var host := Host.new()
	root.add_child(host)
	assert(host.start() == OK)
	assert(host._server.get_local_port() != 8765, "Never use mobile server port")
	host._stop_listener()
	host.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("PASS: desktop native archive, stale write/delete, identity, campaign notes and isolated host")
	quit()
