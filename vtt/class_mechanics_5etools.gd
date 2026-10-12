extends RefCounted

# Compact structured 5etools classTableGroups and hd; generated from upstream
# class JSON, not copied class-specific progressions or translated display names.
const PATH := "res://vtt/data/class_mechanics_5etools.json"
static var _rows: Dictionary = {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("Class mechanics index unavailable: " + PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	for value: Variant in (parsed as Dictionary).get("classes", []):
		if not value is Dictionary:
			continue
		var row: Dictionary = value
		var key: String = String(row.get("name", "")).to_lower()
		if key.is_empty():
			continue
		if not _rows.has(key):
			_rows[key] = {}
		var editions: Dictionary = _rows[key]
		editions[String(row.get("source", "")).to_upper()] = row


static func class_row(klass_name: String, source: String = "") -> Dictionary:
	_ensure_loaded()
	var sources: Dictionary = _rows.get(klass_name.strip_edges().to_lower(), {})
	var edition: String = source.to_upper()
	if sources.has(edition):
		return sources[edition]
	# Pre-existing sheets may lack a book source. Use the original PHB first,
	# then the 2024 PHB, retaining third-party classes as a last fallback.
	for book: String in ["PHB", "XPHB", "TCE"]:
		if sources.has(book):
			return sources[book]
	for book: String in sources.keys():
		return sources[book]
	return {}


static func hit_die(klass_name: String, source: String = "") -> int:
	return maxi(0, int(class_row(klass_name, source).get("hit_die", 0)))


static func column(klass_name: String, source: String, label: String) -> Dictionary:
	for raw: Variant in class_row(klass_name, source).get("columns", []):
		if raw is Dictionary and String((raw as Dictionary).get("name", "")) == label:
			return raw
	return {}


static func column_value(klass_name: String, source: String, label: String, level: int) -> Variant:
	var data: Dictionary = column(klass_name, source, label)
	var values: Variant = data.get("levels", [])
	if not values is Array or level < 1 or level > (values as Array).size():
		return null
	return (values as Array)[level - 1]


static func resource_columns(klass_name: String, source: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in class_row(klass_name, source).get("columns", []):
		if value is Dictionary and String((value as Dictionary).get("kind", "")) == "resource":
			result.append(value)
	return result
