extends RefCounted

# Nonspell activated capabilities use the existing grant/target/tracker
# pipeline, but carry their own identity and do not gain spell metadata.
const PlayerCatalog = preload("res://vtt/player_5etools_catalog.gd")
const PATH := "res://vtt/data/activated_abilities_5etools.json"
static var _loaded := false
static var _by_id: Dictionary = {}
static var _by_option: Dictionary = {}


static func is_ability(entry: Dictionary) -> bool:
	return String(entry.get("action_kind", entry.get("kind", "spell"))) == "ability"


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	for raw: Variant in (parsed as Dictionary).get("abilities", []):
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		var id: String = String(row.get("id", ""))
		if id.is_empty():
			continue
		_by_id[id] = row
		_by_option[_option_key(String(row.get("name", "")), String(row.get("source", "")))] = row


static func _option_key(name: String, source: String) -> String:
	return name.strip_edges().to_lower() + "|" + source.strip_edges().to_lower()


static func definition(id: String) -> Dictionary:
	_load()
	var raw: Variant = _by_id.get(id, {})
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return {}
	var definition: Dictionary = (raw as Dictionary).duplicate(true)
	# No spell school, level or casting components belong to abilities.
	definition.erase("school")
	definition.erase("components")
	definition.erase("level")
	definition["action_kind"] = "ability"
	if String(definition.get("description", "")).is_empty():
		definition["description"] = PlayerCatalog.description_text("optional_features", definition)
	return definition


static func selected_optional_features(record: Dictionary) -> Array[Dictionary]:
	_load()
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	var edition: String = String(record.get("rules_version", "2014"))
	for raw: Variant in record.get("optional_features_catalog", []):
		if not raw is Dictionary or bool((raw as Dictionary).get("disabled", false)):
			continue
		var option: Dictionary = raw
		var name: String = String(option.get("name", ""))
		var source: String = String(option.get("source", ""))
		var key: String = _option_key(name, source)
		var match_value: Variant = _by_option.get(key, {})
		if match_value is Dictionary and (match_value as Dictionary).is_empty():
			# Older sheets sometimes omit the source. Do not select an
			# arbitrary edition if the maneuver has multiple definitions.
			if source.is_empty():
				key = _option_key(name, "XPHB" if edition == "2024" else "PHB")
				match_value = _by_option.get(key, {})
				if match_value is Dictionary and (match_value as Dictionary).is_empty():
					key = _option_key(name, "TCE")
					match_value = _by_option.get(key, {})
		if not match_value is Dictionary or (match_value as Dictionary).is_empty():
			continue
		var id: String = String((match_value as Dictionary).get("id", ""))
		if seen.has(id):
			continue
		seen[id] = true
		result.append(definition(id))
	return result
