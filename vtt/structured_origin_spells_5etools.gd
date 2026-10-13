extends RefCounted

# Runtime interpreter for pre-bundled, STRUCTURED 5etools additionalSpells.
# No natural-language heuristics. Never treats "expanded" or plain prepared
# leveled spells as freely castable; those still require ordinary spell slots.
const PATH := "res://vtt/data/additional_spells_5etools.json"
const Traits = preload("res://vtt/creature_traits_tab.gd")
const Profs = preload("res://vtt/creature_proficiency_rules.gd")
const Catalog = preload("res://vtt/spells/spell_catalog.gd")
static var _entries: Array = []
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("Structured additionalSpells index missing: " + PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and parsed.get("entries", []) is Array:
		_entries = parsed.get("entries", [])


static func _matching_origins(record: Dictionary, row: Dictionary, features: Array[Dictionary]) -> Array[Dictionary]:
	var kind: String = String(row.get("kind", ""))
	var wanted: String = String(row.get("name", ""))
	var source: String = String(row.get("source", ""))
	var result: Array[Dictionary] = []
	match kind:
		"race":
			if String(record.get("species", "")).nocasecmp_to(wanted) == 0 and String(record.get("species_source", "")) == source:
				result.append({"id": "race|" + source.to_lower() + "|" + wanted.to_lower(), "name": wanted, "level": int(record.get("level", 1))})
		"subrace":
			if String(record.get("subrace", "")).nocasecmp_to(wanted) == 0 and String(record.get("subrace_source", "")) == source and (
				String(row.get("race_name", "")).is_empty() or String(record.get("species", "")).nocasecmp_to(String(row.get("race_name", ""))) == 0
			):
				result.append({"id": "subrace|" + source.to_lower() + "|" + wanted.to_lower(), "name": wanted, "level": int(record.get("level", 1))})
		"background":
			if String(record.get("background", "")).nocasecmp_to(wanted) == 0 and String(record.get("background_source", "")) == source:
				result.append({"id": "background|" + source.to_lower() + "|" + wanted.to_lower(), "name": wanted, "level": int(record.get("level", 1))})
		"feat":
			for raw: Variant in record.get("feats_catalog", []):
				if not raw is Dictionary:
					continue
				var feat: Dictionary = raw
				if String(feat.get("name", "")).nocasecmp_to(wanted) == 0 and String(feat.get("source", "")) == source:
					result.append({"id": Profs.feat_source_id(feat), "name": wanted, "level": int(record.get("level", 1))})
		"optionalfeature":
			for feature: Dictionary in features:
				if String(feature.get("name", "")).nocasecmp_to(wanted) == 0 and String(feature.get("book", "")) == source:
					result.append({"id": "feature:" + String(feature.get("key", "")), "name": wanted, "level": int(record.get("level", 1))})
	return result


# Stable spell catalog IDs, retaining the PHB 2014 variant when appropriate.
# Full catalog lookup is a fallback for irregular official spell names.
static func _spell_id(value: String) -> String:
	var raw: String = value.split("#", true, 1)[0].to_lower()
	var parts: PackedStringArray = raw.split("|")
	var name: String = parts[0].strip_edges()
	if name.is_empty():
		return ""
	var source: String = parts[1] if parts.size() > 1 else ""
	var slug: String = name.replace("'", "").replace("’", "").replace("/", "_").replace("-", "_").replace(" ", "_")
	var parsed: RegEx = RegEx.create_from_string("[^a-z0-9_]")
	slug = parsed.sub(slug, "", true)
	while "__" in slug:
		slug = slug.replace("__", "_")
	if source == "phb" and not Catalog.catalog_spell("phb2014_" + slug).is_empty():
		return "phb2014_" + slug
	if not Catalog.catalog_spell(slug).is_empty():
		return slug
	if not Catalog.catalog_spell("phb2014_" + slug).is_empty():
		return "phb2014_" + slug
	return ""


static func _stage_level(key: String) -> int:
	if key == "_":
		return 0
	if key.is_valid_int():
		return int(key)
	# s1, s2 etc represent spell slot level, not character level. Such
	# prepared/expanded entries do not create no-slot entitlements.
	return 0


static func _add_choice(output: Dictionary, origin: Dictionary, spec: Dictionary, tracker_id: String, mode: String, stage: String) -> void:
	var filter: String = String(spec.get("choose", ""))
	if filter.is_empty():
		return
	var pending: Array = output["choices"]
	pending.append({
		"id": String(origin.get("id", "")) + "|" + stage + "|" + mode + "|" + filter,
		"origin_id": String(origin.get("id", "")),
		"origin_name": String(origin.get("name", "")),
		"filter": filter,
		"count": maxi(1, int(spec.get("count", 1))),
		"tracker_id": tracker_id
	})


static func _add_spell(output: Dictionary, origin: Dictionary, token: String, tracker_id: String, mode: String, stage: String) -> void:
	var id: String = _spell_id(token)
	if id.is_empty():
		return
	var grants: Array = output["grants"]
	var origin_id: String = String(origin.get("id", ""))
	for old: Variant in grants:
		if old is Dictionary and String(old.get("origin_id", "")) == origin_id and String(old.get("spell_id", "")) == id and String(old.get("tracker_id", "")) == tracker_id:
			return
	grants.append({
		"id": "5etools:" + origin_id + "|" + id + "|" + mode + "|" + stage,
		"origin_id": origin_id,
		"origin_name": String(origin.get("name", origin_id)),
		"spell_id": id, "tracker_id": tracker_id,
		"automatic": true, "mechanic_source": "5etools.additionalSpells"
	})


static func _add_group(output: Dictionary, origin: Dictionary, spec: Variant, mode: String, stage: String, category: String, count_key: String, block_index: int) -> void:
	if not spec is Array:
		return
	var tracker_id := ""
	if category in ["daily", "rest"]:
		var amount: String = count_key.trim_suffix("e")
		if not amount.is_valid_int() or int(amount) <= 0:
			return
		var each: bool = count_key.ends_with("e")
		var recover := "long_rest" if category == "daily" else "short_rest"
		var tracker_list: Array = output["trackers"]
		# Shared resource for this usage group; 'e' denotes each spell has
		# a separate allowance. Individual IDs are assigned below.
		tracker_id = "5espell:" + String(origin.get("id", "")) + "|" + str(block_index) + "|" + stage + "|" + category + "|" + count_key
		if not each:
			tracker_list.append({
				"id": tracker_id, "name": String(origin.get("name", "")) + " · incantesimi",
				"max": int(amount), "recharge": recover,
				"origin_id": String(origin.get("id", "")),
				"origin_name": String(origin.get("name", "")),
				"origin": String(origin.get("name", "")),
				"automatic": true, "disabled": false
			})
	for raw: Variant in spec:
		var specific_tracker: String = tracker_id
		if category in ["daily", "rest"] and count_key.ends_with("e"):
			var key: String = String(raw) if raw is String else str(spec.find(raw))
			specific_tracker = tracker_id + "|" + key
			var amount: String = count_key.trim_suffix("e")
			var tracker_list: Array = output["trackers"]
			tracker_list.append({
				"id": specific_tracker,
				"name": String(origin.get("name", "")) + " · " + (String(raw) if raw is String else "scelta"),
				"max": int(amount),
				"recharge": "long_rest" if category == "daily" else "short_rest",
				"origin_id": String(origin.get("id", "")),
				"origin_name": String(origin.get("name", "")),
				"origin": String(origin.get("name", "")),
				"automatic": true, "disabled": false
			})
		if raw is Dictionary:
			_add_choice(output, origin, raw, specific_tracker, mode, stage)
		elif raw is String:
			# Known cantrips are at-will; other known/prepared leveled spells
			# require a real usage mode, not an invented free cast.
			if mode == "known" and category == "will":
				var token: String = String(raw)
				if "#c" not in token:
					continue
			_add_spell(output, origin, String(raw), specific_tracker, mode, stage)


static func _walk_usage(output: Dictionary, origin: Dictionary, values: Variant, mode: String, stage: String, block_index: int) -> void:
	if values is Array:
		_add_group(output, origin, values, mode, stage, "will", "", block_index)
		return
	if not values is Dictionary:
		return
	for category: String in ["daily", "rest", "will", "_"]:
		var scoped: Variant = (values as Dictionary).get(category, null)
		if category == "will" or category == "_":
			if scoped is Array:
				_add_group(output, origin, scoped, mode, stage, "will", "", block_index)
		elif scoped is Dictionary:
			for uses: String in scoped.keys():
				_add_group(output, origin, scoped[uses], mode, stage, category, uses, block_index)


static func for_creature(record: Dictionary) -> Dictionary:
	_ensure_loaded()
	var output: Dictionary = {"grants": [], "trackers": [], "choices": []}
	if record.is_empty() or String(record.get("kind", "")) == "monster":
		return output
	var features: Array[Dictionary] = Traits.collect_features(record)
	for raw: Variant in _entries:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var origins: Array[Dictionary] = _matching_origins(record, entry, features)
		if origins.is_empty():
			continue
		for origin: Dictionary in origins:
			for block_index: int in range((entry.get("blocks", []) as Array).size()):
				var block: Variant = (entry.get("blocks", []) as Array)[block_index]
				if not block is Dictionary:
					continue
				for mode: String in ["innate", "known", "prepared"]:
					var progression: Variant = (block as Dictionary).get(mode, null)
					if not progression is Dictionary:
						continue
					for stage: String in (progression as Dictionary).keys():
						var threshold: int = _stage_level(stage)
						if stage.begins_with("s") or (stage != "_" and not stage.is_valid_int()):
							continue
						if int(origin.get("level", 0)) < threshold:
							continue
						var value: Variant = (progression as Dictionary)[stage]
						_walk_usage(output, origin, value, mode, stage, block_index)
	return output
