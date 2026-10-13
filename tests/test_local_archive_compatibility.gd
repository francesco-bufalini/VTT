extends SceneTree

const Characters = preload("res://vtt/player_character_store.gd")
const Monsters = preload("res://vtt/master_creature_store.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var file_count := 0
	var record_count := 0
	for spec: Dictionary in [
		{"path": Characters.ROOT_DIR, "key": "characters", "version": Characters.FILE_VERSION},
		{"path": Monsters.ROOT_DIR, "key": "creatures", "version": Monsters.FILE_VERSION}
	]:
		var directory := DirAccess.open(String(spec["path"]))
		if directory == null:
			continue
		for filename: String in directory.get_files():
			if not filename.ends_with(".json"):
				continue
			var path: String = String(spec["path"]).path_join(filename)
			var raw_text := FileAccess.get_file_as_string(path)
			var parsed: Variant = JSON.parse_string(raw_text)
			assert(parsed is Dictionary, "Invalid local archive: " + filename)
			var data: Dictionary = parsed
			assert(int(data.get("version", 1)) <= int(spec["version"]), "Archive from a newer application: " + filename)
			assert(data.get(spec["key"], []) is Array, "Invalid archive records")
			for raw: Variant in data.get(spec["key"], []):
				assert(raw is Dictionary)
				var record: Dictionary = raw
				var normalized: Dictionary
				if spec["key"] == "characters":
					normalized = Characters.new().normalize_character(record.duplicate(true))
				else:
					normalized = Monsters.new().normalize_creature(record.duplicate(true))
				for key: String in ["id", "name", "owner_id"]:
					if record.has(key):
						assert(normalized.get(key) == record[key], "Normalization changed identity")
				record_count += 1
			assert(FileAccess.get_file_as_string(path) == raw_text, "Compatibility audit must not write archives")
			file_count += 1
	print("PASS: %d local archive files and %d records load with current schemas; identities preserved; no files rewritten" % [file_count, record_count])
	quit()