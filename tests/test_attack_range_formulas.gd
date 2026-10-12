extends SceneTree

const AttackData = preload("res://vtt/creature_attack_data.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var attack: Dictionary = {"id": "test-range", "range_feet": 30, "melee": false}
	var record: Dictionary = {"attack_overrides": {}}
	assert(AttackData.range_for(record, attack) == 30)

	# Bonus is additive; changing the base does not change the bonus.
	record["formula_bonuses"] = [{"id": "reach", "target": "attack_range:test-range", "expression": "10", "origin_id": ""}]
	assert(AttackData.range_for(record, attack) == 40)
	record["attack_overrides"] = {"test-range": {"range_feet": 50}}
	assert(AttackData.range_for(record, attack) == 60)

	# Tactical reach stays within legal limits even with negative modifiers.
	record["attack_overrides"] = {}
	(record["formula_bonuses"] as Array)[0]["expression"] = "-100"
	assert(AttackData.range_for(record, attack) == 5)
	record["attack_overrides"] = {"test-range": {"range_feet": 1000}}
	(record["formula_bonuses"] as Array)[0]["expression"] = "250"
	assert(AttackData.range_for(record, attack) == 1000)

	# Long range is an independent formula: a bonus cannot change the normal ring.
	var ranged: Dictionary = {
		"id": "longbow", "range_feet": 80, "long_range_feet": 320, "melee": false
	}
	var archer: Dictionary = {
		"attack_overrides": {},
		"formula_bonuses": [
			{"id": "long-bonus", "target": "attack_long_range:longbow",
				"expression": "40", "origin_id": ""}
		]
	}
	assert(AttackData.range_for(archer, ranged) == 80)
	assert(AttackData.long_range_for(archer, ranged) == 360,
		"Long-range bonus must not change normal weapon range")
	archer["attack_overrides"] = {"longbow": {"long_range_feet": 400}}
	assert(AttackData.long_range_for(archer, ranged) == 440,
		"Long-range base overrides and grants must compose")
	assert(AttackData.range_for(archer, ranged) == 80)
	(archer["formula_bonuses"] as Array)[0]["expression"] = "-1000"
	assert(AttackData.long_range_for(archer, ranged) == 5)
	assert(AttackData.long_range_for(archer, {"id": "longbow", "melee": true,
		"long_range_feet": 320}) == 0,
		"Melee attacks must not acquire a long-range formula")

	print("PASS: independent normal/long range formulas and clamps")
	quit()
