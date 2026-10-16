extends RefCounted

# Resource counters backed by numeric 5etools JSON fields or formal 5etools
# {@recharge ...} markup. This module never interprets feature prose.
const BenefitRequirements = preload("res://vtt/benefit_requirements.gd")
const ClassMechanics = preload("res://vtt/class_mechanics_5etools.gd")
const ResourceOverrides = preload("res://vtt/class_resource_overrides.gd")
const Features = preload("res://vtt/creature_features.gd")
const OriginSpells5e = preload("res://vtt/structured_origin_spells_5etools.gd")
const FightClubMonsters = preload("res://vtt/fightclub_monster_resources.gd")


static func for_creature(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if String(record.get("kind", "")) == "monster":
		_append_monster_trackers(record, result)
	_append_class_trackers(record, result)
	_assign_automatic_origins(record, result)
	_append_saved_trackers(record, result)
	var seen: Dictionary = {}
	for tracker: Dictionary in result:
		seen[String(tracker.get("id", ""))] = true
	var additional: Dictionary = OriginSpells5e.for_creature(record)
	for value: Variant in additional.get("trackers", []):
		if not value is Dictionary:
			continue
		var tracker: Dictionary = value
		var id: String = String(tracker.get("id", ""))
		if not id.is_empty() and not seen.has(id):
			seen[id] = true
			result.append(tracker)
	return result


# Return a new spent-use map for a recovery event. A long rest also recovers
# resources which recharge on a short rest. Manual and d6 trackers stay intact.
# Callers choose when a rest occurs; merely opening a sheet never resets uses.
static func spent_after_recovery(record: Dictionary, event: String) -> Dictionary:
	var saved: Variant = record.get("resource_tracker_spent", {})
	var spent: Dictionary = (saved as Dictionary).duplicate(true) if saved is Dictionary else {}
	if event not in ["short_rest", "long_rest", "turn"]:
		return spent
	for tracker: Dictionary in for_creature(record):
		var mode: String = String(tracker.get("recharge", "manual"))
		if mode == event or (event == "long_rest" and mode == "short_rest"):
			spent.erase(String(tracker.get("id", "")))
	return spent


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
		# An unmet requirement hides a manual resource without deleting its
		# stable ID or the saved count of spent uses.
		var gate: Dictionary = BenefitRequirements.normalize(data)
		if not BenefitRequirements.allows(record, gate):
			continue
		var formula: String = String(data.get("max_formula", "")).strip_edges()
		var maximum: int = maxi(0, int(data.get("max", 0)))
		if not formula.is_empty():
			var computed: Dictionary = ResourceOverrides.evaluate_max(formula, record, int(record.get("level", 1)))
			if not computed.is_empty():
				maximum = int(computed.get("max", maximum))
		output.append({
			"id": tracker_id, "name": title,
			"max": maximum,
			"max_formula": formula, "requirements": gate,
			"origin": String(data.get("origin_name", "Senza origine")),
			"origin_id": String(data.get("origin_id", "")),
			"origin_name": String(data.get("origin_name", "Senza origine")),
			"recharge": String(data.get("recharge", "manual")),
			"disabled": bool(data.get("disabled", false)),
			"automatic": false
		})


# Connect automatic counters to a real trait whenever possible. Only
# otherwise use a stable internal counter identity, not an invented feat.
# Prefer an explicit structured feature reference. A name is only an
# unambiguous fallback within the same class, edition and subclass.
# Never attach a counter to an unrelated equally named trait.
static func _find_tracker_feature(row: Dictionary, features: Array[Dictionary]) -> Dictionary:
	var reference: String = String(row.get("origin_feature_key", ""))
	if reference.begins_with("feature:"):
		reference = reference.substr(8)
	if not reference.is_empty():
		for feature: Dictionary in features:
			if String(feature.get("key", "")) == reference:
				return feature
		return {}
	var class_name: String = String(row.get("origin_class", ""))
	var source: String = String(row.get("origin_class_source", ""))
	var subclass: String = String(row.get("origin_subclass", ""))
	var wanted: String = String(row.get("origin", row.get("name", ""))).strip_edges().to_lower()
	if wanted.is_empty():
		return {}
	var found: Dictionary = {}
	for feature: Dictionary in features:
		if not class_name.is_empty():
			if String(feature.get("class_name", "")).nocasecmp_to(class_name) != 0:
				continue
			if not source.is_empty() and String(feature.get("class_source", "")).nocasecmp_to(source) != 0:
				continue
			var origin_key: String = String(feature.get("origin_key", ""))
			var is_subclass: bool = "|subclass|" in origin_key
			if is_subclass != (not subclass.is_empty()):
				continue
			if is_subclass and ("|subclass|" + subclass.to_lower() + "|") not in origin_key:
				continue
		var feature_name: String = String(feature.get("name", "")).strip_edges().to_lower()
		if wanted != feature_name and not feature_name.begins_with(wanted + " {") and not feature_name.begins_with(wanted + " ("):
			continue
		if not found.is_empty():
			return {} # Ambiguous, do not arbitrarily borrow the first feature.
		found = feature
	return found


static func _assign_automatic_origins(record: Dictionary, output: Array[Dictionary]) -> void:
	if output.is_empty():
		return
	var features: Array[Dictionary] = Features.collect_features(record)
	for row: Dictionary in output:
		row["automatic"] = true
		row["disabled"] = false
		var label: String = String(row.get("origin", row.get("name", "")))
		var origin_id: String = ""
		var feature: Dictionary = _find_tracker_feature(row, features)
		if not feature.is_empty():
			origin_id = "feature:" + String(feature.get("key", ""))
			label = "Tratto · " + String(feature.get("name", ""))
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



	# Supplement 5etools with source-qualified Fight Club counters. Only attach
	# a counter to the same, uniquely named feature in the SAME section; never
	# assign resources based on prose or a matching monster name alone.
	for supplement: Dictionary in FightClubMonsters.for_monster(record):
		var max_uses: int = int(supplement.get("max", 0))
		var recovery: String = String(supplement.get("recharge", ""))
		if max_uses <= 0 or recovery not in ["d6", "turn", "short_rest", "long_rest"]:
			continue
		if bool(supplement.get("legendary_pool", false)):
			var legendary_value: Variant = stat.get("legendary", [])
			if not legendary_value is Array or (legendary_value as Array).is_empty():
				continue
			var existing_pool := false
			for tracker: Dictionary in output:
				if String(tracker.get("id", "")) == "legendary_actions":
					existing_pool = true
					break
			if not existing_pool:
				output.append({
					"id": "legendary_actions", "name": "Azioni leggendarie",
					"max": max_uses, "origin": "Azioni leggendarie",
					"recharge": "turn", "source_label": "Fight Club 5e"
				})
			continue
		var section: String = String(supplement.get("section", ""))
		if section not in ["trait", "action", "bonus", "reaction", "legendary", "mythic"]:
			continue
		var section_value: Variant = stat.get(section, [])
		if not section_value is Array:
			continue
		var wanted: String = _normalise_monster_feature_name(String(supplement.get("name", "")))
		if wanted.is_empty():
			continue
		var matching_index := -1
		for index: int in range((section_value as Array).size()):
			var raw_entry: Variant = (section_value as Array)[index]
			if not raw_entry is Dictionary:
				continue
			var candidate: String = _normalise_monster_feature_name(
				String((raw_entry as Dictionary).get("name", "")))
			if candidate != wanted:
				continue
			if matching_index >= 0:
				matching_index = -1  # Ambiguous names must be resolved manually.
				break
			matching_index = index
		if matching_index < 0:
			continue
		var native_id: String = "recharge:%s:%d" % [section, matching_index]
		var already_available := false
		for tracker: Dictionary in output:
			if String(tracker.get("id", "")) == native_id:
				already_available = true
				break
		if already_available:
			continue  # 5etools is authoritative for explicit recharge markup.
		var raw_entry: Dictionary = (section_value as Array)[matching_index]
		var actual_title: String = String(raw_entry.get("name", ""))
		var display_name: String = _clean_monster_recharge_name(actual_title)
		var tracker: Dictionary = {
			"id": "fightclub:%s:%d" % [section, matching_index],
			"name": display_name, "max": max_uses, "origin": actual_title,
			"recharge": recovery, "source_label": "Fight Club 5e"
		}
		if recovery == "d6":
			tracker["recharge_min"] = int(supplement.get("recharge_min", 6))
		output.append(tracker)


static func _clean_monster_recharge_name(title: String) -> String:
	var expression := RegEx.create_from_string(
		"\\{@recharge(?: [1-6])?\\}|\\(recharge [1-6](?:-[1-6])?\\)")
	if expression == null:
		return title.strip_edges()
	# Regex is lower-case, but preserve capitalization in the displayed title.
	var lowercase: String = title.to_lower()
	var found: RegExMatch = expression.search(lowercase)
	if found != null:
		return title.erase(found.get_start(), found.get_string().length()).strip_edges()
	return title.strip_edges()


static func _normalise_monster_feature_name(title: String) -> String:
	return _clean_monster_recharge_name(title).to_lower().strip_edges()


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
				"origin_feature_key": String(definition.get("origin_feature_key", "")),
				"origin_class": String(class_data.get("name", "")),
				"origin_class_source": resolved_source,
				"recharge": "manual",
				"source_label": "%s · %s" % [
					String(class_data.get("name", "")), resolved_source
				]
			})
		# Local build-time supplement supplies missing resources and recoveries.
		# 5etools remains authoritative for numeric class-table progressions.
		var subclass_name: String = String(class_data.get("subclass", record.get("subclass", "")))
		for supplement: Dictionary in ResourceOverrides.for_class(
			selected_class_name, resolved_source, class_level, subclass_name, record
		):
			var supplement_column: String = String(supplement.get("column", supplement.get("name", "")))
			# An unlimited (or unavailable) 5etools table value must never
			# become a finite fallback counter from the supplementary source.
			var native_column: Dictionary = ClassMechanics.column(
				selected_class_name, resolved_source, supplement_column)
			if not native_column.is_empty():
				var native_value: Variant = ClassMechanics.column_value(
					selected_class_name, resolved_source, supplement_column, class_level)
				if not (native_value is int or native_value is float) or int(native_value) <= 0:
					continue
			var resource_id: String = "class:%s:%s:%s" % [
				selected_class_name, resolved_source.to_lower(), supplement_column.to_lower().replace(" ", "_")
			]
			if seen.has(resource_id):
				for existing: Dictionary in output:
					if String(existing.get("id", "")) == resource_id:
						existing["recharge"] = String(supplement.get("recharge", "manual"))
						break
				continue
			seen[resource_id] = true
			output.append({
				"id": resource_id, "name": String(supplement.get("name", supplement_column)),
				"max": int(supplement.get("max", 0)),
				"max_formula": String(supplement.get("max_formula", "")),
				"origin": String(supplement.get("origin", supplement_column)),
				"origin_feature_key": String(supplement.get("origin_feature_key", "")),
				"origin_class": String(class_data.get("name", "")),
				"origin_class_source": resolved_source,
				"origin_subclass": String(supplement.get("subclass", "")),
				"recharge": String(supplement.get("recharge", "manual")),
				"source_label": "%s · %s" % [String(class_data.get("name", "")), resolved_source]
			})
