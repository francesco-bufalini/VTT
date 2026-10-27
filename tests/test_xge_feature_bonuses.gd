extends SceneTree

const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Features = preload("res://vtt/creature_features.gd")
const Mechanics = preload("res://vtt/feature_timing_recovery_rules.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")


func _initialize() -> void:
	call_deferred("run")


func _sheet(klass: String, subclass: String, level: int, source: String = "PHB") -> Dictionary:
	return {
		"kind": "character", "class": klass, "class_source": source,
		"subclass": subclass, "subclass_source": "XGE", "level": level,
		"rules_version": "2014" if source == "PHB" else "2024",
		"classes": [{"name": klass, "source": source, "level": level,
			"subclass": subclass, "subclass_source": "XGE"}],
		"abilities": {"str": 10, "dex": 14, "con": 10, "int": 16, "wis": 14, "cha": 16},
		"speed_base": 30, "armor_class_base": 10, "max_hp_base": 20
	}


func _feature(record: Dictionary, name: String) -> Dictionary:
	for row: Dictionary in Features.collect_features(record):
		if String(row.get("name", "")) == name:
			return row
	return {}


func run() -> void:
	var cases: Array[Dictionary] = [
		{"class_name": "Wizard", "subclass": "War Magic", "level": 2,
			"name": "Tactical Wit", "target": "initiative", "amount": 3},
		{"class_name": "Rogue", "subclass": "Swashbuckler", "level": 3,
			"name": "Rakish Audacity", "target": "initiative", "amount": 3},
		{"class_name": "Rogue", "subclass": "Scout", "level": 9,
			"name": "Superior Mobility", "target": "speed", "amount": 10},
		{"class_name": "Fighter", "subclass": "Samurai", "level": 7,
			"name": "Elegant Courtier", "target": "skill:persuasion", "amount": 2}
	]
	for entry: Dictionary in cases:
		var record := _sheet(entry.class_name, entry.subclass, entry.level)
		var feature := _feature(record, entry.name)
		assert(not feature.is_empty(), "Missing granting trait: " + entry.name)
		var sid := "feature:" + String(feature.get("key", ""))
		assert(sid.contains("|phb|") and sid.contains("|subclass|"))
		assert(Bonuses.bonus(record, entry.target) == entry.amount, entry.name)
		var granted := false
		for row: Dictionary in Bonuses.grants(record):
			if String(row.get("origin_id", "")) == sid and String(row.get("target", "")) == entry.target:
				granted = true
		assert(granted, "Bonus must come from exact trait: " + entry.name)
		var muted := record.duplicate(true)
		muted["proficiency_origins"] = [{"id": sid, "group": "feature", "disabled": true}]
		assert(Bonuses.bonus(muted, entry.target) == 0)
		assert(Bonuses.bonus(_sheet(entry.class_name, entry.subclass, entry.level - 1), entry.target) == 0)
		assert(Bonuses.bonus(_sheet(entry.class_name, entry.subclass, entry.level, "XPHB"), entry.target) == 0)
	var war := _sheet("Wizard", "War Magic", 14)
	var reactions: Array[Dictionary] = Mechanics.action_entries(war, Trackers.for_creature(war))
	assert(reactions.size() == 1)
	assert(String(reactions[0].get("rule_id", "")) == "wizard_phb_war_arcane_deflection")
	assert(String(reactions[0].get("activation", "")) == "reaction")
	assert(Mechanics.action_entries(_sheet("Wizard", "War Magic", 14, "XPHB"), []).is_empty())
	print("PASS: 2014 XGE passive bonuses follow exact traits and stay out of 2024")
	quit(0)
