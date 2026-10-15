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
	return {"schema_version": 1, "namespace": NAMESPACE, "entries": []}


static func _persist(doc: Dictionary) -> bool:
	var folder: String = PATH.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
		return false
	var path: String = ProjectSettings.globalize_path(PATH)
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(doc, "  ") + "\n")
	file.flush()
	file.close()
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
	var doc: Dictionary = _document()
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
	var doc: Dictionary = _document()
	var retained: Array = []
	var found := false
	for raw: Variant in doc["entries"]:
		if raw is Dictionary and String(raw.get("id", "")) == parts[3] and String(raw.get("category", "")) == parts[2]:
			found = true
			continue
		retained.append(raw)
	if not found:
		return false
	doc["entries"] = retained
	return _persist(doc)
