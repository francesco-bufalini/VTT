extends RefCounted

const ClassMechanics = preload("res://vtt/class_mechanics_5etools.gd")

# Static, public creature-rule helpers. Mutable resources/trackers have been
# retired from the creature sheet and are no longer generated here.

const LEVEL_XP := [0, 0, 300, 900, 2700, 6500, 14000, 23000, 34000, 48000, 64000, 85000, 100000, 120000, 140000, 165000, 195000, 225000, 265000, 305000, 355000]
const MONSTER_TYPES := {
	"aberration": "Aberrazione", "beast": "Bestia", "celestial": "Celestiale",
	"construct": "Costrutto", "dragon": "Drago", "elemental": "Elementale",
	"fey": "Folletto", "fiend": "Immondo", "giant": "Gigante",
	"humanoid": "Umanoide", "monstrosity": "Mostruosità", "ooze": "Melma",
	"plant": "Vegetale", "undead": "Non morto"
}


static func experience_for_level(level: int) -> int:
	return LEVEL_XP[clampi(level, 0, 20)]


# The monster's challenge rating remains in the original stat block (including
# fractions), while the displayed class level is always an integer.
static func monster_level(stat: Dictionary) -> int:
	return maxi(0, roundi(monster_cr_value(stat)))


static func monster_type_reference(stat: Dictionary) -> Dictionary:
	var raw: Variant = stat.get("type", "")
	var type_code: String = String(raw.get("type", "") if raw is Dictionary else raw).strip_edges().to_lower()
	if type_code.is_empty():
		return {}
	return {
		"id": "monster_type|" + type_code,
		"name": String(MONSTER_TYPES.get(type_code, type_code.capitalize())),
		"source": "5etools",
		"type_code": type_code
	}


# 5etools speed may be a number, or a map with walk/fly/swim speeds.
# The creature type and subtype are distinct from any character class.
# 5etools monster type tags describe subtypes, not class archetypes.
static func monster_subtype(stat: Dictionary) -> String:
	var raw: Variant = stat.get("type", {})
	if not raw is Dictionary:
		return ""
	var tags: Variant = (raw as Dictionary).get("tags", [])
	if not tags is Array:
		return ""
	var labels: PackedStringArray = []
	for item: Variant in tags:
		var label: String = String(item.get("tag", "") if item is Dictionary else item).strip_edges()
		if not label.is_empty() and label not in labels:
			labels.append(label)
	return ", ".join(labels)


static func species_creature_type(species: Dictionary) -> String:
	# Most playable races are humanoids. Some 5etools races (e.g. an
	# Autognome or a Fairy) state a non-humanoid Creature Type explicitly.
	var raw: String = String(species.get("creature_type", "")).to_lower()
	if raw.is_empty():
		var entries: Variant = species.get("entries", [])
		if entries is Array:
			for value: Variant in entries:
				if value is Dictionary and String((value as Dictionary).get("name", "")).to_lower() == "creature type":
					raw = JSON.stringify((value as Dictionary).get("entries", [] )).to_lower()
					break
	for code: String in MONSTER_TYPES.keys():
		if code in raw:
			return String(MONSTER_TYPES[code])
	return String(MONSTER_TYPES["humanoid"])


static func walking_speed(raw: Variant, fallback: int = 30) -> int:
	if raw is int or raw is float:
		return maxi(0, int(raw))
	if raw is Dictionary:
		var walk: Variant = (raw as Dictionary).get("walk", fallback)
		if walk is int or walk is float:
			return maxi(0, int(walk))
	return fallback


# Only Burrow, Climb, Fly and Swim are separate movement speeds in 5e.
# Crawling and jumping consume movement; they are not independent speeds.
const SPECIAL_SPEEDS := ["climb", "swim", "fly", "burrow"]


static func _movement_feet(raw: Variant) -> int:
	if raw is int or raw is float:
		return maxi(0, int(raw))
	if raw is String:
		var words: String = String(raw).strip_edges().split(" ")[0]
		if words.is_valid_int():
			return maxi(0, int(words))
	if raw is Dictionary:
		var definition: Dictionary = raw
		return _movement_feet(definition.get("number", definition.get("value", 0)))
	return 0


