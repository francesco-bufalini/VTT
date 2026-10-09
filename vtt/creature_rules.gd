extends RefCounted

# Pure rules adapter: 5e.tools data is reference data, the record's trackers
# are mutable encounter state. Never send this record in a board snapshot.
const ContentCatalog = preload("res://vtt/content_catalog.gd")
const TRACKER_VERSION := 1



const FULL_CASTER_SLOTS := [
	[], [2], [3], [4, 2], [4, 3], [4, 3, 2],
	[4, 3, 3], [4, 3, 3, 1], [4, 3, 3, 2],
	[4, 3, 3, 3, 1], [4, 3, 3, 3, 2],
	[4, 3, 3, 3, 2, 1], [4, 3, 3, 3, 2, 1],
	[4, 3, 3, 3, 2, 1, 1], [4, 3, 3, 3, 2, 1, 1],
	[4, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 2, 1, 1, 1],
	[4, 3, 3, 3, 2, 1, 1, 1, 1],
	[4, 3, 3, 3, 3, 1, 1, 1, 1],
	[4, 3, 3, 3, 3, 2, 1, 1, 1],
	[4, 3, 3, 3, 3, 2, 2, 1, 1]
]


static func character_trackers(character: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var classes_value: Variant = character.get("classes", [])
	var classes: Array = (
		classes_value if classes_value is Array else []
	)
	if classes.is_empty():
		classes = [{
			"name": String(character.get("class", "")),
			"level": int(character.get("level", 1))
		}]
	var caster_level := 0
	var warlock_level := 0
	for class_value: Variant in classes:
		if not class_value is Dictionary:
			continue
		var cls: Dictionary = class_value as Dictionary
		var name := String(cls.get("name", "")).to_lower()
		var edition := "2024" if String(cls.get("source", character.get("class_source", ""))) == "XPHB" else String(character.get("rules_version", "2014"))
		if String(cls.get("source", "")) == "PHB":
			edition = "2014"
		var level := clampi(int(cls.get("level", 1)), 1, 20)
		match name:
			"bard", "cleric", "druid", "sorcerer", "wizard":
				caster_level += level
			"artificer", "paladin", "ranger":
				# Artificer rounds up. The 2024 half-caster progression
				# is supported at level 1; 2014 paladin/ranger at level 2.
				if name == "artificer" or edition == "2024":
					caster_level += ceili(float(level) / 2.0)
				else:
					caster_level += ceili(float(level) / 2.0) if classes.size() == 1 and level >= 2 else floori(float(level) / 2.0)
			"warlock":
				warlock_level = maxi(warlock_level, level)
		match name:
			"barbarian":
				var uses := 2
				if level >= 17:
					uses = 6
				elif level >= 12:
					uses = 5
				elif level >= 6:
					uses = 4
				elif level >= 3:
					uses = 3
				result.append(default_tracker("rage", "Ira", uses, "long_rest"))
			"fighter":
				var uses := 2
				if level >= 10:
					uses = 4
				elif level >= 4:
					uses = 3
				result.append(default_tracker("second_wind", "Recuperare Energie", uses if edition == "2024" else 1, "long_rest" if edition == "2024" else "short_rest"))
				if level >= 2:
					result.append(default_tracker("action_surge", "Azione Impetuosa", 2 if level >= 17 else 1, "short_rest"))
				if level >= 9:
					result.append(default_tracker("indomitable", "Indomito", 3 if level >= 17 else 2 if level >= 13 else 1, "long_rest"))
			"monk":
				if level >= 2:
					result.append(default_tracker("focus", "Punti Focus / Ki", level, "short_rest"))
			"sorcerer":
				if level >= 2:
					result.append(default_tracker("sorcery_points", "Punti stregoneria", level, "long_rest"))
		for custom_class: Dictionary in ContentCatalog.home_entries("classes"):
			if String(custom_class.id) != String(cls.get("id", "")):
				continue
			for raw: Variant in custom_class.get("trackers", []):
				if raw is Dictionary and level >= int(raw.get("min_level", 1)):
					var tracker := normalize_tracker(raw)
					tracker["id"] = "custom_" + String(custom_class.id).replace(":", "_") + "_" + String(raw.get("id", "resource"))
					tracker["current"] = tracker.maximum
					result.append(tracker)
	if caster_level > 0:
		var slots: Array = FULL_CASTER_SLOTS[clampi(caster_level, 1, 20)]
		for i: int in range(slots.size()):
			result.append(default_tracker(
				"slot_%d" % (i + 1), "Slot livello %d" % (i + 1),
				int(slots[i]), "long_rest", "spell_slot"
			))
	if warlock_level > 0:
		var pact_slots := (
			4 if warlock_level >= 17 else
			3 if warlock_level >= 11 else
			2 if warlock_level >= 2 else 1
		)
		var pact_level := mini(5, (warlock_level + 1) / 2)
		result.append(default_tracker(
			"pact_slot", "Magia del Patto (liv. %d)" % pact_level,
			pact_slots, "short_rest", "spell_slot"
		))
	return result


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
		"overrides": {},
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
	if regex.compile("(?i)recharge(?:\\s+([2-6])(?:\\s*[-–—]\\s*6)?)?") != OK:
		return 0
	var found: RegExMatch = regex.search(name)
	return (int(found.get_string(1)) if not found.get_string(1).is_empty() else 6) if found != null else 0


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
			var override_value: Variant = old.get("overrides", {})
			var overrides: Dictionary = (
				override_value as Dictionary if override_value is Dictionary else {}
			)
			merged["overrides"] = overrides.duplicate(true)
			for key: String in ["maximum", "label", "reset", "recharge_min"]:
				if bool(overrides.get(key, false)) and old.has(key):
					merged[key] = old[key]
			var old_max := maxi(0, int(old.get("maximum", 0)))
			var old_current := clampi(
				int(old.get("current", old_max)), 0, old_max
			)
			# Increasing level grants more total uses without restoring
			# already spent ones. Manual maxima never get overwritten.
			var new_max := maxi(0, int(merged.get("maximum", 0)))
			merged["current"] = clampi(
				new_max - (old_max - old_current), 0, new_max
			)
		result.append(normalize_tracker(merged))
	for id_value: Variant in existing.keys():
		var id := String(id_value)
		if not seen.has(id) and (id.begins_with("custom_") or not (existing[id].get("overrides", {}) as Dictionary).is_empty()):
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
	var manual_value: Variant = raw.get("overrides", {})
	tracker["overrides"] = (
		(manual_value as Dictionary).duplicate(true)
		if manual_value is Dictionary else {}
	)
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
