extends SceneTree

const Requirements = preload("res://vtt/benefit_requirements.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const Features = preload("res://vtt/creature_features.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var multiclass: Dictionary = {
		"kind": "character", "level": 12,
		"classes": [
			{"name": "Fighter", "source": "PHB", "level": 9},
			{"name": "Wizard", "source": "XPHB", "level": 3}
		],
		"abilities": {"str": 10, "dex": 10, "con": 10,
			"int": 10, "wis": 10, "cha": 10},
		"proficiency_origins": [], "proficiency_choices": [], "inventory": []
	}
	assert(Requirements.allows(multiclass,
		Requirements.level_gate(10, "character")))
	assert(not Requirements.allows(multiclass,
		Requirements.level_gate(10, "class", "Fighter", "PHB")))
	assert(Requirements.allows(multiclass,
		Requirements.level_gate(9, "class", "Fighter", "PHB")))
	assert(not Requirements.allows(multiclass,
		Requirements.level_gate(1, "class", "Wizard", "PHB")),
		"2014 and 2024 class sources must remain separate")
	assert(Requirements.allows(multiclass,
		Requirements.level_gate(3, "class", "Wizard", "XPHB")))
	assert(not Requirements.allows(multiclass,
		Requirements.level_gate(1, "class", "Druid", "PHB")))
	assert(not Requirements.allows(multiclass, {"scope": "character",
		"min_level": 1, "max_level": 10}))
	assert(Requirements.normalize({"min_level": 5}).get("min_level") == 5)
	assert(Requirements.normalize({"requirements": {
		"scope": "class", "class_name": "Wizard", "class_source": "XPHB",
		"min_level": 2
	}, "min_level": 20}).get("min_level") == 2)

	var unsorted: Array = [
		{"level": 6, "value": 5}, {"level": 1, "value": 1},
		{"level": 4, "value": 3}
	]
	assert(Requirements.highest_step(multiclass, unsorted,
		"class", "Fighter", "PHB").get("value") == 5)
	assert(Requirements.highest_step(multiclass, unsorted,
		"class", "Wizard", "XPHB").get("value") == 1)
	assert(Requirements.highest_step(multiclass, unsorted,
		"class", "Wizard", "PHB").is_empty())
	assert(Requirements.highest_step(multiclass, unsorted,
		"class", "Fighter", "PHB", 4).get("value") == 3)
	assert(Requirements.allows(
		{"kind": "character", "class": "Fighter", "level": 5},
		Requirements.level_gate(5, "class", "Fighter", "PHB")),
		"A legacy class without a source is still resolvable")

	# Leveling does not delete a stored manual resource's spent-use key.
	var tracker_record: Dictionary = multiclass.duplicate(true)
	tracker_record["level"] = 4
	tracker_record["resource_trackers"] = [
		{"id": "custom-gate", "name": "Progressive Charges",
		"max": 3, "requirements": {"scope": "character", "min_level": 5}}
	]
	tracker_record["resource_tracker_spent"] = {"custom-gate": 2}
	var tracker_found: bool = false
	for tr: Dictionary in Trackers.for_creature(tracker_record):
		tracker_found = tracker_found or tr.get("id") == "custom-gate"
	assert(not tracker_found)
	tracker_record["level"] = 5
	tracker_found = false
	for tr: Dictionary in Trackers.for_creature(tracker_record):
		tracker_found = tracker_found or tr.get("id") == "custom-gate"
	assert(tracker_found and tracker_record["resource_tracker_spent"]["custom-gate"] == 2)

	var bonus_record: Dictionary = {
		"kind": "character", "level": 2, "classes": [],
		"abilities": {"str": 10, "dex": 10, "con": 10, "int": 10,
			"wis": 10, "cha": 10},
		"inventory": [], "proficiency_origins": [], "proficiency_choices": [],
		"formula_bonuses": [{"id": "lvl5", "target": "initiative",
			"expression": "3", "requirements": {
				"scope": "character", "min_level": 5}}]
	}
	assert(Bonuses.bonus(bonus_record, "initiative") == 0)
	bonus_record["level"] = 5
	assert(Bonuses.bonus(bonus_record, "initiative") == 3)

	var candidates: Array[Dictionary] = [
		{"key": "class|phb|fighter|one", "name": "Shared Power",
			"class_name": "Fighter", "class_source": "PHB"},
		{"key": "class|xphb|wizard|two", "name": "Shared Power",
			"class_name": "Wizard", "class_source": "XPHB"},
		{"key": "feat|phb|other", "name": "Shared Power",
			"class_name": "", "class_source": ""}
	]
	assert(Trackers._find_tracker_feature({"origin": "Shared Power",
		"origin_class": "Wizard", "origin_class_source": "XPHB"},
		candidates).get("key") == "class|xphb|wizard|two")
	assert(Trackers._find_tracker_feature({"origin": "Shared Power",
		"origin_class": "Bard", "origin_class_source": "PHB"},
		candidates).is_empty())
	assert(Trackers._find_tracker_feature({"origin": "Shared Power"},
		candidates).is_empty(), "Ambiguous names must not resolve arbitrarily")
	assert(Trackers._find_tracker_feature({
		"origin_feature_key": "feature:class|phb|fighter|one",
		"origin": "Anything"}, candidates).get("key") == "class|phb|fighter|one")

	# Item trait sections can gate their display independently of item
	# ownership without duplicating item definitions.
	var item: Dictionary = {
		"id": "custom:level-item", "name": "Growing Relic",
		"quantity": 1, "active": true, "equipped": true,
		"entries": [
			{"name": "Basic", "entries": ["Description"]},
			{"name": "Advanced", "min_level": 5,
				"entries": ["Description"]}
		]
	}
	var item_record: Dictionary = {"kind": "character", "level": 3,
		"inventory": [item]}
	var names: Array[String] = []
	for feature: Dictionary in Features.collect_features(item_record):
		names.append(String(feature.get("name", "")))
	assert("Basic" in names and not ("Advanced" in names))
	item_record["level"] = 5
	names.clear()
	for feature: Dictionary in Features.collect_features(item_record):
		names.append(String(feature.get("name", "")))
	assert("Basic" in names and "Advanced" in names)

	print("PASS: canonical benefit thresholds, class scope, origin identities and item sections")
	quit()
