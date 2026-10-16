extends SceneTree
## Create the downloadable static PWA's spell catalog from the exact desktop
## endpoint implementation. The native autoload deliberately omits homebrew.

func _initialize() -> void:
	call_deferred("_export_catalog")


func _export_catalog() -> void:
	var host := root.get_node_or_null("/root/PwaHost")
	if host == null or not host.has_method("public_spells_json"):
		push_error("PWA host unavailable: cannot package built-in spell catalog.")
		quit(1)
		return
	var output := ProjectSettings.globalize_path("res://pwa-prototype/catalog")
	var err := DirAccess.make_dir_recursive_absolute(output)
	if err != OK:
		push_error("Could not create PWA catalog folder: " + error_string(err))
		quit(1)
		return
	var data: PackedByteArray = host.call("public_spells_json")
	var decoded: Variant = JSON.parse_string(data.get_string_from_utf8())
	if not decoded is Dictionary or not decoded.get("spells") is Array or decoded.spells.is_empty():
		push_error("Generated PWA spell index is empty or invalid.")
		quit(1)
		return
	var file := FileAccess.open(output.path_join("spells.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not open packaged spell JSON for writing.")
		quit(1)
		return
	file.store_buffer(data)
	file.close()
	print("PASS: exported native built-in PWA spell index (%d records)" % decoded.spells.size())
	quit()
