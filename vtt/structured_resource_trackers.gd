extends RefCounted

# Resource counters backed by numeric 5etools JSON fields or formal 5etools
# {@recharge ...} markup. This module never interprets feature prose.
const ClassMechanics = preload("res://vtt/class_mechanics_5etools.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")


static func for_creature(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if String(record.get("kind", "")) == "monster":
		_append_monster_trackers(record, result)
	_append_class_trackers(record, result)
	_assign_automatic_origins(record, result)
	_append_saved_trackers(record, result)
	return result


# Keep machine-derived counters, but allow additional user-defined resources.
# Their current uses remain in resource_tracker_spent, keyed by stable ID.
static func _append_saved_trackers(record: Dictionary, output: Array[Dictionary]) -> void:
	var seen: Dictionary = {}
	for existing: Dictionary in output:
		seen[String(existing.get("id", ""))] = true
	var saved: Variant = record.get("resource_trackers", [])
	if not saved is Array:
		return
	for raw: Variant in saved:
		if not raw is Dictionary:
			continue
		var data: Dictionary = raw
		var tracker_id: String = String(data.get("id", ""))
		var title: String = String(data.get("name", "")).strip_edges()
		if tracker_id.is_empty() or title.is_empty() or seen.has(tracker_id):
			continue
		seen[tracker_id] = true
		output.append({
			"id": tracker_id, "name": title,
			"max": maxi(0, int(data.get("max", 0))),
			"origin": String(data.get("origin_name", "Senza origine")),
			"origin_id": String(data.get("origin_id", "")),
			"origin_name": String(data.get("origin_name", "Senza origine")),
			"recharge": String(data.get("recharge", "manual")),
			"disabled": bool(data.get("disabled", false)),
			"automatic": false
		})


# Connect automatic counters to a real trait whenever possible. Only
# otherwise use a stable internal counter identity, not an invented feat.
static func _assign_automatic_origins(record: Dictionary, output: Array[Dictionary]) -> void:
	if output.is_empty():
		return
	var features: Array[Dictionary] = Traits.collect_features(record)
	for row: Dictionary in output:
		row["automatic"] = true
		row["disabled"] = false
		var label: String = String(row.get("origin", row.get("name", "")))
		var origin_id := ""
		var wanted: String = label.strip_edges().to_lower()
		for feature: Dictionary in features:
			var feature_name: String = String(feature.get("name", "")).strip_edges().to_lower()
			if wanted != feature_name and not feature_name.begins_with(wanted + " {") and not feature_name.begins_with(wanted + " ("):
				continue
			origin_id = "feature:" + String(feature.get("key", ""))
			label = "Tratto · " + String(feature.get("name", ""))
			break
		if origin_id.is_empty():
			origin_id = "tracker:auto:" + String(row.get("id", ""))
		row["origin_id"] = origin_id
		row["origin_name"] = label


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
	var classes: Array = raw_classes as Array if raw_classes is Array else []
	# Old character files can have the primary class only in legacy fields.
	if classes.is_empty() and not String(record.get("class", "")).is_empty():
		classes = [{
			"name": record.get("class", ""),
			"source": record.get("class_source", ""),
			"level": record.get("level", 0)
		}]
	var seen: Dictionary = {}
	for raw_class: Variant in classes:
		if not raw_class is Dictionary:
			continue
		var class_data: Dictionary = raw_class as Dictionary
		var selected_class_name: String = String(class_data.get("name", "")).to_lower()
		var class_source: String = String(class_data.get("source", "")).to_upper()
		var class_level: int = int(class_data.get("level", 0))
		if class_level < 1 or class_level > 20:
			continue
		# Use the resolved 5etools source for the tracker identity as well as
		# for its progression. Legacy sheets may omit the class source: using
		# an empty source in the ID would split the same PHB resource into
		# separate spent-use keys.
		var class_row: Dictionary = ClassMechanics.class_row(selected_class_name, class_source)
		var resolved_source: String = String(class_row.get("source", class_source)).to_upper()
		for definition: Dictionary in ClassMechanics.resource_columns(selected_class_name, resolved_source):
			var levels_value: Variant = definition.get("levels", [])
			if not levels_value is Array:
				continue
			var levels: Array = levels_value
			if class_level > levels.size():
				continue
			var maximum: Variant = levels[class_level - 1]
			# Preserve the existing finite counter behavior. 'unlimited' is
			# retained in the generated source data, not cast to an arbitrary max.
			if not (maximum is int or maximum is float) or int(maximum) <= 0:
				continue
			var column: String = String(definition.get("name", ""))
			var id: String = "class:%s:%s:%s" % [
				selected_class_name, resolved_source.to_lower(), column.to_lower().replace(" ", "_")
			]
			if seen.has(id):
				continue
			seen[id] = true
			output.append({
				"id": id,
				"name": column,
				"max": int(maximum),
				"origin": String(definition.get("origin_feature", column)),
				"recharge": "manual",
				"source_label": "%s · %s" % [
					String(class_data.get("name", "")), resolved_source
				]
			})
