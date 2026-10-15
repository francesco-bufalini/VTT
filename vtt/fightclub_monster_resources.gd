extends RefCounted

# Generated Fight Club 5e monster counters; all XML is converted offline.
# Source-qualified names prevent a variant from inheriting another book's uses.
const PATHS: Array[String] = [
	"res://vtt/data/fightclub_monster_resources_2014_a.json",
	"res://vtt/data/fightclub_monster_resources_2014_b.json",
	"res://vtt/data/fightclub_monster_resources_2014_c.json"
]
static var _loaded := false
static var _index: Dictionary = {}


static func for_monster(record: Dictionary) -> Array[Dictionary]:
	if String(record.get("kind", "")) != "monster":
		return []
	_ensure_loaded()
	var stat_value: Variant = record.get("stat_block", {})
	if not stat_value is Dictionary:
		return []
	var stat: Dictionary = stat_value as Dictionary
	var source: String = String(stat.get("source", record.get("source", ""))).strip_edges().to_upper()
	var name: String = String(stat.get("name", record.get("base_name", ""))).strip_edges().to_lower()
	if source.is_empty() or name.is_empty():
		return []
	var found: Variant = _index.get(source + "|" + name, [])
	var output: Array[Dictionary] = []
	if found is Array:
		for value: Variant in found:
			if value is Dictionary:
				output.append((value as Dictionary).duplicate(true))
	return output


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path: String in PATHS:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_warning("Fight Club monster supplement not found: " + path)
			continue
		if file.get_length() > 2 * 1024 * 1024:
			push_warning("Fight Club monster supplement too large: " + path)
			file.close()
			continue
		var raw: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if not raw is Dictionary:
			continue
		var document: Dictionary = raw as Dictionary
		if document.get("schema_version") != 1 or document.get("edition") != "2014":
			continue
		var monsters_value: Variant = document.get("monsters", [])
		if not monsters_value is Array:
			continue
		for value: Variant in monsters_value:
			if not value is Dictionary:
				continue
			var row: Dictionary = value as Dictionary
			var source: String = String(row.get("source", "")).strip_edges().to_upper()
			var name: String = String(row.get("name", "")).strip_edges().to_lower()
			var resources: Variant = row.get("resources", [])
			if source.is_empty() or name.is_empty() or not resources is Array:
				continue
			var key: String = source + "|" + name
			# Duplicate catalog names must not silently override first definitions.
			if not _index.has(key):
				_index[key] = (resources as Array).duplicate(true)
