extends RefCounted

const CATALOG_PATH := "res://vtt/data/player_5etools_catalog.json"

static var _catalog: Dictionary = {}


static func _ensure_loaded() -> void:
	if not _catalog.is_empty():
		return
	if not FileAccess.file_exists(CATALOG_PATH):
		push_error("Player5eToolsCatalog: catalogo non trovato.")
		return
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("Player5eToolsCatalog: impossibile aprire il catalogo.")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_catalog = parsed as Dictionary
	else:
		push_error("Player5eToolsCatalog: JSON non valido.")


static func entries(category: String) -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	var value: Variant = _catalog.get(category, [])
	if value is Array:
		for item: Variant in value:
			if item is Dictionary:
				result.append((item as Dictionary).duplicate(true))
	return result


static func search(
	category: String,
	query: String = "",
	filters: Dictionary = {},
	limit: int = 120
) -> Array[Dictionary]:
	var normalized_query := query.strip_edges().to_lower()
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries(category):
		if not _matches_filters(entry, filters):
			continue
		if (
			not normalized_query.is_empty()
			and normalized_query not in _search_text(entry)
		):
			continue
		result.append(entry)
		if result.size() >= maxi(1, limit):
			break
	return result


static func _matches_filters(
	entry: Dictionary,
	filters: Dictionary
) -> bool:
	for raw_key: Variant in filters.keys():
		var key := String(raw_key)
		var expected: String = String(filters[raw_key]).strip_edges()
		if expected.is_empty():
			continue

		var actual_value: Variant = entry.get(key)
		if actual_value is Array:
			var found := false
			for array_value: Variant in actual_value:
				if (
					String(array_value).strip_edges().to_lower()
					== expected.to_lower()
				):
					found = true
					break
			if not found:
				return false
		elif (
			String(actual_value).strip_edges().to_lower()
			!= expected.to_lower()
		):
			return false
	return true


static func _search_text(entry: Dictionary) -> String:
	var values: PackedStringArray = []
	for key: String in [
		"name",
		"source",
		"type",
		"rarity",
		"weapon_category",
		"class_name",
		"class_source",
		"species",
		"base_species",
		"category",
		"script",
	]:
		if entry.has(key):
			values.append(String(entry.get(key, "")))
	return " ".join(values).to_lower()


static func display_label(entry: Dictionary) -> String:
	var name := String(entry.get("name", ""))
	var source := String(entry.get("source", ""))
	var details: PackedStringArray = []

	if entry.has("level") and int(entry.get("level", 0)) > 0:
		details.append("Lv %d" % int(entry.get("level", 0)))
	if not String(entry.get("rarity", "")).is_empty():
		var rarity := String(entry.get("rarity", ""))
		if rarity != "none":
			details.append(rarity)
	if not String(entry.get("weapon_category", "")).is_empty():
		details.append(String(entry.get("weapon_category", "")))

	var suffix := ""
	if not details.is_empty():
		suffix = " · " + " · ".join(details)
	if not source.is_empty():
		suffix += " · " + source
	return name + suffix
