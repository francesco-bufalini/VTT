extends RefCounted

# Single device-local archive for both characters and monsters.
# Scene-authored creatures are separate and never written here.
const Owner = preload("res://vtt/creature_owner.gd")
const FILE_PATH := "user://creatures/creatures.json"
const FILE_VERSION := 1
const HISTORY_LIMIT := 30
const HISTORY_MAX_BYTES := 2 * 1024 * 1024
const HISTORY_COALESCE_MS := 800
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
			# Token links address creature IDs globally, not kind-qualified IDs.
			if incoming_ids.has(String(old.get("id", ""))):
				return ERR_ALREADY_EXISTS
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
	return _write(merged, _without_history_kind(loaded.get("undo", []), kind),
		_without_history_kind(loaded.get("redo", []), kind))


# Atomic operations for the creature-facing API: do not replace an entire kind
# when only a single sheet is edited, transferred, or removed.
func upsert(record: Dictionary, allow_transfer: bool = false) -> Error:
	var kind := String(record.get("kind", ""))
	var id := String(record.get("id", "")).strip_edges()
	if kind not in ["character", "monster"] or id.is_empty():
		return ERR_INVALID_PARAMETER
	if not allow_transfer and not Owner.is_owner(record):
		return ERR_UNAUTHORIZED
	var loaded := _load()
	if loaded.error != OK:
		return loaded.error
	var records: Array[Dictionary] = loaded.records
	for index: int in range(records.size()):
		var old: Dictionary = records[index]
		if String(old.get("id", "")) != id:
			continue
		if String(old.get("kind", "")) != kind:
			return ERR_ALREADY_EXISTS
		if not allow_transfer and not Owner.can_edit(record, old):
			return ERR_UNAUTHORIZED
		if old == record:
			return OK
		var undo_entries: Array = loaded.get("undo", []).duplicate(true)
		var redo_entries: Array = loaded.get("redo", []).duplicate(true)
		redo_entries = _without_history(redo_entries, kind, id)
		if allow_transfer:
			undo_entries = _without_history(undo_entries, kind, id)
		else:
			var now := int(Time.get_unix_time_from_system() * 1000)
			var coalesced := false
			if not undo_entries.is_empty():
				var last: Dictionary = undo_entries.back()
				if (
					String(last.get("kind", "")) == kind
					and String(last.get("id", "")) == id
					and last.get("after", {}) == old
					and now >= int(last.get("at", 0))
					and now - int(last.get("at", 0)) <= HISTORY_COALESCE_MS
				):
					last["after"] = record.duplicate(true)
					last["at"] = now
					undo_entries[undo_entries.size() - 1] = last
					coalesced = true
			if not coalesced:
				undo_entries.append({
					"kind": kind, "id": id,
					"before": old.duplicate(true), "after": record.duplicate(true),
					"at": now
				})
		records[index] = record.duplicate(true)
		_limit_history(undo_entries, redo_entries)
		return _write(records, undo_entries, redo_entries)
	records.append(record.duplicate(true))
	return _write(records, loaded.get("undo", []), loaded.get("redo", []))


func delete_record(record: Dictionary) -> Error:
	var kind := String(record.get("kind", ""))
	var id := String(record.get("id", "")).strip_edges()
	if kind not in ["character", "monster"] or id.is_empty():
		return ERR_INVALID_PARAMETER
	if not Owner.is_owner(record):
		return ERR_UNAUTHORIZED
	var loaded := _load()
	if loaded.error != OK:
		return loaded.error
	var records: Array[Dictionary] = loaded.records
	for index: int in range(records.size()):
		var old: Dictionary = records[index]
		if String(old.get("kind", "")) != kind or String(old.get("id", "")) != id:
			continue
		if not Owner.can_edit(record, old):
			return ERR_UNAUTHORIZED
		records.remove_at(index)
		return _write(records,
			_without_history(loaded.get("undo", []), kind, id),
			_without_history(loaded.get("redo", []), kind, id))
	return ERR_DOES_NOT_EXIST


