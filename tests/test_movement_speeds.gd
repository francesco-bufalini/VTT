extends SceneTree

const Rules = preload("res://vtt/creature_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var empty := {"kind": "character", "rules_version": "2014",
		"speed_base": 30, "species_speed": {"walk": 30}, "formula_bonuses": []}
	assert(Rules.SPECIAL_SPEEDS.size() == 4, "5e has four special movement modes")
	for mode: String in Rules.SPECIAL_SPEEDS:
		assert(Rules.special_speed_base(empty, mode) == 0
			and Bonuses.value(empty, "speed:" + mode) == 0,
			"Undeclared special speeds must default to zero, not to walking Speed")
	var monster := {"kind": "monster", "rules_version": "2014", "stat_block": {
		"speed": {"walk": 0, "fly": {"number": 60, "condition": "(hover)"},
			"swim": 30, "burrow": "15 ft"}
	}}
	assert(Rules.special_speed_base(monster, "fly") == 60
		and Bonuses.value(monster, "speed:swim") == 30
		and Bonuses.value(monster, "speed:burrow") == 15
		and Bonuses.value(monster, "speed:climb") == 0,
		"Monster speeds must come from structured bestiary data")
	var character := {"kind": "character", "rules_version": "2014",
		"speed_base": 30, "species_speed": {"walk": 30, "climb": 25},
		"movement_speeds": {"burrow": 10},
		"formula_bonuses": [
			{"target": "speed:climb", "expression": "5", "origin_id": ""},
			{"target": "speed:swim", "expression": "15", "origin_id": ""}
		]}
	assert(Bonuses.value(character, "speed:climb") == 30
		and Bonuses.value(character, "speed:burrow") == 10
		and Bonuses.value(character, "speed:swim") == 15
		and Bonuses.value(character, "speed:fly") == 0,
		"Species and originless bonuses add speeds, including initially missing modes")
	assert(Bonuses.symbol_target("fly_speed") == "speed:fly"
		and Bonuses.symbol_target("burrow_speed") == "speed:burrow",
		"Formula variables must reference each new speed target")
	character["rules_version"] = "2024"
	(character["formula_bonuses"] as Array).append(
		{"target": "speed", "expression": "5", "origin_id": ""})
	assert(Bonuses.value(character, "speed") == 35
		and Bonuses.value(character, "speed:climb") == 35
		and Bonuses.value(character, "speed:burrow") == 15
		and Bonuses.value(character, "speed:fly") == 0,
		"2024 Speed modifiers affect existing special speeds but cannot grant flying")
	assert(Rules.special_speed_base(character, "walk") == 0,
		"Walking speed is separate and is not a special speed")
	print("PASS: four 5e movement modes, zero defaults, monster/species origins and bonus targets")
	quit()
