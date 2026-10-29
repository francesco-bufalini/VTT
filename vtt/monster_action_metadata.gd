extends RefCounted

# Import-time normalization of action and recharge metadata. Official 5etools
# {@atk}/{@hit}/{@damage}/{@recharge} tags are converted ONCE, not on every
# sheet refresh. Fight Club resources enrich only uniquely identified actions.
# Hand-verified exceptions live separately from source JSON and can be edited.
const FightClub = preload("res://vtt/fightclub_monster_resources.gd")
const OVERRIDES := "res://vtt/data/monster_action_overrides.json"
const SECTIONS := ["trait", "action", "bonus", "reaction", "legendary", "mythic"]
static var _loaded := false
static var _overrides: Dictionary = {}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(OVERRIDES, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		var entries: Variant = (parsed as Dictionary).get("actions", {})
		if entries is Dictionary:
			_overrides = entries


static func _key(stat: Dictionary, section: String, name: String) -> String:
	return String(stat.get("source", "")).strip_edges().to_upper() + "|" + (
		String(stat.get("name", "")).strip_edges().to_lower() + "|" + section + "|" +
		name.strip_edges().to_lower())


static func _capture(value: String, expression: String) -> String:
	# Legacy/5etools-tag converter, never called for prepared entries.
	var pattern: RegEx = RegEx.create_from_string(expression)
	if pattern == null:
		return ""
	var match_value: RegExMatch = pattern.search(value)
	return match_value.get_string(1) if match_value != null else ""


static func parse_attack(action: Dictionary) -> Dictionary:
	var text_value: String = JSON.stringify(action.get("entries", []))
	var lower: String = text_value.to_lower()
	var hit: String = _capture(text_value, "\\{@hit\\s*([+-]?\\d+)\\}")
	if hit.is_empty():
		hit = _capture(text_value, "([+-]\\d+)\\s+to\\s+hit")
	var code: String = _capture(text_value, "\\{@atk\\s+([^}]+)\\}").to_lower()
	var attack: bool = (not hit.is_empty() or not code.is_empty()
		or "weapon attack:" in lower or "spell attack:" in lower)
	if not attack:
		return {}
	var reach: String = _capture(lower, "reach\\s*(\\d+)\\s*(?:ft|feet)")
	var normal: String = _capture(lower, "range\\s*(\\d+)\\s*(?:/|ft|feet)")
	var long: String = _capture(lower, "range\\s*\\d+\\s*/\\s*(\\d+)")
	var ranged: bool = ("ranged" in lower or "rw" in code or "rs" in code)
	var melee: bool = not ranged or "melee or ranged" in lower or "mw" in code or "ms" in code
	var dice: String = _capture(text_value, "\\{@damage\\s*([^}]+)\\}")
	if dice.is_empty():
		dice = _capture(text_value, "(\\d+d\\d+(?:\\s*[+-]\\s*\\d+)*)")
	return {
		"attack_kind": "attack",
		"melee": melee,
		"has_ranged_mode": ranged,
		"range_feet": maxi(5, int(normal)) if ranged and not normal.is_empty()
			else maxi(5, int(reach)) if not reach.is_empty() else 5,
		"long_range_feet": maxi(0, int(long)) if ranged and not long.is_empty() else 0,
		"melee_reach_feet": maxi(5, int(reach)) if not reach.is_empty() else 5,
		"damage": dice,
		"base_hit": int(hit) if not hit.is_empty() else 0,
		"hit_known": not hit.is_empty(),
		"source_ability": "dex" if ranged else "str"
	}


static func _all_reach_in_entry(action: Dictionary) -> int:
	# Preserve legacy maximum-reach semantics, including all distinct reach
	# mentions within non-attack actions. Do this only on import/edit.
	var expression := RegEx.create_from_string("reach\\s*(\\d+)\\s*(?:ft\\.?|feet)")
	if expression == null:
		return 5
	var best := 5
	var content: String = JSON.stringify(action.get("entries", [])).to_lower()
	for found: RegExMatch in expression.search_all(content):
		best = maxi(best, int(found.get_string(1)))
	return best


static func _clean_name(name: String) -> String:
	# Clean only the formal 5etools suffix, never infer recharge from prose.
	var start: int = name.find("{@recharge")
	if start < 0:
		return name.strip_edges()
	var end: int = name.find("}", start)
	return (name.erase(start, end - start + 1).strip_edges()
		if end >= 0 else name.strip_edges())


static func parse_recharge(name: String) -> Dictionary:
	var raw: String = _capture(name, "\\{@recharge(?: ([1-6]))?\\}")
	if "{@recharge" not in name:
		return {}
	var clean: String = _clean_name(name)
	if clean.is_empty():
		return {}
	return {"name": clean, "max": 1, "recharge": "d6",
		"recharge_min": int(raw) if not raw.is_empty() else 6}


static func _resource_name(name: String) -> String:
	var clean: String = _clean_name(name).to_lower()
	var at: int = clean.find(" (recharge ")
	if at >= 0 and clean.ends_with(")"):
		clean = clean.substr(0, at)
	return clean.strip_edges()


static func _unique_index(stat: Dictionary, section: String, wanted: String) -> int:
	var raw: Variant = stat.get(section, [])
	if not raw is Array:
		return -1
	var index := -1
	for i: int in range((raw as Array).size()):
		var candidate: Variant = (raw as Array)[i]
		if not candidate is Dictionary:
			continue
		if _resource_name(String((candidate as Dictionary).get("name", ""))) != wanted:
			continue
		if index >= 0:
			return -1
		index = i
	return index


static func _source_revision(stat: Dictionary) -> int:
	# The revision ignores derived vtt_* fields; edits to actions or source
	# invalidate the cache without imposing regex work on every sheet update.
	var pieces: PackedStringArray = [
		String(stat.get("source", "")),
		String(stat.get("name", "")),
		str(stat.get("legendaryActions", ""))
	]
	for section: String in SECTIONS:
		var raw: Variant = stat.get(section, [])
		if not raw is Array:
			continue
		for value: Variant in raw:
			if value is Dictionary:
				pieces.append(section + "|" + String((value as Dictionary).get("name", ""))
					+ "|" + JSON.stringify((value as Dictionary).get("entries", []))
					+ "|" + str((value as Dictionary).get("attacks_per_action", "")))
	return "||".join(pieces).hash()


static func _multiattack_text(value: Variant) -> String:
	if value is String:
		return String(value)
	if value is Array:
		var parts: PackedStringArray = []
		for part: Variant in value:
			parts.append(_multiattack_text(part))
		return " ".join(parts)
	if value is Dictionary:
		return _multiattack_text(value.get("entries", value.get("entry", value.get("description", ""))))
	return ""

static func multiattack_count(action: Dictionary) -> int:
	if String(action.get("name", "")).strip_edges().to_lower() not in ["multiattack", "multiattacco"]:
		return 0
	var direct: int = int(action.get("attacks_per_action", 0))
	# Count the full routine: a preceding special use plus the attack clause.
	var pattern := RegEx.create_from_string("(?i)\\b(?:makes?|can make|may make|effettua|può effettuare)\\s+(?:up to\\s+)?(\\d+|one|two|three|four|five|six|uno|due|tre|quattro|cinque|sei)\\s+(?:(?:melee|ranged|weapon|spell|arma)\\s+)*(?:attacks?|attacchi)\\b")
	var words: Dictionary = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "uno": 1, "due": 2, "tre": 3, "quattro": 4, "cinque": 5, "sei": 6}
	var count: int = 0
	var description: String = _multiattack_text(action.get("entries", action.get("description", "")))
	for found: RegExMatch in pattern.search_all(description):
		var number: String = found.get_string(1).to_lower()
		count = maxi(count, int(words.get(number, number)))
	var special_pattern := RegEx.create_from_string("(?i)\\b(?:can|may)\\s+use\\s+[^.!?]+[.!?]\\s*(?:It|They|The [A-Za-z -]+?)\\s+then\\s+(?:makes?|can make|may make)\\s+")
	var specials: int = special_pattern.search_all(description).size() if count > 0 else 0
	var derived: bool = int(action.get("vtt_multiattack_count_version", 0)) == 2 and bool(action.get("vtt_multiattack_count_derived", false))
	var legacy: bool = not action.has("vtt_multiattack_count_version") and specials > 0 and direct == count
	if direct >= 2 and not derived and not legacy:
		return direct
	return count + specials if count + specials >= 2 else 0


