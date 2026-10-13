extends RefCounted
const Rules = preload("res://vtt/creature_rules.gd")
const Mechanics = preload("res://vtt/class_mechanics_5etools.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Catalog = preload("res://vtt/spells/spell_catalog.gd")

static func classes(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for member: Dictionary in Rules.level_classes(record):
		var name: String = Catalog.canonical_class_name(String(member.get("name", "")))
		var source: String = String(member.get("source", ""))
		if source.is_empty():
			source = "XPHB" if String(record.get("rules_version", "2014")) == "2024" else "PHB"
		var data: Dictionary = Mechanics.class_row(name, source).get("spellcasting", {})
		if data.is_empty():
			continue
		var level: int = clampi(int(member.get("level", 1)), 1, 20)
		var prepared := -1
		var mode := "Conosciuti"
		if data.has("preparedSpellsProgression"):
			prepared = int(data.preparedSpellsProgression[level - 1])
			mode = "Preparati"
		elif data.has("preparedSpells"):
			var expression: String = String(data.preparedSpells).replace("<$level$>", str(level))
			for ability: String in ["str", "dex", "con", "int", "wis", "cha"]:
				expression = expression.replace("<$" + ability + "_mod$>", str(Bonuses.value(record, "ability_mod:" + ability)))
			var parser := Expression.new()
			if parser.parse(expression) == OK:
				var value: Variant = parser.execute([], null, false)
				if not parser.has_execute_failed():
					prepared = maxi(1, floori(float(value)))
			mode = "Preparati"
		elif data.has("spellsKnownProgression"):
			prepared = int(data.spellsKnownProgression[level - 1])
		var single: Dictionary = {"classes": [member], "rules_version": record.get("rules_version", "2014")}
		var progression: Dictionary = Rules.spell_slot_progression(single)
		var highest: int = int(progression.get("pact_level", 0)) if int(progression.get("pact_total", 0)) > 0 else 0
		for index: int in range(1, 10):
			if int(progression.get("slots", [])[index]) > 0:
				highest = maxi(highest, index)
		if highest == 0:
			prepared = 0
		result.append({"id": "class|" + source.to_lower() + "|" + name.to_lower(), "name": name,
			"source": source, "mode": mode, "limit": prepared, "max_level": highest,
			"cantrips": int(data.get("cantripProgression", [])[level - 1]) if data.has("cantripProgression") else 0,
			"book": name.to_lower() == "wizard"})
	return result

static func eligible(spell: Dictionary, member: Dictionary) -> bool:
	if bool(spell.get("internal_grant", false)) or int(spell.get("level", 0)) > int(member.get("max_level", 0)):
		return false
	for name: Variant in spell.get("classes", []):
		if Catalog.canonical_class_name(String(name)).nocasecmp_to(String(member.get("name", ""))) == 0:
			return true
	return false

static func sources(entry: Dictionary, record: Dictionary) -> Array:
	if entry.has("casting_classes"):
		return entry.get("casting_classes", [])
	var spell: Dictionary = Catalog.catalog_spell(String(entry.get("id", "")))
	var matches: Array = []
	for member: Dictionary in classes(record):
		if eligible(spell, member):
			matches.append(member.id)
	# Preserve ambiguous legacy selections visibly until the user assigns them.
	return matches if matches.size() == 1 else []

static func selected(record: Dictionary, entries: Array, class_id: String) -> Array[String]:
	var result: Array[String] = []
	for entry: Variant in entries:
		if entry is Dictionary and class_id in sources(entry, record):
			result.append(String(entry.get("id", "")))
	return result

static func apply(record: Dictionary, entries: Array, member: Dictionary, ids: Array) -> Array:
	var result: Array = []
	for raw: Variant in entries:
		if not raw is Dictionary:
			result.append(raw)
			continue
		var entry: Dictionary = raw.duplicate(true)
		var origins: Array = sources(entry, record).duplicate()
		if member.id in origins:
			origins.erase(member.id)
			if String(entry.get("id", "")) not in ids and origins.is_empty():
				continue
		entry["casting_classes"] = origins
		result.append(entry)
	for raw: Variant in ids:
		var id: String = String(raw)
		var found := false
		for entry: Variant in result:
			if entry is Dictionary and String(entry.get("id", "")) == id:
				var origins: Array = entry.get("casting_classes", [])
				if member.id not in origins:
					origins.append(member.id)
				entry["casting_classes"] = origins
				found = true
				break
		if not found:
			var spell: Dictionary = Catalog.catalog_spell(id)
			result.append({"id": id, "name": spell.get("name", id), "level": spell.get("level", 0),
				"source": spell.get("source", ""), "casting_classes": [member.id]})
	return result
