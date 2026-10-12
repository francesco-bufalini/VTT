extends SceneTree

const Defenses = preload("res://vtt/creature_damage_defenses_tab.gd")
const Characters = preload("res://vtt/player_character_store.gd")
const Monsters = preload("res://vtt/master_creature_store.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var stat: Dictionary = {
		"name": "Defense Test", "source": "MM", "str": 10, "dex": 10,
		"resist": ["cold", {"resist": ["slashing"], "note": "only from nonmagical attacks"}],
		"immune": ["poison"], "conditionImmune": ["charmed"]
	}
	var monster: Dictionary = {
		"kind": "monster", "stat_block": stat, "damage_defense_overrides": {},
		"condition_immunity_overrides": {}
	}
	assert(Defenses.rank(monster, "cold") == 1
		and Defenses.rank(monster, "poison") == 2
		and Defenses.rank(monster, "slashing") == 0,
		"Unconditional bestiary resistance and immunity must resolve without promoting conditional damage rules")
	assert(Defenses.condition_immune(monster, "charmed")
		and not Defenses.condition_immune(monster, "stunned"),
		"Bestiary condition immunities must be displayed")
	var editor := Defenses.new()
	root.add_child(editor)
	var events: Array[Dictionary] = []
	editor.setup(func(damage: Dictionary, conditions: Dictionary) -> void:
		events.append({"damage": damage.duplicate(true), "conditions": conditions.duplicate(true)})
	)
	editor.load_record(monster)
	assert(editor._damage_buttons.size() == 13
		and editor._condition_buttons.size() == Defenses.CONDITIONS.size())
	var cold: Dictionary = editor._damage_buttons["cold"]
	(cold["immunity"] as CheckButton).button_pressed = true
	assert(events.size() == 1 and int(events[0].damage["cold"]) == 2
		and (cold["resistance"] as CheckButton).button_pressed,
		"Enabling immunity must automatically include resistance")
	(cold["immunity"] as CheckButton).button_pressed = false
	assert(events.size() == 2 and int(events[1].damage["cold"]) == 1,
		"Disabling immunity must leave the lower resistance rank, like Expertise")
	(cold["resistance"] as CheckButton).button_pressed = false
	assert(events.size() == 3 and int(events[2].damage["cold"]) == 0,
		"Disabling resistance must remove both defense grades")
	var poison: Dictionary = editor._damage_buttons["poison"]
	(poison["resistance"] as CheckButton).button_pressed = false
	assert(int(events.back().damage["poison"]) == 0,
		"Manual overrides must be allowed to disable bestiary immunity")
	var charmed: CheckButton = editor._condition_buttons["charmed"]
	charmed.button_pressed = false
	assert(not bool(events.back().conditions["charmed"]),
		"Manual condition-immunity overrides must allow switching off bestiary values")
	var normal: Dictionary = Characters.new().normalize_character({
		"id": "damage:test", "kind": "character", "damage_defense_overrides": events.back().damage,
		"condition_immunity_overrides": events.back().conditions
	})
	assert(Defenses.rank(normal, "cold") == 0
		and not Defenses.condition_immune(normal, "charmed"),
		"Damage and condition defense overrides must persist through character normalization")
	var monster_record: Dictionary = Monsters.new().create_creature(stat, "ally")
	monster_record["damage_defense_overrides"] = {"cold": 2}
	monster_record["condition_immunity_overrides"] = {"charmed": false}
	var normalized: Dictionary = Monsters.new().normalize_creature(monster_record)
	assert(Defenses.rank(normalized, "cold") == 2
		and not Defenses.condition_immune(normalized, "charmed"),
		"Damage and condition defense overrides must persist through monster normalization")
	editor.queue_free()
	await process_frame
	print("PASS: 5e damage-defense ranks, conditional defenses, condition immunity and persistence")
	quit()
