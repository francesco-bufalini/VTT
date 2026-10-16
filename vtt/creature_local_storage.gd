extends RefCounted

# Single device-local archive for both characters and monsters.
# Scene-authored creatures are separate and never written here.
const Owner = preload("res://vtt/creature_owner.gd")
const FILE_PATH := "user://creatures/creatures.json"
const FILE_VERSION := 1
const LEGACY_SOURCES := [
	{"dir": "user://player_characters", "key": "characters", "kind": "character"},
	{"dir": "user://master_creatures", "key": "creatures", "kind": "monster"},
	# Briefly used by an older global-archive revision.
	{"dir": "user://creatures", "file": "characters.json", "key": "characters", "kind": "character"},
	{"dir": "user://creatures", "file": "monsters.json", "key": "creatures", "kind": "monster"}
]

# A custom path is useful for isolated tests. Legacy sources are only scanned
# for the real user archive, unless migration_sources is explicitly supplied.
var path: String = FILE_PATH
var migration_sources: Array[Dictionary] = []


func list_records(kind: String = "") -> Array[Dictionary]:
	var loaded := _load()
	if loaded.error != OK:
		push_error("Creature archive: cannot read %s (%s)" % [path, error_string(loaded.error)])
		return []
	var result: Array[Dictionary] = []
	for record: Dictionary in loaded.records:
		if kind.is_empty() or String(record.get("kind", "")) == kind:
			result.append(record.duplicate(true))
	return result


func save_records(kind: String, records: Array[Dictionary], allow_transfer: bool = false) -> Error:
	if kind not in ["character", "monster"]:
		return ERR_INVALID_PARAMETER
	var loaded := _load()
	if loaded.error != OK:
		return loaded.error
	var incoming_ids: Dictionary = {}
	for record: Dictionary in records:
		var id := String(record.get("id", "")).strip_edges()
		if id.is_empty() or String(record.get("kind", kind)) != kind or incoming_ids.has(id):
			return ERR_INVALID_PARAMETER
		incoming_ids[id] = record
		if not allow_transfer and not Owner.is_owner(record):
			return ERR_UNAUTHORIZED
	var merged: Array[Dictionary] = []
	for old: Dictionary in loaded.records:
		if String(old.get("kind", "")) != kind:
			merged.append(old.duplicate(true))
			continue
		var old_id := String(old.get("id", ""))
		if incoming_ids.has(old_id):
			var replacement: Dictionary = incoming_ids[old_id]
			if not allow_transfer and not Owner.can_edit(replacement, old):
				return ERR_UNAUTHORIZED
		elif not Owner.is_owner(old):
			# Sheets transferred to another owner remain stored but invisible.
			merged.append(old.duplicate(true))
	for record: Dictionary in records:
		var row := record.duplicate(true)
		row["kind"] = kind
		merged.append(row)
	return _write(merged)


func _load() -> Dictionary:
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return {"error": FileAccess.get_open_error(), "records": []}
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if not parsed is Dictionary:
			return {"error": ERR_FILE_CORRUPT, "records": []}
		if int(parsed.get("version", -1)) != FILE_VERSION or not parsed.get("creatures") is Array:
			return {"error": ERR_FILE_CORRUPT, "records": []}
		var records: Array[Dictionary] = []
		for entry: Variant in parsed["creatures"]:
			if not entry is Dictionary:
				return {"error": ERR_FILE_CORRUPT, "records": []}
			var record: Dictionary = entry
			if String(record.get("kind", "")) not in ["character", "monster"]:
				return {"error": ERR_FILE_CORRUPT, "records": []}
			if String(record.get("id", "")).strip_edges().is_empty():
				return {"error": ERR_FILE_CORRUPT, "records": []}
			records.append(record.duplicate(true))
		return {"error": OK, "records": records}
	# Migration happens only when the global file does not exist. Its existence
	# becomes the migration marker: deleting a creature never resurrects it.
	var legacy: Array[Dictionary] = []
	var specs: Array = LEGACY_SOURCES if path == FILE_PATH else migration_sources
	for spec_value: Variant in specs:
		var spec: Dictionary = spec_value
		var dir_path := String(spec.get("dir", ""))
		var directory := DirAccess.open(dir_path)
		if directory == null:
			if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
				return {"error": ERR_CANT_OPEN, "records": []}
			continue
		var names: PackedStringArray = []
		if spec.has("file"):
			var filename := String(spec["file"])
			if FileAccess.file_exists(dir_path.path_join(filename)):
				names.append(filename)
		else:
			for filename: String in directory.get_files():
				if filename.ends_with(".json"):
					names.append(filename)
			names.sort()
		for filename: String in names:
			var source_path: String = dir_path.path_join(filename)
			if source_path == path:
				continue
			var file := FileAccess.open(source_path, FileAccess.READ)
			if file == null:
				return {"error": FileAccess.get_open_error(), "records": []}
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if not parsed is Dictionary or not parsed.get(spec["key"]) is Array:
				# Abort rather than creating an incomplete archive and masking
				# records in a damaged old file on subsequent launches.
				return {"error": ERR_FILE_CORRUPT, "records": []}
			var index := 0
			for entry: Variant in parsed[spec["key"]]:
				if not entry is Dictionary:
					return {"error": ERR_FILE_CORRUPT, "records": []}
				var record: Dictionary = entry.duplicate(true)
				record["kind"] = String(spec["kind"])
				var id := String(record.get("id", "")).strip_edges()
				if id.is_empty():
					id = "legacy_" + (source_path + ":" + str(index)).md5_text().substr(0, 16)
					record["id"] = id
				var duplicate := false
				for existing: Dictionary in legacy:
					if String(existing.get("kind", "")) != record["kind"] or String(existing.get("id", "")) != id:
						continue
					if existing == record:
						duplicate = true
						break
					# Preserve two distinct sheets from different scopes even
					# if their old IDs were the same.
					record["id"] = id + "_legacy_" + (source_path + ":" + str(index)).md5_text().substr(0, 12)
					break
				if not duplicate:
					legacy.append(record)
				index += 1
	var error := _write(legacy)
	return {"error": error, "records": legacy if error == OK else []}


func _write(records: Array[Dictionary]) -> Error:
	var folder := path.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	if error != OK:
		return error
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": FILE_VERSION, "creatures": records}, "  "))
	error = file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary),
		ProjectSettings.globalize_path(path)
	)
