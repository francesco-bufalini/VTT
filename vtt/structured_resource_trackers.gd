extends RefCounted

# Resource counters backed by numeric 5etools JSON fields or formal 5etools
# {@recharge ...} markup. This module never interprets feature prose.
const PROGRESSIONS_PATH := "res://vtt/data/structured_resource_progressions_5etools.json"

static var _cached_progressions: Array[Dictionary] = []


static func for_creature(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if String(record.get("kind", "")) == "monster":
		_append_monster_trackers(record, result)
	_append_class_trackers(record, result)
	return result


static func _append_monster_trackers(record: Dictionary, output: Array[Dictionary]) -> void:
	var raw: Variant = record.get("stat_block", {})
	if not raw is Dictionary:
		return
	var stat: Dictionary = raw as Dictionary
	# 5etools has an explicit top-level count for some legendary monsters.
	var action_count: Variant = stat.get("legendaryActions", null)
	if (action_count is int or action_count is float) and int(action_count) > 0:
		output.append({
			"id": "legendary_actions",
			"name": "Azioni leggendarie",
			"max": int(action_count),
			"origin": "Azioni leggendarie",
			"recharge": "turn"
		})
	# The recharge tag is machine-readable syntax, not a natural-language
	# expression such as "(Recharges after a Short or Long Rest)".
	for section: String in ["trait", "action", "bonus", "reaction", "legendary", "mythic"]:
		var section_value: Variant = stat.get(section, [])
		if not section_value is Array:
			continue
		var entries: Array = section_value as Array
		for index: int in range(entries.size()):
			if not entries[index] is Dictionary:
				continue
			var feature: Dictionary = entries[index] as Dictionary
			var title: String = String(feature.get("name", ""))
			var match_data: Dictionary = _recharge_markup(title)
			if match_data.is_empty():
				continue
			output.append({
				"id": "recharge:%s:%d" % [section, index],
				"name": String(match_data["name"]),
				"max": 1,
				"origin": String(match_data["name"]),
				"recharge": "d6",
				"recharge_min": int(match_data["min"])
			})


static func _recharge_markup(title: String) -> Dictionary:
	var regex := RegEx.new()
	if regex.compile("\\{@recharge(?: ([1-6]))?\\}") != OK:
		return {}
	var found: RegExMatch = regex.search(title)
	if found == null:
		return {}
	var threshold: int = 6
	if not found.get_string(1).is_empty():
		threshold = int(found.get_string(1))
	var clean_name: String = title.replace(found.get_string(0), "").strip_edges()
	if clean_name.is_empty():
		return {}
	return {"name": clean_name, "min": threshold}


static func _append_class_trackers(record: Dictionary, output: Array[Dictionary]) -> void:
	var raw_classes: Variant = record.get("classes", [])
	if not raw_classes is Array:
		return
	var definitions: Array[Dictionary] = _progressions()
	var seen: Dictionary = {}
	for raw_class: Variant in raw_classes as Array:
		if not raw_class is Dictionary:
			continue
		var class_data: Dictionary = raw_class as Dictionary
		var class_name: String = String(class_data.get("name", "")).to_lower()
		var class_source: String = String(class_data.get("source", "")).to_upper()
		var class_level: int = int(class_data.get("level", 0))
		if class_level < 1 or class_level > 20:
			continue
		for definition: Dictionary in definitions:
			if String(definition.get("class_name", "")).to_lower() != class_name:
				continue
			if String(definition.get("class_source", "")).to_upper() != class_source:
				continue
			var levels_value: Variant = definition.get("levels", [])
			if not levels_value is Array:
				continue
			var levels: Array = levels_value as Array
			if class_level > levels.size():
				continue
			var maximum: Variant = levels[class_level - 1]
			if not (maximum is int or maximum is float) or int(maximum) <= 0:
				continue
			var column: String = String(definition.get("column", ""))
			var id: String = "class:%s:%s:%s" % [
				class_name, class_source.to_lower(), column.to_lower().replace(" ", "_")
			]
			if seen.has(id):
				continue
			seen[id] = true
			output.append({
				"id": id,
				"name": String(definition.get("name", column)),
				"max": int(maximum),
				"origin": String(definition.get("origin_feature", column)),
				"recharge": "manual",
				"source_label": "%s · %s" % [
					String(class_data.get("name", "")), class_source
				]
			})


static func _progressions() -> Array[Dictionary]:
	if not _cached_progressions.is_empty():
		return _cached_progressions
	var file := FileAccess.open(PROGRESSIONS_PATH, FileAccess.READ)
	if file == null:
		return []
	var decoded: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not decoded is Dictionary:
		return []
	var values: Variant = (decoded as Dictionary).get("resources", [])
	if values is Array:
		for value: Variant in values:
			if value is Dictionary:
				_cached_progressions.append(value as Dictionary)
	return _cached_progressions