# Undo is derived from the actual preceding persisted record, not UI widgets.
# The history stays in the same atomically replaced JSON as the creature.
func undo_owned(record: Dictionary, redo: bool = false) -> Error:
	var kind := String(record.get("kind", ""))
	var id := String(record.get("id", ""))
	if not Owner.is_owner(record):
		return ERR_UNAUTHORIZED
	var loaded := _load()
	if loaded.error != OK:
		return loaded.error
	var records: Array[Dictionary] = loaded.records
	var record_index := -1
	for index: int in range(records.size()):
		if String(records[index].get("id", "")) == id and String(records[index].get("kind", "")) == kind:
			record_index = index
			break
	if record_index < 0 or not Owner.is_owner(records[record_index]):
		return ERR_UNAUTHORIZED
	var undo_entries: Array = loaded.get("undo", []).duplicate(true)
	var redo_entries: Array = loaded.get("redo", []).duplicate(true)
	var source: Array = redo_entries if redo else undo_entries
	var source_index := -1
	for index: int in range(source.size() - 1, -1, -1):
		var entry: Dictionary = source[index]
		if String(entry.get("kind", "")) == kind and String(entry.get("id", "")) == id:
			source_index = index
			break
	if source_index < 0:
		return ERR_DOES_NOT_EXIST
	var entry: Dictionary = source[source_index]
	var expected: Variant = entry.get("before" if redo else "after", {})
	var replacement: Variant = entry.get("after" if redo else "before", {})
	if (
		not expected is Dictionary or not replacement is Dictionary
		or records[record_index] != expected
		or not Owner.can_edit(replacement as Dictionary, records[record_index])
	):
		return ERR_UNAUTHORIZED
	records[record_index] = (replacement as Dictionary).duplicate(true)
	source.remove_at(source_index)
	# Never coalesce a new edit into a history entry just restored by undo/redo.
	entry["at"] = 0
	if redo:
		undo_entries.append(entry)
	else:
		redo_entries.append(entry)
	_limit_history(undo_entries, redo_entries)
	return _write(records, undo_entries, redo_entries)


static func _without_history(entries: Array, kind: String, id: String) -> Array:
	var result: Array = []
	for value: Variant in entries:
		if not value is Dictionary:
			continue
		if String(value.get("kind", "")) == kind and String(value.get("id", "")) == id:
			continue
		result.append(value)
	return result


static func _without_history_kind(entries: Array, kind: String) -> Array:
	var result: Array = []
	for value: Variant in entries:
		if value is Dictionary and String(value.get("kind", "")) != kind:
			result.append(value)
	return result


static func _limit_history(undo_entries: Array, redo_entries: Array) -> void:
	while undo_entries.size() > HISTORY_LIMIT:
		undo_entries.pop_front()
	while redo_entries.size() > HISTORY_LIMIT:
		redo_entries.pop_front()
	while (
		not undo_entries.is_empty() or not redo_entries.is_empty()
	) and JSON.stringify({"undo": undo_entries, "redo": redo_entries}).to_utf8_buffer().size() > HISTORY_MAX_BYTES:
		if not undo_entries.is_empty():
			undo_entries.pop_front()
		else:
			redo_entries.pop_front()


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
		var seen_ids: Dictionary = {}
		for entry: Variant in parsed["creatures"]:
			if not entry is Dictionary:
				return {"error": ERR_FILE_CORRUPT, "records": []}
			var record: Dictionary = entry
			if String(record.get("kind", "")) not in ["character", "monster"]:
				return {"error": ERR_FILE_CORRUPT, "records": []}
			var id := String(record.get("id", "")).strip_edges()
			if id.is_empty() or seen_ids.has(id):
				return {"error": ERR_FILE_CORRUPT, "records": []}
			seen_ids[id] = true
			records.append(record.duplicate(true))
		if not parsed.get("undo", []) is Array or not parsed.get("redo", []) is Array:
			return {"error": ERR_FILE_CORRUPT, "records": []}
		return {"error": OK, "records": records,
			"undo": parsed.get("undo", []), "redo": parsed.get("redo", [])}
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
					if String(existing.get("id", "")) != id:
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


func _write(records: Array[Dictionary], undo_entries: Array = [], redo_entries: Array = []) -> Error:
	var folder := path.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	if error != OK:
		return error
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({
		"version": FILE_VERSION, "creatures": records,
		"undo": undo_entries, "redo": redo_entries
	}, "  "))
	error = file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary),
		ProjectSettings.globalize_path(path)
	)
