extends RefCounted
## Versioned 5etools/Fight Club mechanic supplements. Strict structured matching;
## never infer timings or recoveries from feature descriptions at runtime.
const PATH := "res://vtt/data/feature_timing_recovery_rules.json"
static var _loaded := false
static var _actions: Array[Dictionary] = []
static var _recoveries: Array[Dictionary] = []

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1:
		push_warning("Feature mechanic catalog not available")
		return
	for raw: Variant in parsed.get("actions", []):
		if raw is Dictionary:
			_actions.append(raw)
	for raw: Variant in parsed.get("recoveries", []):
		if raw is Dictionary:
			_recoveries.append(raw)

static func _subclass_key(value: String) -> String:
	var name := value.strip_edges().to_lower()
	for prefix: String in ["circle of ", "the ", "way of ", "oath of ", "school of "]:
		if name.begins_with(prefix):
			name = name.substr(prefix.length())
	return name

static func _members(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = record.get("classes", [])
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary:
				result.append(entry)
	if result.is_empty() and not String(record.get("class", "")).is_empty():
		result.append({
			"name": record.get("class", ""),
			"source": record.get("class_source", ""),
			"level": record.get("level", 0),
			"subclass": record.get("subclass", "")
		})
	return result

static func _member_for(record: Dictionary, rule: Dictionary) -> Dictionary:
	var edition := "XPHB" if String(record.get("rules_version", "2014")) == "2024" else "PHB"
	for row: Dictionary in _members(record):
		if String(row.get("name", "")).nocasecmp_to(String(rule.get("class_name", ""))) != 0:
			continue
		var source := String(row.get("source", "")).to_upper()
		if source.is_empty():
			source = edition
		if source != String(rule.get("class_source", "")).to_upper():
			continue
		if int(row.get("level", 0)) < int(rule.get("min_level", 1)):
			continue
		var required := String(rule.get("subclass", ""))
		if not required.is_empty():
			var chosen := String(row.get("subclass", record.get("subclass", "")))
			if _subclass_key(chosen) != _subclass_key(required):
				continue
		return row
	return {}

static func _tracker_for(member: Dictionary, rule: Dictionary, trackers: Array[Dictionary]) -> Dictionary:
	var source := String(rule.get("class_source", "")).to_lower()
	var klass := String(rule.get("class_name", "")).to_lower()
	var wanted := String(rule.get("resource_name", rule.get("tracker_name", "")))
	for tracker: Dictionary in trackers:
		if not String(tracker.get("id", "")).begins_with("class:" + klass + ":" + source + ":"):
			continue
		if String(tracker.get("name", "")).nocasecmp_to(wanted) == 0:
			return tracker
	return {}

static func action_entries(record: Dictionary, trackers: Array[Dictionary]) -> Array[Dictionary]:
	_load()
	var by_action: Dictionary = {}
	for rule: Dictionary in _actions:
		var member := _member_for(record, rule)
		if member.is_empty():
			continue
		var key := String(rule.get("action_id", ""))
		if key.is_empty():
			continue
		if not by_action.has(key) or int(rule.get("priority", 0)) > int((by_action[key] as Dictionary).get("priority", 0)):
			by_action[key] = rule
	var result: Array[Dictionary] = []
	for key: String in by_action:
		var rule: Dictionary = by_action[key]
		var member := _member_for(record, rule)
		var tracker := _tracker_for(member, rule, trackers)
		result.append({
			"name": String(rule.get("name", key)),
			"activation": String(rule.get("activation", "action")),
			"action_id": key,
			"tracker": String(tracker.get("name", rule.get("tracker_name", ""))),
			"tracker_id": String(tracker.get("id", "")),
			"detail": String(rule.get("detail", "")),
			"feature": String(rule.get("feature", "")),
			"rule_id": String(rule.get("id", ""))
		})
	return result

static func apply_tracker_rules(record: Dictionary, trackers: Array[Dictionary]) -> void:
	_load()
	for rule: Dictionary in _recoveries:
		var member := _member_for(record, rule)
		if member.is_empty():
			continue
		var tracker := _tracker_for(member, rule, trackers)
		if tracker.is_empty():
			continue
		var event := String(rule.get("event", ""))
		var mode := String(rule.get("mode", ""))
		if mode == "full" and event in ["short_rest", "long_rest", "turn"]:
			# Full short-rest recovery supersedes a long-rest-only baseline.
			if event == "short_rest" or String(tracker.get("recharge", "")) != "short_rest":
				tracker["recharge"] = event
		elif mode in ["partial", "optional_partial"]:
			var existing: Array = tracker.get("partial_recoveries", [])
			existing.append(rule.duplicate(true))
			tracker["partial_recoveries"] = existing

static func recovery_patch(record: Dictionary, event: String, trackers: Array[Dictionary]) -> Dictionary:
	var saved: Variant = record.get("resource_tracker_spent", {})
	var spent: Dictionary = (saved as Dictionary).duplicate(true) if saved is Dictionary else {}
	if event not in ["short_rest", "long_rest", "turn"]:
		return {"resource_tracker_spent": spent}
	var ready: Dictionary = record.get("resource_recovery_ready", {}).duplicate(true)
	var used: Dictionary = record.get("resource_recovery_used", {}).duplicate(true)
	for tracker: Dictionary in trackers:
		var id := String(tracker.get("id", ""))
		if bool(tracker.get("disabled", false)):
			continue
		var recharge := String(tracker.get("recharge", "manual"))
		if recharge == event or (event == "long_rest" and recharge == "short_rest"):
			spent.erase(id)
		if event != "short_rest":
			continue
		for rule: Variant in tracker.get("partial_recoveries", []):
			if not rule is Dictionary or String(rule.get("event", "")) != event:
				continue
			var rid := String(rule.get("id", ""))
			if String(rule.get("mode", "")) == "optional_partial":
				if not bool(used.get(rid, false)):
					ready[rid] = true
			else:
				var amount := maxi(0, int(rule.get("amount", 0)))
				spent[id] = maxi(0, int(spent.get(id, 0)) - amount)
				if int(spent[id]) == 0:
					spent.erase(id)
	if event == "long_rest":
		ready.clear()
		used.clear()
	var patch := {"resource_tracker_spent": spent, "resource_recovery_ready": ready, "resource_recovery_used": used}
	if event in ["short_rest", "long_rest"]: patch["active_class_features"] = {}
	if event == "long_rest": patch["created_spell_slots"] = []
	return patch

static func optional_recovery_patch(record: Dictionary, rule_id: String, trackers: Array[Dictionary]) -> Dictionary:
	var ready: Dictionary = record.get("resource_recovery_ready", {})
	var used: Dictionary = record.get("resource_recovery_used", {})
	if not bool(ready.get(rule_id, false)) or bool(used.get(rule_id, false)):
		return {}
	for tracker: Dictionary in trackers:
		for raw: Variant in tracker.get("partial_recoveries", []):
			if not raw is Dictionary:
				continue
			var rule: Dictionary = raw
			if String(rule.get("id", "")) != rule_id or String(rule.get("mode", "")) != "optional_partial":
				continue
			var member := _member_for(record, rule)
			if member.is_empty():
				continue
			var amount := maxi(0, int(rule.get("amount", 0)))
			if String(rule.get("formula", "")) == "half_class_level_floor":
				amount = int(floor(float(member.get("level", 0)) / 2.0))
			var spent: Dictionary = record.get("resource_tracker_spent", {}).duplicate(true)
			var id := String(tracker.get("id", ""))
			spent[id] = maxi(0, int(spent.get(id, 0)) - amount)
			if int(spent[id]) == 0:
				spent.erase(id)
			var next_ready := ready.duplicate(true)
			next_ready.erase(rule_id)
			var next_used := used.duplicate(true)
			next_used[rule_id] = true
			return {"resource_tracker_spent": spent, "resource_recovery_ready": next_ready, "resource_recovery_used": next_used}
	return {}