static func prepare(stat_block: Dictionary) -> Dictionary:
	_load()
	var source_revision: int = _source_revision(stat_block)
	var override_revision: int = JSON.stringify(_overrides).hash()
	if (int(stat_block.get("vtt_action_metadata_version", 0)) == 1
		and int(stat_block.get("vtt_multiattack_count_version", 0)) == 2
		and int(stat_block.get("vtt_action_source_revision", -1)) == source_revision
		and int(stat_block.get("vtt_action_override_revision", -1)) == override_revision):
		return stat_block
	var stat: Dictionary = stat_block.duplicate(true)
	stat["vtt_multiattack_count_version"] = 2
	var max_reach: int = 5
	for section: String in SECTIONS:
		var raw: Variant = stat.get(section, [])
		if not raw is Array:
			continue
		var rows: Array = raw
		for index: int in range(rows.size()):
			if not rows[index] is Dictionary:
				continue
			var action: Dictionary = rows[index]
			var attack_count: int = multiattack_count(action)
			if attack_count >= 2:
				action["vtt_attacks_per_action"] = attack_count
			else:
				action.erase("vtt_attacks_per_action")
			# Never reuse metadata after its source action changed. Re-evaluate
			# the new formal tags and then apply the curated override.
			action.erase("vtt_attack")
			action.erase("vtt_resource")
			max_reach = maxi(max_reach, _all_reach_in_entry(action))
			var name: String = String(action.get("name", ""))
			var generated: Dictionary = parse_attack(action)
			var resource: Dictionary = parse_recharge(name)
			var override: Variant = _overrides.get(_key(stat, section, name), {})
			if override is Dictionary:
				if (override as Dictionary).has("attack"):
					var custom: Variant = (override as Dictionary)["attack"]
					if custom is Dictionary:
						generated = (custom as Dictionary).duplicate(true)
				if (override as Dictionary).has("resource"):
					var custom_resource: Variant = (override as Dictionary)["resource"]
					if custom_resource is Dictionary:
						resource = (custom_resource as Dictionary).duplicate(true)
			if not generated.is_empty() and String(generated.get("attack_kind", "")) == "attack":
				action["vtt_attack"] = generated
			if not resource.is_empty():
				resource["id"] = "recharge:%s:%d" % [section, index]
				action["vtt_resource"] = resource
			rows[index] = action
		stat[section] = rows

	# Supplement 5etools formal recharge markup from matching Fight Club XML
	# records. The supplement is already converted offline, with provenance.
	var supplementary: Array[Dictionary] = FightClub.for_monster(
		{"kind": "monster", "stat_block": stat})
	for item: Dictionary in supplementary:
		if bool(item.get("legendary_pool", false)):
			var legendary: Variant = stat.get("legendary", [])
			if (not stat.has("legendaryActions") and legendary is Array
				and not (legendary as Array).is_empty()):
				stat["vtt_legendary_actions"] = int(item.get("max", 0))
			continue
		var section: String = String(item.get("section", ""))
		if section not in SECTIONS:
			continue
		var index: int = _unique_index(stat, section, _resource_name(String(item.get("name", ""))))
		if index < 0:
			continue
		var rows: Array = stat.get(section, [])
		var action: Dictionary = rows[index]
		if action.has("vtt_resource"):
			continue # 5etools formal tag takes precedence
		var resource: Dictionary = {
			"id": "fightclub:%s:%d" % [section, index],
			"name": _clean_name(String(action.get("name", ""))),
			"max": int(item.get("max", 1)),
			"recharge": String(item.get("recharge", "manual")),
			"source_label": "Fight Club 5e"
		}
		if String(item.get("recharge", "")) == "d6":
			resource["recharge_min"] = int(item.get("recharge_min", 6))
		action["vtt_resource"] = resource
		rows[index] = action
		stat[section] = rows
	stat["vtt_max_reach_feet"] = max_reach
	stat["vtt_action_metadata_version"] = 1
	stat["vtt_action_source_revision"] = source_revision
	stat["vtt_action_override_revision"] = override_revision
	return stat
