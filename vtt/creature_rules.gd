extends RefCounted

# Static, public creature-rule helpers. Mutable resources/trackers have been
# retired from the creature sheet and are no longer generated here.

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


static func serialize_public_identity(creature: Dictionary) -> Dictionary:
	# No HP, ability scores, spell slots, secret notes, or full stat block.
	return {
		"creature_id": String(creature.get("id", "")),
		"owner_id": String(creature.get("owner_id", "")),
		"default_miniature_id": String(
			creature.get("default_miniature_id", "")
		)
	}


# Automatic calculations never select spells on behalf of a player.
# Only capacities and deterministic values are derived from class levels.
const HIT_DICE := {
	"barbarian": 12, "fighter": 10, "paladin": 10, "ranger": 10,
	"bard": 8, "cleric": 8, "druid": 8, "monk": 8, "rogue": 8,
	"warlock": 8, "artificer": 8, "sorcerer": 6, "wizard": 6
}
const SPELLS_KNOWN_2014 := {
	"bard": [0, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 15, 16, 18, 19, 19, 20, 22, 22, 22],
	"sorcerer": [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 12, 13, 13, 14, 14, 15, 15, 15, 15],
	"warlock": [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15],
	"ranger": [0, 0, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11]
}


static func level_classes(character: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = character.get("classes", [])
	if raw is Array:
		for value: Variant in raw:
			if value is Dictionary and not String(value.get("name", "")).is_empty():
				result.append((value as Dictionary).duplicate(true))
	if result.is_empty() and not String(character.get("class", "")).is_empty():
		result.append({
			"name": String(character.get("class", "")),
			"level": int(character.get("level", 1)),
			"source": String(character.get("class_source", ""))
		})
	return result


static func average_die(die: int) -> int:
	return maxi(1, (die + 2) / 2)


static func automatic_monster_hit_points(creature: Dictionary) -> Dictionary:
	var stat_value: Variant = creature.get("stat_block", {})
	if not stat_value is Dictionary:
		return {"available": false, "reason": "Blocco statistiche assente."}
	var stat: Dictionary = stat_value as Dictionary
	var hp_value: Variant = stat.get("hp", {})
	if hp_value is Dictionary and (hp_value as Dictionary).has("average"):
		return {
			"available": true,
			"value": maxi(1, int((hp_value as Dictionary).get("average", 1))),
			"detail": "Valore medio del blocco statistiche 5etools"
		}
	if hp_value is int or hp_value is float:
		return {"available": true, "value": maxi(1, int(hp_value)),
			"detail": "PF del blocco statistiche"}
	return {"available": false, "reason": "PF medi non presenti nel blocco statistiche."}


static func ability_modifier(score: int) -> int:
	return floori((float(score) - 10.0) / 2.0)


static func automatic_hit_points(character: Dictionary) -> Dictionary:
	var classes: Array[Dictionary] = level_classes(character)
	if classes.is_empty():
		return {"available": false, "reason": "Seleziona almeno una classe."}
	var abilities: Dictionary = character.get("abilities", {})
	var bonuses: Dictionary = character.get("ability_bonuses", {})
	var con_modifier: int = ability_modifier(int(abilities.get("con", 10)) + int(bonuses.get("con", 0)))
	var total: int = 0
	var parts: PackedStringArray = []
	var first_level: bool = true
	for cls: Dictionary in classes:
		var name: String = String(cls.get("name", "")).to_lower()
		var die: int = int(HIT_DICE.get(name, 0))
		if die <= 0:
			return {"available": false, "reason": "Dado vita non noto per " + String(cls.get("name", ""))}
		var count: int = clampi(int(cls.get("level", 1)), 1, 20)
		var subtotal: int = 0
		for index: int in range(count):
			var gain: int = (die if first_level else average_die(die)) + con_modifier
			subtotal += maxi(1, gain)
			first_level = false
		total += subtotal
		parts.append("%s %d (d%d): %d PF" % [
			String(cls.get("name", "")), count, die, subtotal
		])
	return {"available": true, "value": total, "detail": "; ".join(parts)}


static func proficiency_bonus(character: Dictionary) -> int:
	var total: int = 0
	for cls: Dictionary in level_classes(character):
		total += maxi(0, int(cls.get("level", 1)))
	return 2 + (clampi(total, 1, 20) - 1) / 4


static func spellcasting_limits(character: Dictionary) -> Dictionary:
	var classes: Array[Dictionary] = level_classes(character)
	var abilities: Dictionary = character.get("abilities", {})
	var edition: String = String(character.get("rules_version", "2014"))
	var lines: PackedStringArray = []
	var maximum_known: Dictionary = {}
	var prepared_capacity: Dictionary = {}
	var incomplete: bool = false
	for cls: Dictionary in classes:
		var name: String = String(cls.get("name", "")).to_lower()
		var lvl: int = clampi(int(cls.get("level", 1)), 1, 20)
		if edition == "2014" and SPELLS_KNOWN_2014.has(name):
			var known_table: Array = SPELLS_KNOWN_2014[name]
			var known_count: int = int(known_table[lvl])
			maximum_known[name] = known_count
			lines.append("%s: %d incantesimi conosciuti (2014)" % [cls.get("name", ""), known_count])
		elif edition == "2014" and name in ["cleric", "druid", "wizard", "paladin", "artificer"]:
			var stat: String = "int" if name in ["wizard", "artificer"] else "wis" if name in ["cleric", "druid"] else "cha"
			var modifier: int = floori((float(abilities.get(stat, 10)) - 10.0) / 2.0)
			var effective: int = lvl if name in ["cleric", "druid"] else ceili(float(lvl) / 2.0)
			var capacity: int = maxi(1, effective + modifier)
			if name == "paladin" and lvl < 2:
				capacity = 0
			prepared_capacity[name] = capacity
			lines.append("%s: %d incantesimi preparabili (2014)" % [cls.get("name", ""), capacity])
		elif name in ["fighter", "barbarian", "monk", "rogue"]:
			# Spellcasting subclasses are not represented by the class name.
			continue
		else:
			incomplete = true
			lines.append("%s: richiede regole di classe/sottoclasse (%s)" % [cls.get("name", ""), edition])
	return {
		"known_limits": maximum_known,
		"prepared_limits": prepared_capacity,
		"detail": "\n".join(lines),
		"incomplete": incomplete
	}