static func special_speed_base(record: Dictionary, movement: String) -> int:
	if movement not in SPECIAL_SPEEDS:
		return 0
	var source: Variant = {}
	if String(record.get("kind", "character")) == "monster":
		var stat: Variant = record.get("stat_block", {})
		if stat is Dictionary:
			source = (stat as Dictionary).get("speed", {})
	else:
		# Caller-supplied current race/subrace speed, not persisted in saves.
		source = record.get("species_speed", {})
	var speed_data: Dictionary = source if source is Dictionary else {}
	# Explicit overrides can add a mode (or set it to zero).
	var explicit: Variant = record.get("movement_speeds", {})
	if explicit is Dictionary:
		speed_data = speed_data.merged(explicit, true)
	return _movement_feet(speed_data.get(movement, 0))


# Damage is resolved in layers: temporary HP, transformed-form HP, then base HP.
# Both UI actions and combat attacks call this helper to remain consistent.
static func apply_damage_layers(record: Dictionary, amount: int) -> Dictionary:
	var result: Dictionary = record.duplicate(true)
	var remaining: int = maxi(0, amount)
	var temp: int = maxi(0, int(result.get("temporary_hp", 0)))
	var form_hp: int = maxi(0, int(result.get("second_form_hp", 0)))
	var base_hp: int = maxi(0, int(result.get("current_hp", 0)))
	var absorbed: int = mini(remaining, temp)
	temp -= absorbed
	remaining -= absorbed
	absorbed = mini(remaining, form_hp)
	form_hp -= absorbed
	remaining -= absorbed
	result["temporary_hp"] = temp
	result["second_form_hp"] = form_hp
	result["current_hp"] = maxi(0, base_hp - remaining)
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


# Preserve fractional 5etools Challenge Ratings (1/8, 1/4, 1/2).
static func monster_cr_value(stat: Dictionary) -> float:
	var raw: Variant = stat.get("cr", 0)
	if raw is Dictionary:
		raw = (raw as Dictionary).get("cr", 0)
	if raw is float or raw is int:
		return maxf(0.0, float(raw))
	var label: String = String(raw).strip_edges()
	if "/" in label:
		var parts: PackedStringArray = label.split("/")
		if parts.size() == 2 and parts[0].is_valid_float() and parts[1].is_valid_float():
			var denominator: float = float(parts[1])
			if denominator > 0:
				return maxf(0.0, float(parts[0]) / denominator)
	return maxf(0.0, float(label)) if label.is_valid_float() else 0.0


# Bestiary reach is determined by its melee attack descriptions, not the
# miniature or its physical footprint. Ranged attacks do not increase reach.
static func monster_base_reach_feet(stat: Dictionary) -> float:
	var explicit: Variant = stat.get("reach", null)
	if explicit is float or explicit is int:
		return maxf(5.0, float(explicit))
	var maximum: float = 5.0
	for section: String in ["action", "bonus", "reaction", "legendary", "mythic", "trait"]:
		var entries: Variant = stat.get(section, [])
		if not entries is Array:
			continue
		for raw: Variant in entries:
			if not raw is Dictionary:
				continue
			var attack: Dictionary = raw as Dictionary
			var text_value: String = JSON.stringify(attack.get("entries", [])).to_lower()
			var pattern: RegEx = RegEx.create_from_string("reach\\s*(\\d+)\\s*(?:ft\\.?|feet)")
			if pattern == null:
				continue
			for match_value: RegExMatch in pattern.search_all(text_value):
				maximum = maxf(maximum, float(match_value.get_string(1)))
	return maximum


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


static func class_hit_die(klass_name: String, source: String = "") -> int:
	return ClassMechanics.hit_die(klass_name, source)


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
			"detail": "Valore medio del blocco statistiche"
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
	var con_modifier: int = int(character.get("effective_con_modifier", ability_modifier(int(abilities.get("con", 10)))))
	var total: int = 0
	var parts: PackedStringArray = []
	var first_level: bool = true
	for cls: Dictionary in classes:
		var name: String = String(cls.get("name", "")).to_lower()
		var die: int = ClassMechanics.hit_die(name, String(cls.get("source", "")))
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


static func automatic_hit_dice(character: Dictionary) -> String:
	var parts: PackedStringArray = []
	for cls: Dictionary in level_classes(character):
		var name: String = String(cls.get("name", "")).to_lower()
		var sides: int = ClassMechanics.hit_die(name, String(cls.get("source", "")))
		if sides > 0:
			parts.append("%dd%d (%s)" % [maxi(0, int(cls.get("level", 0))),
				sides, String(cls.get("name", ""))])
	return ", ".join(parts)


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
			var supplied: Dictionary = character.get("effective_ability_modifiers", {})
			var modifier: int = int(supplied.get(stat, ability_modifier(
				int(abilities.get(stat, 10))
			)))
			var effective: int = lvl if name in ["cleric", "druid", "wizard"] else ceili(float(lvl) / 2.0)
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


