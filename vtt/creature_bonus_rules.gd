extends RefCounted

# Every numeric formula target may receive several independent, additive grants.
# "expression" is deliberately arithmetic only: no dice and no method calls.
# Existing manual bonus fields are retained as legacy components of the base.
const Rules = preload("res://vtt/creature_rules.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const Skills = preload("res://vtt/creature_skills_5etools.gd")
const Items = preload("res://vtt/creature_item_rules.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]


static func grants(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = record.get("formula_bonuses", [])
	if raw is Array:
		for entry: Variant in raw:
			if not entry is Dictionary:
				continue
			var row: Dictionary = entry as Dictionary
			if String(row.get("target", "")).is_empty():
				continue
			result.append({
				"id": String(row.get("id", "")),
				"target": String(row.get("target", "")),
				"expression": String(row.get("expression", "0")),
				"origin_id": String(row.get("origin_id", "")),
				"origin_name": String(row.get("origin_name", "Manuale")),
				"disabled": bool(row.get("disabled", false))
			})
	return result


# The old editable compensation boxes become ordinary manual-source grants on
# first normalization. Migration is idempotent and preserves the final total.
static func migrate_legacy(record: Dictionary, preserve_old_initiative: bool = false) -> void:
	var rows: Array[Dictionary] = grants(record)
	# A legacy initiative base could be manually overridden. Convert any
	# difference from the DEX-derived base into a separate source bonus.
	if preserve_old_initiative:
		var abilities: Dictionary = record.get("abilities", {})
		var old_manual: Dictionary = record.get("ability_bonuses", {})
		var dex: int = Rules.ability_modifier(int(abilities.get("dex", 10)) + int(old_manual.get("dex", 0)))
		var difference: int = int(record.get("initiative_base", dex)) - dex
		if difference != 0:
			var found := false
			for grant: Dictionary in rows:
				if String(grant.get("id", "")) == "legacy|initiative_base_adjustment":
					found = true
					break
			if not found:
				rows.append({"id": "legacy|initiative_base_adjustment",
					"target": "initiative", "expression": str(difference),
					"origin_id": "", "origin_name": "Correzione iniziativa precedente",
					"disabled": false})
	for mapping: Dictionary in [
		{"field": "max_hp_bonus", "target": "hp"},
		{"field": "armor_class_bonus", "target": "ac"},
		{"field": "initiative_bonus", "target": "initiative"},
		{"field": "speed_bonus", "target": "speed"}
	]:
		var field: String = String(mapping["field"])
		var amount: int = int(record.get(field, 0))
		_add_migrated(rows, String(mapping["target"]), amount)
		record[field] = 0
	var scores: Dictionary = record.get("ability_bonuses", {}).duplicate(true)
	for ability: String in ABILITIES:
		_add_migrated(rows, "ability:" + ability, int(scores.get(ability, 0)))
		scores[ability] = 0
	record["ability_bonuses"] = scores
	var slots: Variant = record.get("spell_slots_bonus", [])
	if slots is Array:
		var cleaned: Array = (slots as Array).duplicate(true)
		for level: int in range(1, mini(cleaned.size(), 10)):
			_add_migrated(rows, "slot:" + str(level), int(cleaned[level]))
			cleaned[level] = 0
		record["spell_slots_bonus"] = cleaned
	_add_migrated(rows, "pact_slot", int(record.get("pact_slots_bonus", 0)))
	record["pact_slots_bonus"] = 0
	var tracker_bonuses: Variant = record.get("resource_tracker_bonuses", {})
	if tracker_bonuses is Dictionary:
		for tracker_id: Variant in (tracker_bonuses as Dictionary).keys():
			_add_migrated(rows, "tracker:" + String(tracker_id), int(tracker_bonuses[tracker_id]))
		record["resource_tracker_bonuses"] = {}
	var overrides: Variant = record.get("attack_overrides", {})
	if overrides is Dictionary:
		var cleaned_overrides: Dictionary = (overrides as Dictionary).duplicate(true)
		for attack_id: Variant in cleaned_overrides.keys():
			var settings: Variant = cleaned_overrides[attack_id]
			if not settings is Dictionary:
				continue
			var entry: Dictionary = settings as Dictionary
			_add_migrated(rows, "attack_hit:" + String(attack_id), int(entry.get("bonus", 0)))
			_add_migrated(rows, "attack_damage:" + String(attack_id), int(entry.get("bonus", 0)))
			_add_migrated(rows, "attack_range:" + String(attack_id), int(entry.get("range_bonus", 0)))
			entry["bonus"] = 0
			entry["range_bonus"] = 0
			cleaned_overrides[attack_id] = entry
		record["attack_overrides"] = cleaned_overrides
	record["formula_bonuses"] = rows


static func _add_migrated(rows: Array[Dictionary], target: String, amount: int) -> void:
	if amount == 0:
		return
	for row: Dictionary in rows:
		if String(row.get("id", "")) == "legacy|" + target:
			return
	rows.append({
		"id": "legacy|" + target, "target": target, "expression": str(amount),
		"origin_id": "", "origin_name": "Bonus manuale precedente", "disabled": false
	})


static func available_origins(record: Dictionary) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var seen: Dictionary = {}
	var disabled_live: Dictionary = {}
	for source: Dictionary in Proficiencies.origins(record):
		var sid: String = String(source.get("id", ""))
		if sid.is_empty() or seen.has(sid):
			continue
		if sid.begins_with("item:") or sid.begins_with("feature:"):
			# These identities are live only while the item/feature really exists.
			disabled_live[sid] = bool(source.get("disabled", false))
			continue
		seen[sid] = true
		results.append({"id": sid, "name": String(source.get("name", "")), "disabled": bool(source.get("disabled", false))})
	for feature: Dictionary in Traits.collect_features(record):
		var sid: String = "feature:" + String(feature.get("key", ""))
		if sid == "feature:" or seen.has(sid):
			continue
		seen[sid] = true
		results.append({"id": sid, "name": "Tratto · " + String(feature.get("name", "")), "disabled": bool(disabled_live.get(sid, false))})
	var inv: Variant = record.get("inventory", [])
	if inv is Array:
		for owned: Variant in inv:
			if not owned is Dictionary:
				continue
			var sid: String = "item:" + String((owned as Dictionary).get("id", ""))
			if sid == "item:" or seen.has(sid):
				continue
			seen[sid] = true
			results.append({"id": sid, "name": "Oggetto · " + String((owned as Dictionary).get("name", "")), "disabled": bool(disabled_live.get(sid, false))})
	return results


static func _origin_active(sid: String, enabled: Dictionary) -> bool:
	return sid.is_empty() or bool(enabled.get(sid, false))


static func _source_map(record: Dictionary) -> Dictionary:
	var enabled: Dictionary = {}
	for source: Dictionary in available_origins(record):
		enabled[String(source.get("id", ""))] = not bool(source.get("disabled", false))
	return enabled


static func symbol_target(symbol: String) -> String:
	if symbol.ends_with("_score") and symbol.trim_suffix("_score") in ABILITIES:
		return "ability:" + symbol.trim_suffix("_score")
	if symbol.ends_with("_mod") and symbol.trim_suffix("_mod") in ABILITIES:
		return "ability_mod:" + symbol.trim_suffix("_mod")
	if symbol.begins_with("save_") and symbol.substr(5) in ABILITIES:
		return "save:" + symbol.substr(5)
	if symbol.begins_with("skill_"):
		return "skill:" + symbol.substr(6).replace("_", " ")
	match symbol:
		"proficiency", "prof": return "proficiency"
		"initiative": return "initiative"
		"ac": return "ac"
		"speed": return "speed"
		"max_hp": return "hp"
		"passive_perception": return "passive_perception"
		"level": return "level"
	return ""


static func _evaluate_expression(record: Dictionary, expression: String, stack: Dictionary) -> Dictionary:
	var expr: String = expression.strip_edges().to_lower()
	if expr.is_empty() or expr.contains("d20") or expr.contains("d6"):
		return {"ok": false, "error": "Formula vuota o con dadi"}
	var allowed: RegEx = RegEx.create_from_string("^[0-9a-z_ .+*/()\\-]+$")
	if allowed == null or allowed.search(expr) == null:
		return {"ok": false, "error": "Sono ammessi solo numeri, +, -, *, /, parentesi e variabili"}
	var names: PackedStringArray = []
	var values: Array = []
	var identifiers: RegEx = RegEx.create_from_string("[a-z_][a-z0-9_]*")
	for found: RegExMatch in identifiers.search_all(expr):
		var name: String = found.get_string()
		if name in names:
			continue
		var target: String = symbol_target(name)
		if target.is_empty():
			return {"ok": false, "error": "Variabile sconosciuta: " + name}
		var dependent: Dictionary = _resolve(record, target, stack)
		if not bool(dependent.get("ok", false)):
			return dependent
		names.append(name)
		values.append(float(dependent.get("value", 0)))
	var parser := Expression.new()
	if parser.parse(expr, names) != OK:
		return {"ok": false, "error": "Sintassi non valida: " + expr}
	var number: Variant = parser.execute(values, null, false)
	if parser.has_execute_failed() or not (number is int or number is float):
		return {"ok": false, "error": "Impossibile calcolare: " + expr}
	if is_nan(float(number)) or is_inf(float(number)):
		return {"ok": false, "error": "Risultato non finito"}
	return {"ok": true, "value": roundi(float(number))}


static func _base(record: Dictionary, target: String, stack: Dictionary) -> Dictionary:
	var abilities: Dictionary = record.get("abilities", {})
	var legacy: Dictionary = record.get("ability_bonuses", {})
	if target.begins_with("ability:"):
		var ability: String = target.substr(8)
		if ability in ABILITIES:
			return {"ok": true, "value": int(abilities.get(ability, 10)) + int(legacy.get(ability, 0))}
	if target.begins_with("ability_mod:"):
		var ability: String = target.substr(12)
		if ability in ABILITIES:
			var score: Dictionary = _resolve(record, "ability:" + ability, stack)
			if not bool(score.get("ok", false)):
				return score
			return {"ok": true, "value": Rules.ability_modifier(int(score["value"]))}
	if target == "level":
		return {"ok": true, "value": int(record.get("level", 1))}
	if target == "proficiency":
		if String(record.get("kind", "")) == "monster" or record.has("stat_block"):
			var cr: float = Rules.monster_cr_value(record.get("stat_block", {}))
			return {"ok": true, "value": 2 + maxi(0, floori((cr - 1.0) / 4.0))}
		return {"ok": true, "value": Rules.proficiency_bonus(record)}
	if target == "initiative":
		var dex: Dictionary = _resolve(record, "ability_mod:dex", stack)
		if not bool(dex.get("ok", false)):
			return dex
		return {"ok": true, "value": int(dex["value"]) + int(record.get("initiative_bonus", 0))}
	if target == "ac":
		return {"ok": true, "value": int(record.get("armor_class_base", 10)) + int(record.get("armor_class_bonus", 0)) + Items.shield_bonus(record.get("inventory", []))}
	if target == "speed":
		return {"ok": true, "value": int(record.get("speed_base", record.get("speed", 30))) + int(record.get("speed_bonus", 0))}
	if target == "hp":
		return {"ok": true, "value": int(record.get("max_hp_base", record.get("max_hp", 1))) + int(record.get("max_hp_bonus", 0))}
	if target == "second_max":
		return {"ok": true, "value": int(record.get("second_form_max_hp", 0))}
	if target.begins_with("save:"):
		var ability: String = target.substr(5)
		if ability in ABILITIES:
			var modifier: Dictionary = _resolve(record, "ability_mod:" + ability, stack)
			if not bool(modifier.get("ok", false)):
				return modifier
			var known: bool = Proficiencies.has_proficiency(record, "save", ability)
			var stat: Dictionary = record.get("stat_block", {})
			var saves: Variant = stat.get("save", {})
			if not known and String(record.get("kind", "")) == "monster" and saves is Dictionary and String((saves as Dictionary).get(ability, "")).is_valid_int():
				return {"ok": true, "value": int((saves as Dictionary)[ability])}
			var prof: Dictionary = _resolve(record, "proficiency", stack) if known else {"ok": true, "value": 0}
			if not bool(prof.get("ok", false)):
				return prof
			return {"ok": true, "value": int(modifier["value"]) + int(prof["value"])}
	if target.begins_with("skill:"):
		var key: String = target.substr(6)
		for skill: Dictionary in Skills.SKILLS:
			if String(skill.get("id", "")) != key:
				continue
			var ability: String = String(skill.get("ability", "wis"))
			var modifier: Dictionary = _resolve(record, "ability_mod:" + ability, stack)
			var prof: Dictionary = _resolve(record, "proficiency", stack)
			if not bool(modifier.get("ok", false)):
				return modifier
			if not bool(prof.get("ok", false)):
				return prof
			var rank: int = 2 if Proficiencies.has_proficiency(record, "expertise", key) else 1 if Proficiencies.has_proficiency(record, "skill", key) else 0
			if String(record.get("kind", "")) == "monster" and not bool(record.get("skill_ranks_custom", false)):
				var ranks: Dictionary = Skills.ranks_from_bestiary(record, int(prof["value"]), abilities)
				rank = maxi(rank, int(ranks.get(key, 0)))
			return {"ok": true, "value": int(modifier["value"]) + rank * int(prof["value"])}
	if target == "passive_perception":
		var perception: Dictionary = _resolve(record, "skill:perception", stack)
		if not bool(perception.get("ok", false)):
			return perception
		return {"ok": true, "value": 10 + int(perception["value"])}
	# Other numeric targets (attack and slots) supply their native base.
	return {"ok": true, "value": 0}


static func _resolve(record: Dictionary, target: String, stack: Dictionary) -> Dictionary:
	if stack.has(target):
		return {"ok": false, "error": "Dipendenza circolare: " + target}
	var path: Dictionary = stack.duplicate()
	path[target] = true
	var base: Dictionary = _base(record, target, path)
	if not bool(base.get("ok", false)):
		return base
	var sum: Dictionary = _sum(record, target, path)
	return {"ok": true, "value": int(base.get("value", 0)) + int(sum["value"])}


static func _sum(record: Dictionary, target: String, stack: Dictionary) -> Dictionary:
	var total := 0
	var details: PackedStringArray = []
	var errors: PackedStringArray = []
	var target_grants: Array[Dictionary] = []
	for row: Dictionary in grants(record):
		if String(row.get("target", "")) == target and not bool(row.get("disabled", false)):
			target_grants.append(row)
	if target_grants.is_empty():
		return {"value": 0, "details": details, "errors": errors}
	var enabled: Dictionary = _source_map(record)
	for row: Dictionary in target_grants:
		if String(row.get("target", "")) != target or bool(row.get("disabled", false)):
			continue
		var sid: String = String(row.get("origin_id", ""))
		if not _origin_active(sid, enabled):
			continue
		var evaluated: Dictionary = _evaluate_expression(record, String(row.get("expression", "0")), stack)
		var origin: String = String(row.get("origin_name", "Manuale"))
		if not bool(evaluated.get("ok", false)):
			errors.append("%s: %s" % [origin, String(evaluated.get("error", "Formula non valida"))])
			continue
		var value: int = int(evaluated["value"])
		total += value
		details.append("%s: %s = %+d" % [origin, row.get("expression", "0"), value])
	return {"value": total, "details": details, "errors": errors}


static func value(record: Dictionary, target: String) -> int:
	var result: Dictionary = _resolve(record, target, {})
	return int(result.get("value", 0))


static func bonus(record: Dictionary, target: String) -> int:
	return int(_sum(record, target, {target: true}).get("value", 0))


static func add(record: Dictionary, target: String, base: int) -> int:
	return base + bonus(record, target)


static func description(record: Dictionary, target: String) -> String:
	var result: Dictionary = _sum(record, target, {target: true})
	var details: PackedStringArray = result.get("details", PackedStringArray())
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	var lines := PackedStringArray()
	if not details.is_empty():
		lines.append("Bonus cumulabili: " + str(result.get("value", 0)))
		lines.append_array(details)
	if not errors.is_empty():
		lines.append("Bonus ignorati:")
		lines.append_array(errors)
	return "\n".join(lines)
