extends SceneTree
const Actions = preload("res://vtt/creature_action_economy_tab.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for pair: Array in [[5, 2], [11, 3], [20, 4]]:
		var record := {"kind": "character", "rules_version": "2014", "classes": [{"name": "Fighter", "source": "PHB", "level": pair[0]}, {"name": "Barbarian", "source": "PHB", "level": 5}]}
		assert(Actions.attack_action_summary(record).count == pair[1])
	var monster := {"kind": "monster", "stat_block": {"action": [{"name": "Multiattack", "entries": ["The beast makes three attacks."]}]}}
	var found := false
	for row: Dictionary in Actions.entries(monster):
		assert(row.get("name", "") != "Multiattack")
		if row.get("id", "") == "attack":
			assert(row.attack_count == 3 and "three attacks" in row.detail)
			found = true
	assert(found)
	monster.stat_block.action[0].entries = ["The dragon can use its Frightful Presence. It then makes three attacks: one with its bite and two with its claws."]
	assert(Actions.attack_action_summary(monster).count == 4, "The displayed routine includes the special use plus three attacks")
	monster.stat_block.action[0].attacks_per_action = 4
	assert(Actions.attack_action_summary(monster).count == 4, "Explicit structured count takes precedence")
	print("PASS: Extra Attack uses class levels without stacking; Multiattack belongs to Attack with source tooltip")
	quit()
