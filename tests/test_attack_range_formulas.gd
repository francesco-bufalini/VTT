extends SceneTree

const AttackData = preload("res://vtt/creature_attack_data.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var attack: Dictionary = {"id": "test-range", "range_feet": 30, "melee": false}
	var record: Dictionary = {"attack_overrides": {}}
	assert(AttackData.range_for(record, attack) == 30)

	# Bonus is additive; changing the base does not change the bonus.
	record["attack_overrides"] = {"test-range": {"range_bonus": 10}}
	assert(AttackData.range_for(record, attack) == 40)
	record["attack_overrides"] = {"test-range": {"range_feet": 50, "range_bonus": 10}}
	assert(AttackData.range_for(record, attack) == 60)

	# Tactical reach stays within legal limits even with negative modifiers.
	record["attack_overrides"] = {"test-range": {"range_bonus": -100}}
	assert(AttackData.range_for(record, attack) == 5)
	record["attack_overrides"] = {"test-range": {"range_feet": 1000, "range_bonus": 250}}
	assert(AttackData.range_for(record, attack) == 1000)

	print("PASS: attack range formula preserves base, bonus and clamps")
	quit()
