extends RefCounted

# Copy legacy per-campaign/scenario archives to the shared local archive once.
# Leave source files untouched so a migration can always be reversed manually.
static func migrate(target_path: String, legacy_dir: String, records_key: String, version: int) -> void:
	if FileAccess.file_exists(target_path):
		return
	var result: Array = []
	var by_id: Dictionary = {}
	var files := DirAccess.get_files_at(legacy_dir)
	files.sort()
	for file_name: String in files:
		if not file_name.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(legacy_dir.path_join(file_name)))
		if not parsed is Dictionary:
			continue
		var entries: Variant = (parsed as Dictionary).get(records_key, [])
		if not entries is Array:
			continue
		for entry: Variant in entries:
			if not entry is Dictionary:
				continue
			var record: Dictionary = (entry as Dictionary).duplicate(true)
			var record_id := String(record.get("id", ""))
			if record_id.is_empty():
				record_id = "legacy_" + (file_name + JSON.stringify(record)).sha256_text().substr(0, 16)
				record["id"] = record_id
			if by_id.has(record_id):
				var existing: Dictionary = result[int(by_id[record_id])]
				if JSON.stringify(existing) == JSON.stringify(record):
					continue
				# Conflicting historic versions cannot share an ID in one archive.
				# Keep both rather than discarding a sheet.
				record_id = record_id + "_legacy_" + (file_name + JSON.stringify(record)).sha256_text().substr(0, 12)
				while by_id.has(record_id):
					record_id += "_copy"
				record["id"] = record_id
			by_id[record_id] = result.size()
			result.append(record)
	var parent := target_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent))
	var temporary := target_path + ".tmp"
	var writer := FileAccess.open(temporary, FileAccess.WRITE)
	if writer == null:
		push_error("Cannot migrate creature archive: " + target_path)
		return
	var payload: Dictionary = {"version": version, "scope": "global"}
	payload[records_key] = result
	writer.store_string(JSON.stringify(payload, "  "))
	var error := writer.get_error()
	writer.close()
	if error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(target_path)) != OK:
		push_error("Cannot commit migrated creature archive: " + target_path)