# 5e spell-slot progressions. Index 0 represents cantrips (no slot).
const FULL_CASTER_SLOTS := [
	[0,0,0,0,0,0,0,0,0,0],
	[0,2,0,0,0,0,0,0,0,0], [0,3,0,0,0,0,0,0,0,0],
	[0,4,2,0,0,0,0,0,0,0], [0,4,3,0,0,0,0,0,0,0],
	[0,4,3,2,0,0,0,0,0,0], [0,4,3,3,0,0,0,0,0,0],
	[0,4,3,3,1,0,0,0,0,0], [0,4,3,3,2,0,0,0,0,0],
	[0,4,3,3,3,1,0,0,0,0], [0,4,3,3,3,2,0,0,0,0],
	[0,4,3,3,3,2,1,0,0,0], [0,4,3,3,3,2,1,0,0,0],
	[0,4,3,3,3,2,1,1,0,0], [0,4,3,3,3,2,1,1,0,0],
	[0,4,3,3,3,2,1,1,1,0], [0,4,3,3,3,2,1,1,1,0],
	[0,4,3,3,3,2,1,1,1,1], [0,4,3,3,3,3,1,1,1,1],
	[0,4,3,3,3,3,2,1,1,1], [0,4,3,3,3,3,2,2,1,1]
]


static func spell_slot_progression(character: Dictionary) -> Dictionary:
	var classes: Array[Dictionary] = level_classes(character)
	var edition: String = String(character.get("rules_version", "2014"))
	var contributions: Array[Dictionary] = []
	var warlock_level := 0
	var warnings := PackedStringArray()
	for cls: Dictionary in classes:
		var name: String = String(cls.get("name", "")).to_lower()
		var level: int = clampi(int(cls.get("level", 1)), 1, 20)
		if name == "warlock":
			warlock_level += level
		elif name in ["bard", "cleric", "druid", "sorcerer", "wizard"]:
			contributions.append({"name": name, "level": level, "kind": "full"})
		elif name == "artificer":
			contributions.append({"name": name, "level": level, "kind": "half_up"})
		elif name in ["paladin", "ranger"]:
			if level >= 2 or edition == "2024":
				contributions.append({"name": name, "level": level, "kind": "half"})
		elif name in ["fighter", "rogue"]:
			warnings.append(
				"Le sottoclassi magiche di %s richiedono il calcolo manuale." % String(cls.get("name", ""))
			)
		elif name == "mostro":
			# CR is not a caster level; real class additions determine slots.
			pass
		elif not name.is_empty() and ClassMechanics.hit_die(name, String(cls.get("source", ""))) <= 0:
			warnings.append("Classe homebrew non calcolabile: " + String(cls.get("name", "")))
	var caster_level := 0
	var playable_classes: int = 0
	for cls: Dictionary in classes:
		if String(cls.get("name", "")).to_lower() != "mostro":
			playable_classes += 1
	var multiclass: bool = playable_classes > 1
	for contribution: Dictionary in contributions:
		var level: int = int(contribution.get("level", 0))
		match String(contribution.get("kind", "")):
			"full":
				caster_level += level
			"half_up":
				caster_level += ceili(float(level) / 2.0)
			"half":
				if multiclass and edition == "2014":
					caster_level += floori(float(level) / 2.0)
				else:
					caster_level += ceili(float(level) / 2.0)
	caster_level = clampi(caster_level, 0, 20)
	var slots: Array = FULL_CASTER_SLOTS[caster_level].duplicate()
	# Pact Magic uses a separate pool, refreshed on a short rest.
	var pact_total: int = 0
	var pact_level: int = 1
	if warlock_level >= 1:
		pact_total = 1 if warlock_level == 1 else 2 if warlock_level < 11 else 3 if warlock_level < 17 else 4
		pact_level = mini(5, ceili(float(warlock_level) / 2.0))
	return {
		"slots": slots,
		"pact_total": pact_total,
		"pact_level": pact_level,
		"warnings": "\n".join(warnings),
		"caster_level": caster_level
	}
