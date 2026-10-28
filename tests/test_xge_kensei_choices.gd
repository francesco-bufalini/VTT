extends SceneTree

const Features = preload("res://vtt/creature_features.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const Mechanics = preload("res://vtt/feature_timing_recovery_rules.gd")

func _initialize() -> void:
	call_deferred("run")

func _sheet(level: int, source: String = "PHB", subclass: String = "Way of the Kensei") -> Dictionary:
	return {"kind": "character", "rules_version": "2014" if source == "PHB" else "2024",
		"class": "Monk", "class_source": source, "subclass": subclass,
		"subclass_source": "XGE", "level": level,
		"classes": [{"name": "Monk", "source": source, "level": level,
			"subclass": subclass, "subclass_source": "XGE"}],
		"abilities": {"str": 10, "dex": 16, "con": 10, "int": 10, "wis": 14, "cha": 10}}

func _trait_id(record: Dictionary) -> String:
	for feature: Dictionary in Features.collect_features(record):
		if String(feature.get("name", "")) == "Path of the Kensei":
			return "feature:" + String(feature.get("key", ""))
	return ""

func run() -> void:
	var record := _sheet(3)
	var sid := _trait_id(record)
	assert(sid.contains("|subclass|") and sid.ends_with("path%20of%20the%20kensei"))
	var requirement: Dictionary = {}
	for origin: Dictionary in Proficiencies.origins(record):
		if String(origin.get("id", "")) == sid:
			for choice: Dictionary in origin.get("requirements", []):
				if String(choice.get("kind", "")) == "tool":
					requirement = choice
	assert(int(requirement.get("count", 0)) == 1)
	assert(requirement.get("data", {}).get("choose", {}).get("from", []) == ["calligrapher's supplies", "painter's supplies"])
	assert(not Proficiencies.has_proficiency(record, "tool", "calligrapher's supplies"), "The choice must remain pending")
	assert(_trait_id(_sheet(2)).is_empty())
	assert(_trait_id(_sheet(3, "XPHB")) != sid)
	assert(_trait_id(_sheet(3, "PHB", "Way of the Drunken Master")).is_empty())
	var actions: Array[Dictionary] = Mechanics.action_entries(record, [])
	assert(actions.any(func(row): return String(row.get("rule_id", "")) == "monk_phb_xge_kensei_kenseis_shot" and String(row.get("activation", "")) == "bonus"))
	assert(not Mechanics.action_entries(_sheet(3, "XPHB"), []).any(func(row): return String(row.get("rule_id", "")) == "monk_phb_xge_kensei_kenseis_shot"))
	print("PASS: XGE Kensei choice and bonus action follow the exact 2014 traits")
	quit(0)
