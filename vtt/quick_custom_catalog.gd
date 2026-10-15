extends RefCounted

# Quick-created catalog definitions share the standard local homebrew package.
# Never write to res:// or mutate the bundled 5etools reference catalogs.
const PATH := "user://homebrew/quick_custom_catalog.json"
const NAMESPACE := "quick_local"
const ContentCatalog = preload("res://vtt/content_catalog.gd")
const ALLOWED := ["backgrounds", "feats", "items"]
const PROFICIENCY_FIELDS := {
	"skill": "skillProficiencies", "tool": "toolProficiencies",
	"language": "languageProficiencies", "weapon": "weaponProficiencies",
	"armor": "armorProficiencies", "save": "saveProficiencies",
	"expertise": "expertise"
}


static func is_custom(entry: Dictionary) -> bool:
	return String(entry.get("id", "")).begins_with("homebrew:" + NAMESPACE + ":")


static func _document() -> Dictionary:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file != null:
		var raw: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if raw is Dictionary:
			var data: Dictionary = raw
			if data.get("schema_version") == 1 and data.get("namespace") == NAMESPACE and data.get("entries") is Array:
				return data
		# A corrupt or unrelated existing file must never be overwritten.
		return {}
	return {"schema_version": 1, "namespace": NAMESPACE, "entries": []}


static func _persist(doc: Dictionary) -> bool:
	var encoded: String = JSON.stringify(doc, "  ") + "\n"
	# Never replace a valid package with one the catalog refuses to load.
	if encoded.to_utf8_buffer().size() > ContentCatalog.MAX_FILE_BYTES:
		return false
	var folder: String = PATH.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
		return false
	var path: String = ProjectSettings.globalize_path(PATH)
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(encoded)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return false
	# Replace the previous file only after the new one has been written.
	var err: Error = DirAccess.rename_absolute(temporary, path)
	if err != OK and FileAccess.file_exists(path):
		# Windows does not always replace an existing destination on rename.
		# Use a backup to restore the old package if the second move fails.
		var backup: String = path + ".bak"
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(path, backup) == OK:
			err = DirAccess.rename_absolute(temporary, path)
			if err != OK:
				DirAccess.rename_absolute(backup, path)
			else:
				DirAccess.remove_absolute(backup)
	if err != OK:
		DirAccess.remove_absolute(temporary)
		return false
	ContentCatalog.reload_homebrew()
	return true


static func create(category: String, name: String, description: String,
		proficiencies: Array[Dictionary] = [], details: Dictionary = {}) -> Dictionary:
	name = name.strip_edges()
	if category not in ALLOWED or name.is_empty() or name.length() > 120:
		return {}
	# Background and feat identities use (source, name), not a catalog ID.
	# Reject colliding labels so one selection cannot merge two origins.
	for existing: Dictionary in ContentCatalog.home_entries(category):
		if is_custom(existing) and String(existing.get("name", "")).nocasecmp_to(name) == 0:
			return {}
	var doc: Dictionary = _document()
	if doc.is_empty():
		return {}
	var id: String = "local_%s_%s" % [
		str(int(Time.get_unix_time_from_system())),
		Crypto.new().generate_random_bytes(8).hex_encode()
	]
	var data: Dictionary = {"description": description.strip_edges(), "entries": [description.strip_edges()]}
	if category == "items":
		data["type"] = String(details.get("type", "OTH"))
		data["custom_item_type"] = String(details.get("custom_item_type", "other"))
		data["rarity"] = String(details.get("rarity", "none"))
		data["value"] = maxi(0, int(details.get("value", 0)))
		data["value_gp"] = data["value"]
	else:
		for row: Dictionary in proficiencies:
			var kind: String = String(row.get("kind", ""))
			var key: String = String(row.get("key", "")).strip_edges().to_lower()
			var field: String = String(PROFICIENCY_FIELDS.get(kind, ""))
			if field.is_empty() or key.is_empty():
				continue
			if not data.has(field):
				data[field] = []
			var values: Array = data[field]
			var grant: Dictionary = {key: true}
			if grant not in values:
				values.append(grant)
	var entry: Dictionary = {
		"id": id, "name": name, "category": category,
		"source": "Personalizzato", "data": data
	}
	(doc["entries"] as Array).append(entry)
	if not _persist(doc):
		return {}
	return {"id": "homebrew:%s:%s:%s" % [NAMESPACE, category, id],
		"name": name, "category": category, "source": "Personalizzato",
		"origin": "homebrew"}


static func remove(entry: Dictionary) -> bool:
	if not is_custom(entry):
		return false
	var parts: PackedStringArray = String(entry.get("id", "")).split(":")
	if parts.size() != 4 or parts[2] not in ALLOWED:
		return false
	# An imported definition can live in portable_imports rather than the
	# original quick-create package. Allow deletion from either location,
	# without ever accepting filesystem separators from a remote ID.
	var local_id: String = parts[3]
	var valid := RegEx.create_from_string("^[a-z0-9][a-z0-9_-]{0,63}$")
	if valid.search(local_id) == null:
		return false
	var changed := false
	var doc: Dictionary = _document()
	if not doc.is_empty():
		var retained: Array = []
		for raw: Variant in doc["entries"]:
			if raw is Dictionary and String(raw.get("id", "")) == local_id and String(raw.get("category", "")) == parts[2]:
				changed = true
				continue
			retained.append(raw)
		if changed:
			doc["entries"] = retained
			if not _persist(doc):
				return false
	var imported: String = "user://homebrew/portable_imports/%s/%s_%s.json" % [
		NAMESPACE, parts[2], local_id]
	if FileAccess.file_exists(imported):
		# Only delete the expected single-entry package, never an unrelated
		# user file that happens to share a path.
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(imported))
		if saved is Dictionary and String(saved.get("namespace", "")) == NAMESPACE:
			var entries: Variant = saved.get("entries", [])
			if entries is Array and entries.size() == 1:
				var candidate: Variant = entries[0]
				if candidate is Dictionary and String(candidate.get("id", "")) == local_id and String(candidate.get("category", "")) == parts[2]:
					if DirAccess.remove_absolute(ProjectSettings.globalize_path(imported)) == OK:
						changed = true
	if changed:
		ContentCatalog.reload_homebrew()
	return changed
