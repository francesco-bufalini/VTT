extends RefCounted

# Runtime/computed data belongs here, not in 5etools JSON or live creature saves.
# Each overlay targets the exact catalog ID; it never changes its source record.
const BUNDLED_DIR := "res://vtt/enrichment"
const USER_DIR := "user://vtt_enrichment"
const MAX_FILE_BYTES := 2 * 1024 * 1024
const CATEGORIES := ["spells", "monsters", "items", "races", "classes", "subclasses", "subclass_features", "class_features", "species_traits", "feats", "backgrounds", "optional_features", "conditions", "diseases", "effects"]
const PROTECTED_FIELDS := ["id", "name", "source", "category", "origin", "asset_dir", "overrides", "quantity", "equipped_slots", "inventory", "hp_current", "current_hp", "owner_id", "instance_overrides"]

static var _loaded := false
static var _overlays: Dictionary = {}
static var diagnostics: Array[String] = []


static func reload(paths: Array[String] = [BUNDLED_DIR, USER_DIR]) -> void:
	_overlays.clear()
	diagnostics.clear()
	_loaded = true
	for path: String in paths:
		_load_directory(path, 0)


static func _load_directory(path: String, depth: int) -> void:
	if depth > 4:
		diagnostics.append("Integrazione: profondità massima: " + path)
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	var files: PackedStringArray = directory.get_files()
	files.sort()
	for filename: String in files:
		if filename.ends_with(".json") and not filename.ends_with(".schema.json"):
			_load_file(path.path_join(filename))
	var folders: PackedStringArray = directory.get_directories()
	folders.sort()
	for folder: String in folders:
		if not folder.begins_with(".") and folder not in ["examples", "templates"]:
			_load_directory(path.path_join(folder), depth + 1)


static func _load_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		diagnostics.append("Integrazione: file illeggibile o troppo grande: " + path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		diagnostics.append("Integrazione: JSON non valido: " + path)
		return
	var document: Dictionary = parsed
	var category: String = String(document.get("category", ""))
	if document.get("schema_version") != 1 or category not in CATEGORIES or not document.get("entries") is Array:
		diagnostics.append("Integrazione: schema non valido: " + path)
		return
	for raw: Variant in document.entries:
		if not raw is Dictionary:
			diagnostics.append("Integrazione: voce non valida: " + path)
			continue
		var row: Dictionary = raw
		var catalog_id: String = String(row.get("id", "")).strip_edges()
		var fields: Variant = row.get("fields", {})
		if catalog_id.is_empty() or not fields is Dictionary:
			diagnostics.append("Integrazione: ID/campi mancanti: " + path)
			continue
		var key: String = category + "|" + catalog_id
		var combined: Dictionary = (_overlays.get(key, {}) as Dictionary).duplicate(true)
		for raw_field: Variant in (fields as Dictionary).keys():
			var field: String = String(raw_field)
			if field in PROTECTED_FIELDS:
				diagnostics.append("Integrazione: campo riservato ignorato: " + field)
				continue
			combined[field] = (fields as Dictionary)[raw_field]
		_overlays[key] = combined


static func apply_to(category: String, definition: Dictionary) -> Dictionary:
	if not _loaded:
		reload()
	var result: Dictionary = definition.duplicate(true)
	if category == "items":
		# Adapt native 5etools names only on the catalog view.
		# Use unambiguous key mappings rather than typed nested-array loops.
		var item_fields: Dictionary = {
			"dmg1": "damage",
			"dmg2": "versatile_damage",
			"dmgType": "damage_type",
			"property": "properties"
		}
		for raw_name: String in item_fields.keys():
			var runtime_name: String = String(item_fields[raw_name])
			if result.has(raw_name) and not result.has(runtime_name):
				result[runtime_name] = result[raw_name]
	var catalog_id: String = String(result.get("id", ""))
	var extension: Variant = _overlays.get(category + "|" + catalog_id, {})
	if extension is Dictionary:
		for field: Variant in (extension as Dictionary).keys():
			result[field] = (extension as Dictionary)[field]
	return result


static func extension_for(category: String, catalog_id: String) -> Dictionary:
	if not _loaded:
		reload()
	var extension: Variant = _overlays.get(category + "|" + catalog_id, {})
	return (extension as Dictionary).duplicate(true) if extension is Dictionary else {}
