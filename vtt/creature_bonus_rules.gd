extends RefCounted

# Every numeric formula target may receive several independent, additive grants.
# "expression" is deliberately arithmetic only: no dice and no method calls.
const BenefitRequirements = preload("res://vtt/benefit_requirements.gd")
const Rules = preload("res://vtt/creature_rules.gd")
const RaceRules = preload("res://vtt/creature_race_rules.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const Skills = preload("res://vtt/creature_skills_5etools.gd")
const Items = preload("res://vtt/creature_item_rules.gd")
const Features = preload("res://vtt/creature_features.gd")
const Structured = preload("res://vtt/creature_structured_bonuses.gd")
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]


static func _saved_grants(record: Dictionary) -> Array[Dictionary]:
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
				"requirements": BenefitRequirements.normalize(row),
				"origin_id": String(row.get("origin_id", "")),
				"origin_name": String(row.get("origin_name", "Senza origine")),
				"disabled": bool(row.get("disabled", false)),
				"automatic": bool(row.get("automatic", false)) or String(row.get("id", "")).begins_with("auto|")
			})
	return result


static func grants(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var disabled_auto: Dictionary = {}
	for row: Dictionary in _saved_grants(record):
		if bool(row.get("automatic", false)):
			disabled_auto[String(row.get("id", ""))] = bool(row.get("disabled", false))
		else:
			result.append(row)
	for automatic: Dictionary in Structured.derive(record):
		automatic["disabled"] = bool(disabled_auto.get(String(automatic.get("id", "")), false))
		result.append(automatic)
	return result



static func available_origins(record: Dictionary) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var seen: Dictionary = {}
	var disabled_live: Dictionary = {}
	var inactive_live: Dictionary = {}
	var effective: Dictionary = Proficiencies.origin_enabled_map(record)
	for source: Dictionary in Proficiencies.origins(record):
		var sid: String = String(source.get("id", ""))
		if sid.is_empty() or seen.has(sid):
			continue
		if sid.begins_with("item:") or sid.begins_with("feature:"):
			# These identities are live only while the item/feature really exists.
			disabled_live[sid] = bool(source.get("disabled", false))
			inactive_live[sid] = not bool(effective.get(sid, false))
			continue
		seen[sid] = true
		results.append({"id": sid, "name": String(source.get("name", "")),
			"disabled": bool(source.get("disabled", false)),
			"inactive": not bool(effective.get(sid, false))})
	for feature: Dictionary in Features.collect_features(record):
		var sid: String = "feature:" + String(feature.get("key", ""))
		if sid == "feature:" or seen.has(sid):
			continue
		seen[sid] = true
		var inactive: bool = not bool(effective.get(sid, false))
		# Feat feature traits are children of the feat, not independent
		# sources that can keep granting bonuses after the feat is muted.
		var origin_key: String = String(feature.get("origin_key", ""))
		if origin_key.begins_with("feat|"):
			for feat: Variant in record.get("feats_catalog", []):
				if feat is Dictionary:
					var feat_id: String = String(feat.get("id", ""))
					if feat_id.is_empty():
						feat_id = String(feat.get("name", "")).to_lower() + "|" + String(feat.get("source", "")).to_lower()
					if origin_key == "feat|" + feat_id:
						inactive = inactive or not bool(effective.get(Proficiencies.feat_source_id(feat), false))
						break
		results.append({"id": sid, "name": "Tratto · " + String(feature.get("name", "")),
			"disabled": bool(disabled_live.get(sid, false)), "inactive": inactive})
	var inv: Variant = record.get("inventory", [])
	if inv is Array:
		for owned: Variant in inv:
			if not owned is Dictionary:
				continue
			var sid: String = "item:" + String((owned as Dictionary).get("id", ""))
			if sid == "item:" or seen.has(sid):
				continue
			seen[sid] = true
			results.append({"id": sid, "name": "Oggetto · " + String((owned as Dictionary).get("name", "")),
				"disabled": bool(disabled_live.get(sid, false)),
				"inactive": not bool(effective.get(sid, false))})
	for row: Dictionary in Structured.derive(record):
		var sid: String = String(row.get("origin_id", ""))
		if sid.is_empty() or seen.has(sid):
			continue
		seen[sid] = true
		results.append({"id": sid, "name": String(row.get("origin_name", sid)),
			"disabled": bool(disabled_live.get(sid, false)),
			"inactive": bool(inactive_live.get(sid, false))})
	return results


static func _origin_active(sid: String, enabled: Dictionary) -> bool:
	return sid.is_empty() or bool(enabled.get(sid, false))


static func _source_map(record: Dictionary) -> Dictionary:
	var enabled: Dictionary = {}
	for source: Dictionary in available_origins(record):
		enabled[String(source.get("id", ""))] = not bool(source.get("inactive", source.get("disabled", false)))
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
		"climb_speed": return "speed:climb"
		"swim_speed": return "speed:swim"
		"fly_speed": return "speed:fly"
		"burrow_speed": return "speed:burrow"
		"max_hp": return "hp"
		"passive_perception": return "passive_perception"
		"level": return "level"
		"attunement_max", "max_attunements": return "attunement_max"
	return ""



# Follow both explicit formula references and implicit derived-stat dependencies.
# The stack check in _resolve prevents infinite recursion, but on its own two
# mutually dependent grants could evaluate differently depending on query order.
# Reject every grant belonging to a dependency cycle before evaluating it.
static func _expression_dependencies(expression: String) -> Array[String]:
	var result: Array[String] = []
	var identifiers: RegEx = RegEx.create_from_string("[a-z_][a-z0-9_]*")
	for found: RegExMatch in identifiers.search_all(expression.to_lower()):
		var dependency: String = symbol_target(found.get_string())
		if not dependency.is_empty() and dependency not in result:
			result.append(dependency)
	return result


static func _native_dependencies(record: Dictionary, target: String) -> Array[String]:
	var result: Array[String] = []
	if target.begins_with("ability_mod:"):
		var ability: String = target.substr(12)
		if ability in ABILITIES:
			result.append("ability:" + ability)
	elif target == "initiative":
		result.append("ability_mod:dex")
	elif target.begins_with("speed:"):
		var movement: String = target.substr(6)
		if movement in Rules.SPECIAL_SPEEDS and String(record.get("rules_version", "2014")) == "2024" and Rules.special_speed_base(record, movement) > 0:
			result.append("speed")
	elif target == "ac":
		var armor := Items.equipped_armor(record.get("inventory", []))
		if not armor.is_empty() and Items.armor_uses_dexterity(Items.entry_for(armor)):
			result.append("ability_mod:dex")
	elif target.begins_with("save:"):
		var ability: String = target.substr(5)
		if ability in ABILITIES:
			result.append("ability_mod:" + ability)
			result.append("proficiency")
	elif target.begins_with("skill:"):
		for skill: Dictionary in Skills.SKILLS:
			if String(skill.get("id", "")) == target.substr(6):
				result.append("ability_mod:" + String(skill.get("ability", "wis")))
				result.append("proficiency")
				break
	elif target == "passive_perception":
		result.append("skill:perception")
	return result


static func _dependency_reaches(
	record: Dictionary, current: String, wanted: String,
	rows: Array[Dictionary], enabled: Dictionary, visited: Dictionary
) -> bool:
	if current == wanted:
		return true
	if visited.has(current):
		return false
	visited[current] = true
	for dependency: String in _native_dependencies(record, current):
		if _dependency_reaches(record, dependency, wanted, rows, enabled, visited):
			return true
	for row: Dictionary in rows:
		if (String(row.get("target", "")) != current
			or bool(row.get("disabled", false))
			or not _origin_active(String(row.get("origin_id", "")), enabled)):
			continue
		for dependency: String in _expression_dependencies(String(row.get("expression", ""))):
			if _dependency_reaches(record, dependency, wanted, rows, enabled, visited):
				return true
	return false


static func _would_cycle(
	record: Dictionary, target: String, expression: String,
	rows: Array[Dictionary], enabled: Dictionary
) -> bool:
	for dependency: String in _expression_dependencies(expression):
		if _dependency_reaches(record, dependency, target, rows, enabled, {}):
			return true
	return false


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


# Alternative base AC formulas never add together. Each candidate retains its
# actual granting trait; disabling that origin withdraws only that candidate.
static func natural_armor_options(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not Items.equipped_armor(record.get("inventory", [])).is_empty():
		return result
	var enabled := Proficiencies.origin_enabled_map(record)
	var shield := not Items.occupying(record.get("inventory", []), "off").is_empty() and Items.kind(Items.entry_for(Items.occupying(record.get("inventory", []), "off"))) == "shield"
	shield = shield or Items.shield_bonus(record.get("inventory", [])) > 0
	for feature: Dictionary in Features.collect_features(record):
		var sid := "feature:" + String(feature.get("key", ""))
		if bool(feature.get("inactive", false)) or not bool(enabled.get(sid, true)):
			continue
		var name := String(feature.get("name", ""))
		var owner := String(feature.get("class_name", ""))
		var book := String(feature.get("class_source", ""))
		var formula := ""
		if name == "Unarmored Defense" and owner == "Barbarian" and book in ["PHB", "XPHB"]:
			formula = "10 + dex_mod + con_mod"
		elif name == "Unarmored Defense" and owner == "Monk" and book in ["PHB", "XPHB"] and not shield:
			formula = "10 + dex_mod + wis_mod"
		elif name == "Unarmored Defense" and owner == "Bard" and book == "XPHB" and not shield:
			formula = "10 + dex_mod + cha_mod"
		elif name == "Draconic Resilience" and owner == "Sorcerer":
			if book == "PHB": formula = "13 + dex_mod"
			elif book == "XPHB": formula = "10 + dex_mod + cha_mod"
		if not formula.is_empty():
			result.append({"origin_id": sid, "origin_name": "Tratto · " + name, "expression": formula})
	return result


static func _base(record: Dictionary, target: String, stack: Dictionary) -> Dictionary:
	var abilities: Dictionary = record.get("abilities", {})
	if target.begins_with("ability:"):
		var ability: String = target.substr(8)
		if ability in ABILITIES:
			return {"ok": true, "value": int(abilities.get(ability, 10))}
	if target.begins_with("ability_mod:"):
		var ability: String = target.substr(12)
		if ability in ABILITIES:
			var score: Dictionary = _resolve(record, "ability:" + ability, stack)
			if not bool(score.get("ok", false)):
				return score
			return {"ok": true, "value": Rules.ability_modifier(int(score["value"]))}
	if target == "level":
		return {"ok": true, "value": int(record.get("level", 1))}
	if target == "attunement_max":
		return {"ok": true, "value": maxi(0, int(record.get("attunement_max_base", 3)))}
	if target == "proficiency":
		if String(record.get("kind", "")) == "monster" or record.has("stat_block"):
			var cr: float = Rules.effective_monster_cr(record)
			return {"ok": true, "value": 2 + maxi(0, floori((minf(cr, 30.0) - 1.0) / 4.0))}
		return {"ok": true, "value": Rules.proficiency_bonus(record)}
	if target == "initiative":
		var dex: Dictionary = _resolve(record, "ability_mod:dex", stack)
		if not bool(dex.get("ok", false)):
			return dex
		return {"ok": true, "value": int(dex["value"])}
	if target == "ac":
		if Items.equipped_armor(record.get("inventory", [])).is_empty():
			var default_formula: String = str(record.get("armor_class_base", 10))
			if String(record.get("kind", "")) == "monster":
				default_formula = str(Rules.monster_armor_class(record.get("stat_block", {})))
			elif int(record.get("armor_class_base", 10)) == 10:
				default_formula = "10 + dex_mod"
			var natural_formula: String = String(record.get("armor_natural_formula", default_formula)).strip_edges()
			var natural: Dictionary = _evaluate_expression(record, natural_formula, stack)
			# Malformed formulas do not crash the sheet or grant arbitrary AC.
			var natural_value: int = int(natural.get("value", record.get("armor_class_base", 10)))
			for option: Dictionary in natural_armor_options(record):
				var candidate := _evaluate_expression(record, String(option.expression), stack)
				if bool(candidate.get("ok", false)):
					natural_value = maxi(natural_value, int(candidate.value))
			return {"ok": true, "value": natural_value + Items.shield_bonus(record.get("inventory", []))}
		var armor_record: Dictionary = record
		var armor := Items.equipped_armor(record.get("inventory", []))
		if not armor.is_empty() and Items.armor_uses_dexterity(Items.entry_for(armor)):
			var dex: Dictionary = _resolve(record, "ability_mod:dex", stack)
			if not bool(dex.get("ok", false)):
				return dex
			armor_record = record.duplicate(false)
			armor_record["effective_armor_dex"] = int(dex["value"])
		return {"ok": true, "value": int(Items.armor_base(armor_record).get("value", 10)) + Items.shield_bonus(record.get("inventory", []))}
	if target == "speed":
		if String(record.get("kind", "character")) != "monster":
			var species_speed: Variant = record.get("species_speed", {})
			if not RaceRules.has_speed(species_speed):
				species_speed = RaceRules.speed_for_record(record)
			if RaceRules.has_speed(species_speed):
				return {"ok": true, "value": Rules.walking_speed(species_speed)}
		return {"ok": true, "value": int(record.get("speed_base", record.get("speed", 30)))}
	if target.begins_with("speed:"):
		var movement: String = target.substr(6)
		if movement in Rules.SPECIAL_SPEEDS:
			var base: int = Rules.special_speed_base(record, movement)
			# In the 2024 rules, increases/decreases to Speed also change any
			# existing special speeds. They never grant a missing movement mode.
			if base > 0 and String(record.get("rules_version", "2014")) == "2024":
				base += int(_sum(record, "speed", stack).get("value", 0))
			return {"ok": true, "value": base}
	if target == "hp":
		return {"ok": true, "value": int(record.get("max_hp_base", record.get("max_hp", 1)))}
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
	var all_grants: Array[Dictionary] = grants(record)
	for row: Dictionary in all_grants:
		if String(row.get("target", "")) == target and not bool(row.get("disabled", false)) and (
			BenefitRequirements.allows(record, BenefitRequirements.normalize(row))):
			target_grants.append(row)
	if target_grants.is_empty():
		return {"value": 0, "details": details, "errors": errors}
	var enabled: Dictionary = _source_map(record)
	for row: Dictionary in target_grants:
		if String(row.get("target", "")) != target or bool(row.get("disabled", false)) or (
			not BenefitRequirements.allows(record, BenefitRequirements.normalize(row))):
			continue
		var sid: String = String(row.get("origin_id", ""))
		if not _origin_active(sid, enabled):
			continue
		var origin: String = String(row.get("origin_name", "Senza origine"))
		# Reject cyclic grants consistently, not only whichever one happens to
		# hit _resolve's recursion guard first. Other additive grants survive.
		if _would_cycle(record, target, String(row.get("expression", "0")), all_grants, enabled):
			errors.append("%s: Dipendenza circolare (%s)" % [origin, target])
			continue
		var evaluated: Dictionary = _evaluate_expression(record, String(row.get("expression", "0")), stack)
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
	if target == "ac":
		for option: Dictionary in natural_armor_options(record):
			var base := _evaluate_expression(record, String(option.expression), {"ac": true})
			if bool(base.get("ok", false)):
				lines.append("%s: %s = %d (formula alternativa)" % [option.origin_name, option.expression, int(base.value)])
	if not details.is_empty():
		lines.append("Bonus cumulabili: " + str(result.get("value", 0)))
		lines.append_array(details)
	if not errors.is_empty():
		lines.append("Bonus ignorati:")
		lines.append_array(errors)
	return "\n".join(lines)
