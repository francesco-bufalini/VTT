extends SceneTree

const Features = preload("res://vtt/creature_features.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")


func _initialize() -> void:
	call_deferred("run")


func _sheet(klass: String, subclass: String, level: int, source: String = "PHB") -> Dictionary:
	return {
		"kind": "character", "rules_version": "2014" if source == "PHB" else "2024",
		"class": klass, "class_source": source, "subclass": subclass,
		"subclass_source": "XGE", "level": level,
		"classes": [{"name": klass, "source": source, "level": level,
			"subclass": subclass, "subclass_source": "XGE"}],
		"abilities": {"str": 10, "dex": 14, "con": 10, "int": 12, "wis": 14, "cha": 14}
	}


func _trait_id(record: Dictionary, name: String) -> String:
	for feature: Dictionary in Features.collect_features(record):
		if String(feature.get("name", "")) == name:
			return "feature:" + String(feature.get("key", ""))
	return ""


func _has_origin(rows: Array[Dictionary], sid: String, kind: String, key: String) -> bool:
	for row: Dictionary in rows:
		if (String(row.get("origin_id", "")) == sid and String(row.get("kind", "")) == kind
			and String(row.get("key", "")) == key):
			return true
	return false


func run() -> void:
	var cases: Array[Dictionary] = [
		{"klass": "Bard", "subclass": "College of Swords", "level": 3,
			"name": "Bonus Proficiencies", "grants": [["armor", "medium"], ["weapon", "scimitar"]]},
		{"klass": "Cleric", "subclass": "Forge Domain", "level": 1,
			"name": "Bonus Proficiency", "grants": [["armor", "heavy"], ["tool", "smith's tools"]]},
		{"klass": "Druid", "subclass": "Circle of the Shepherd", "level": 2,
			"name": "Speech of the Woods", "grants": [["language", "sylvan"]]},
		{"klass": "Monk", "subclass": "Way of the Drunken Master", "level": 3,
			"name": "Bonus Proficiencies", "grants": [["skill", "performance"], ["tool", "brewer's supplies"]]},
		{"klass": "Rogue", "subclass": "Mastermind", "level": 3,
			"name": "Master of Intrigue", "grants": [["tool", "disguise kit"], ["tool", "forgery kit"]]},
		{"klass": "Rogue", "subclass": "Scout", "level": 3,
			"name": "Survivalist", "grants": [["skill", "nature"], ["skill", "survival"], ["expertise", "nature"], ["expertise", "survival"]]},
		{"klass": "Sorcerer", "subclass": "Storm Sorcery", "level": 1,
			"name": "Wind Speaker", "grants": [["language", "primordial"]]},
		{"klass": "Warlock", "subclass": "The Hexblade", "level": 1,
			"name": "Hex Warrior", "grants": [["armor", "medium"], ["armor", "shield"], ["weapon", "martial"]]}
	]
	for entry: Dictionary in cases:
		var record := _sheet(entry.klass, entry.subclass, entry.level)
		var sid := _trait_id(record, entry.name)
		assert(sid.begins_with("feature:class|phb|") and sid.contains("|subclass|"), entry.name)
		var rows: Array[Dictionary] = Proficiencies.choices(record)
		for grant: Array in entry.grants:
			assert(_has_origin(rows, sid, String(grant[0]), String(grant[1])), entry.name + ": " + String(grant[1]))
			assert(Proficiencies.has_proficiency(record, String(grant[0]), String(grant[1])), entry.name + ": active " + String(grant[1]))
		assert(Proficiencies.origins(record).any(func(origin): return String(origin.get("id", "")) == sid), entry.name + ": origin")
		assert(Proficiencies.is_mandatory_grant(record, sid, String(entry.grants[0][0]), String(entry.grants[0][1])), entry.name + ": mandatory")
		if entry.subclass == "Mastermind":
			var requirements: Array = []
			for origin: Dictionary in Proficiencies.origins(record):
				if String(origin.get("id", "")) == sid:
					requirements = origin.get("requirements", [])
			assert(requirements.any(func(item): return item.kind == "tool" and item.count == 1))
			assert(requirements.any(func(item): return item.kind == "language" and item.count == 2))
		var revised := _sheet(entry.klass, entry.subclass, entry.level, "XPHB")
		assert(_trait_id(revised, entry.name) != sid)
		assert(not Proficiencies.choices(revised).any(func(row): return String(row.get("origin_id", "")) == sid))
		if entry.level > 1:
			assert(_trait_id(_sheet(entry.klass, entry.subclass, entry.level - 1), entry.name).is_empty())
	print("PASS: eight XGE 2014 proficiency traits retain exact native origins")
	quit(0)
