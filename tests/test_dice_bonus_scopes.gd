extends SceneTree
const Dice = preload("res://vtt/creature_dice_bonuses.gd")
const Applied = preload("res://vtt/creature_active_spells.gd")
const Content = preload("res://vtt/content_catalog.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var record := {"kind": "character", "dice_bonuses": [{"id": "d20", "target": "any_d20", "dice": "1d4", "origin_id": ""}]}
	for key: String in ["attack_hit:test", "spell_attack", "skill:perception", "save:wis", "initiative", "ability_mod:str"]:
		assert(Dice.applicable(record, key).size() == 1, "Any-d20 bonuses must remain available for d20 rolls")
	for key: String in ["attack_damage:test", "spell_damage"]:
		assert(Dice.applicable(record, key).is_empty(), "Any-d20 bonuses must never apply to damage")
	record.dice_bonuses[0].target = "damage_roll"
	assert(Dice.applicable(record, "attack_damage:test").size() == 1)
	assert(Dice.applicable(record, "spell_damage").size() == 1)
	assert(Dice.applicable(record, "attack_hit:test").is_empty())
	record.dice_bonuses[0].target = "attack_damage:test"
	assert(Dice.applicable(record, "attack_damage:test").size() == 1)
	assert(Dice.applicable(record, "spell_damage").is_empty())
	record.dice_bonuses = []
	# Process-local catalog fixture exercises real active-effect resolution.
	var id := "regression_any_d20"
	Content.home_entries("spells")
	var saved_home := Content._home.duplicate(true)
	Content._home[id] = {"category": "spells","id": id, "name": "D20 regression", "duration": "1 minute",
		"roll_bonus_targets": ["any_d20"], "consume_effect_on_roll": true}
	assert(Applied.apply(record, id, {"bonus_dice": "1d6", "caster_name": "Test"}))
	assert(Dice.applicable(record, "attack_hit:test").size() == 1)
	assert(Dice.applicable(record, "save:wis")[0].consumes_spell == id)
	assert(Dice.applicable(record, "attack_damage:test").is_empty()
		and Dice.applicable(record, "spell_damage").is_empty(),
		"Damage rolls must not offer or consume a d20-only spell effect")
	Content._home[id].roll_bonus_targets = ["any_d20", "damage_roll"]
	assert(Dice.applicable(record, "attack_damage:test").size() == 1,
		"An explicit damage scope still grants its damage bonus")
	Content._home = saved_home
	print("PASS: manual and active d20 bonus scopes exclude damage while explicit damage grants remain valid")
	quit()