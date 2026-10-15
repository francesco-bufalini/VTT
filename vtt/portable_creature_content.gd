extends RefCounted

# Portable companion definitions for a creature export. The archive carries
# only homebrew definitions actually referenced by the sheet (including
# owned documents), never the whole private homebrew folder.
const Catalog = preload("res://vtt/content_catalog.gd")
const CATEGORIES := Catalog.CATEGORIES
const IMPORT_DIR := "user://homebrew/portable_imports"
const MAX_ENTRIES := 250
const MAX_BYTES := 12 * 1024 * 1024


static func _referenced(value: Variant, wanted: Dictionary) -> void:
	if value is Dictionary:
		for entry: Variant in (value as Dictionary).values():
			_referenced(entry, wanted)
	elif value is Array:
		for entry: Variant in value:
			_referenced(entry, wanted)
	elif value is String:
		var identifier := String(value).strip_edges()
		if identifier.begins_with("homebrew:") and identifier.split(":").size() == 4:
			wanted[identifier] = true


static func _definitions() -> Dictionary:
	var result: Dictionary = {}
	for category: String in CATEGORIES:
		for entry: Dictionary in Catalog.home_entries(category):
			result[String(entry.get("id", ""))] = entry
	return result


static func unresolved(creature: Dictionary) -> Array[String]:
	# Abort an export rather than promising portability while a referenced
	# homebrew definition has already disappeared from this device.
	var wanted: Dictionary = {}
	_referenced(creature, wanted)
	var definitions: Dictionary = _definitions()
	var checked: Dictionary = {}
	for _pass: int in range(MAX_ENTRIES):
		var changed := false
		for raw_id: Variant in wanted.keys():
			var identifier: String = String(raw_id)
			if checked.has(identifier):
				continue
			checked[identifier] = true
			if definitions.has(identifier):
				_referenced(definitions[identifier], wanted)
				changed = true
		if not changed:
			break
	var missing: Array[String] = []
	for raw_id: Variant in wanted.keys():
		var identifier: String = String(raw_id)
		if not definitions.has(identifier):
			missing.append(identifier)
	missing.sort()
	return missing


static func bundle(creature: Dictionary) -> Array[Dictionary]:
	var wanted: Dictionary = {}
	_referenced(creature, wanted)
	var definitions: Dictionary = _definitions()
	# Fill dependencies recursively, since a feature or item can grant
	# another locally-defined feat, spell or catalog reference.
	var added: Dictionary = {}
	for _pass: int in range(MAX_ENTRIES):
		var changed := false
		for raw_id: Variant in wanted.keys():
			var identifier: String = String(raw_id)
			if added.has(identifier) or not definitions.has(identifier):
				continue
			added[identifier] = true
			_referenced(definitions[identifier], wanted)
			changed = true
		if not changed:
			break
	var result: Array[Dictionary] = []
	for raw_id: Variant in added.keys():
		var entry: Dictionary = definitions[String(raw_id)]
		var parts: PackedStringArray = String(raw_id).split(":")
		if parts.size() != 4:
			continue
		var data: Dictionary = entry.duplicate(true)
		for field: String in ["id", "name", "source", "category", "origin",
			"asset_dir", "overrides", "icon", "icon_id"]:
			data.erase(field)
		# The override and icon metadata belong to the entry declaration, not
		# the JSON data dictionary.
		result.append({"id": String(raw_id), "name": String(entry.get("name", "")),
			"source": String(entry.get("source", parts[1])),
			"overrides": String(entry.get("overrides", "")),
			"icon": String(entry.get("icon", "")),
			"icon_id": String(entry.get("icon_id", "")),
			"data": data})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", "")))
	return result


static func _valid_entry(entry: Dictionary) -> bool:
	var id: String = String(entry.get("id", ""))
	var parts := id.split(":")
	if parts.size() != 4 or parts[0] != "homebrew" or parts[2] not in CATEGORIES:
		return false
	var namespace_pattern := RegEx.create_from_string("^[a-z0-9][a-z0-9_-]{0,47}$")
	var local_pattern := RegEx.create_from_string("^[a-z0-9][a-z0-9_-]{0,63}$")
	if namespace_pattern.search(parts[1]) == null or local_pattern.search(parts[3]) == null:
		return false
	return entry.get("data") is Dictionary and not String(entry.get("name", "")).strip_edges().is_empty() and String(entry.get("name", "")).length() <= 160


static func install(raw: Variant) -> Error:
	if raw == null:
		return OK # Older creature exports contain no companion definitions.
	if not raw is Array or (raw as Array).size() > MAX_ENTRIES:
		return ERR_INVALID_DATA
	if JSON.stringify(raw).to_utf8_buffer().size() > MAX_BYTES:
		return ERR_INVALID_DATA
	var known: Dictionary = _definitions()
	var new_entries: Dictionary = {}
	for item: Variant in raw:
		if not item is Dictionary or not _valid_entry(item as Dictionary):
			return ERR_INVALID_DATA
		# The normal homebrew loader caps each package at 2 MB, even if a
		# creature bundle may contain several such packages.
		if JSON.stringify(item).to_utf8_buffer().size() > Catalog.MAX_FILE_BYTES - 512:
			return ERR_INVALID_DATA
		var entry: Dictionary = item as Dictionary
		var identifier: String = String(entry["id"])
		if known.has(identifier) or new_entries.has(identifier):
			continue # Recipient's existing content wins, no duplicates.
		new_entries[identifier] = entry
	# Check all entries before writing anything.
	for identifier: String in new_entries.keys():
		var entry: Dictionary = new_entries[identifier]
		var parts := identifier.split(":")
		var document: Dictionary = {
			"schema_version": 1, "namespace": parts[1],
			"entries": [{
				"category": parts[2], "id": parts[3],
				"name": String(entry["name"]),
				"source": String(entry.get("source", parts[1])),
				"overrides": String(entry.get("overrides", "")),
				"icon": String(entry.get("icon", "")),
				"icon_id": String(entry.get("icon_id", "")),
				"data": (entry["data"] as Dictionary).duplicate(true)
			}]
		}
		var folder := IMPORT_DIR.path_join(parts[1])
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
			return ERR_CANT_CREATE
		var path: String = folder.path_join(parts[2] + "_" + parts[3] + ".json")
		# An existing file with a conflicting definition is never replaced.
		if FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_string(JSON.stringify(document, "  "))
		var err: Error = file.get_error()
		file.close()
		if err != OK:
			return err
	if not new_entries.is_empty():
		Catalog.reload_homebrew()
	return OK
