extends RefCounted

# Pure rules adapter: 5e.tools data is reference data, the record's trackers
# are mutable encounter state. Never send this record in a board snapshot.
const TRACKER_VERSION := 1


static func monster_armor_class(stat: Dictionary) -> int:
	var ac_value: Variant = stat.get("ac", [])
	if ac_value is Array:
		for part: Variant in ac_value as Array:
			if part is int or part is float:
				return maxi(0, int(part))
			if part is Dictionary and (part as Dictionary).has("ac"):
				return maxi(0, int((part as Dictionary).get("ac", 10)))
	if ac_value is int or ac_value is float:
		return maxi(0, int(ac_value))
	return 10


static func monster_abilities(stat: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for ability: String in ["str", "dex", "con", "int", "wis", "cha"]:
		result[ability] = clampi(int(stat.get(ability, 10)), 1, 30)
	return result


static func default_tracker(
	tracker_id: String,
	label: String,
	maximum: int,
	reset: String,
	kind: String = "resource",
	recharge_min: int = 0
) -> Dictionary:
	return {
		"id": tracker_id,
		"label": label,
		"kind": kind,
		"maximum": maxi(0, maximum),
		"current": maxi(0, maximum),
		"reset": reset,
		"recharge_min": recharge_min
	}


static func monster_trackers(stat: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var legendary_value: Variant = stat.get("legendary", [])
	if legendary_value is Array and not (legendary_value as Array).is_empty():
		var legendary_max := maxi(1, int(stat.get("legendaryActions", 3)))
		result.append(default_tracker(
			"legendary_actions", "Azioni leggendarie",
			legendary_max, "turn"
		))

	var spellcasting_value: Variant = stat.get("spellcasting", [])
	if spellcasting_value is Array:
		for caster_value: Variant in spellcasting_value as Array:
			if not caster_value is Dictionary:
				continue
			var caster: Dictionary = caster_value as Dictionary
			var slots_value: Variant = caster.get("spells", {})
			if not slots_value is Dictionary:
				continue
			for level: int in range(1, 10):
				var slot_value: Variant = (slots_value as Dictionary).get(str(level), {})
				if slot_value is Dictionary:
					var total := maxi(0, int((slot_value as Dictionary).get("slots", 0)))
					if total > 0:
						result.append(default_tracker(
							"slot_%d" % level, "Slot livello %d" % level,
							total, "long_rest", "spell_slot"
						))
	# A monster can have several independent abilities with the same label.
	# Index-based keys are stable for a given 5e.tools stat block.
	for section: String in ["trait", "action", "bonus", "reaction", "legendary"]:
		var entries_value: Variant = stat.get(section, [])
		if not entries_value is Array:
			continue
		var entries: Array = entries_value as Array
		for index: int in range(entries.size()):
			if not entries[index] is Dictionary:
				continue
			var item: Dictionary = entries[index] as Dictionary
			var name := String(item.get("name", "")).strip_edges()
			if name.is_empty():
				continue
			var recharge_min := _recharge_threshold(name)
			if recharge_min > 0:
				result.append(default_tracker(
					"%s_%d_recharge" % [section, index], name,
					1, "recharge", "recharge", recharge_min
				))
				continue
			var per_day := _daily_uses(name)
			if per_day > 0:
				result.append(default_tracker(
					"%s_%d_day" % [section, index], name,
					per_day, "long_rest"
				))
	return result


static func _recharge_threshold(name: String) -> int:
	var regex := RegEx.new()
	if regex.compile("(?i)recharge\\s+([2-6])(?:\\s*[-–—]\\s*6)?") != OK:
		return 0
	var found: RegExMatch = regex.search(name)
	return int(found.get_string(1)) if found != null else 0


static func _daily_uses(name: String) -> int:
	var regex := RegEx.new()
	if regex.compile("(?i)([1-9][0-9]*)\\s*/\\s*day") != OK:
		return 0
	var found: RegExMatch = regex.search(name)
	return int(found.get_string(1)) if found != null else 0


static func reconcile_trackers(
	existing_value: Variant,
	derived: Array[Dictionary]
) -> Array[Dictionary]:
	var existing: Dictionary = {}
	if existing_value is Array:
		for raw: Variant in existing_value as Array:
			if raw is Dictionary:
				var tracker: Dictionary = raw as Dictionary
				var tracker_id := String(tracker.get("id", "")).strip_edges()
				if not tracker_id.is_empty():
					existing[tracker_id] = tracker
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for source: Dictionary in derived:
		var id := String(source.get("id", ""))
		seen[id] = true
		var merged: Dictionary = source.duplicate(true)
		if existing.has(id):
			var old: Dictionary = existing[id]
			for key: String in ["current", "maximum", "label", "reset", "recharge_min"]:
				if old.has(key):
					merged[key] = old[key]
		result.append(normalize_tracker(merged))
	# Explicitly user-created trackers persist even if the catalog changes.
	for id_value: Variant in existing.keys():
		var id := String(id_value)
		if not seen.has(id) and id.begins_with("custom_"):
			result.append(normalize_tracker(existing[id]))
	return result


static func normalize_tracker(raw: Dictionary) -> Dictionary:
	var tracker := raw.duplicate(true)
	tracker["id"] = String(raw.get("id", ""))
	tracker["label"] = String(raw.get("label", "Risorsa"))
	tracker["kind"] = String(raw.get("kind", "resource"))
	tracker["reset"] = String(raw.get("reset", "long_rest"))
	tracker["maximum"] = clampi(int(raw.get("maximum", 0)), 0, 9999)
	tracker["current"] = clampi(
		int(raw.get("current", tracker["maximum"])),
		0, int(tracker["maximum"])
	)
	tracker["recharge_min"] = clampi(int(raw.get("recharge_min", 0)), 0, 6)
	return tracker


static func apply_reset(
	trackers_value: Variant,
	rest_type: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not trackers_value is Array:
		return result
	for raw: Variant in trackers_value as Array:
		if not raw is Dictionary:
			continue
		var item := normalize_tracker(raw as Dictionary)
		var rule := String(item.get("reset", ""))
		if (
			rest_type == "long_rest"
			and rule in ["long_rest", "short_rest", "turn"]
		) or (
			rest_type == "short_rest" and rule in ["short_rest", "turn"]
		) or (
			rest_type == "turn" and rule == "turn"
		):
			item["current"] = item["maximum"]
		result.append(item)
	return result


static func serialize_public_identity(creature: Dictionary) -> Dictionary:
	# No HP, ability scores, spell slots, secret notes, or full stat block.
	return {
		"creature_id": String(creature.get("id", "")),
		"owner_id": String(creature.get("owner_id", "")),
		"default_miniature_id": String(
			creature.get("default_miniature_id", "")
		)
	}
