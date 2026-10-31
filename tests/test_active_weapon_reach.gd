extends SceneTree

const Attacks = preload("res://vtt/creature_attack_data.gd")
const Items = preload("res://vtt/creature_item_rules.gd")


func _initialize() -> void:
	call_deferred("_run")


func _weapon(id: String, name: String, reach: bool = false) -> Dictionary:
	return {
		"id": id, "name": name, "source": "PHB", "quantity": 1,
		"type": "M", "weapon_category": "martial",
		"damage": "1d8", "damage_type": "S",
		"properties": ["R"] if reach else [],
		"equipped_slots": []
	}


func _run() -> void:
	var sword: Dictionary = _weapon("test:sword", "Sword")
	var polearm: Dictionary = _weapon("test:polearm", "Polearm", true)
	var shield: Dictionary = {
		"id": "test:shield", "name": "Shield", "source": "PHB",
		"quantity": 1, "type": "S", "ac": 2, "equipped_slots": ["off"]
	}
	var record: Dictionary = {
		"kind": "character", "inventory": [sword, polearm, shield],
		"attack_overrides": {}, "abilities": {"str": 16, "dex": 12},
		"ability_bonuses": {}
	}
	assert(Attacks.equip_first_inventory_weapon(record))
	assert("main" in Items.slots(record.inventory[0]))
	assert("off" in Items.slots(record.inventory[2]), "One-handed default preserves shield")
	assert(Attacks.active_range(record) == 5.0)
	assert(not Attacks.equip_first_inventory_weapon(record), "Explicit equipment must be respected")

	var equipped: Array = record.inventory
	equipped[0]["equipped_slots"] = []
	equipped[1]["equipped_slots"] = ["main"]
	record["inventory"] = equipped
	record["equipped_attack_id"] = "item:test:polearm"
	assert(Attacks.active_range(record) == 10.0, "Map reach follows active weapon")
	record["attack_overrides"] = {"item:test:polearm": {"range_feet": 15}}
	assert(Attacks.active_range(record) == 15.0, "Per-attack reach overrides are respected")
	assert(Attacks.damage_expression(record, Attacks.active_attack(record)) == "1d8+3")
	equipped[1]["equipped_slots"] = []
	record["inventory"] = equipped
	assert(Attacks.active_attack(record).get("id") == "improvised", "Equipped shield remains a valid improvised attack after sheathing")
	record["hand_main_special"] = "unarmed"
	assert(Attacks.active_attack(record).get("id") == "unarmed", "Explicitly selected unarmed attacks remain available")

	var monster: Dictionary = {
		"kind": "monster", "inventory": [],
		"stat_block": {"action": [
			{"name": "Claw", "entries": ["{@atk mw} {@hit 5} reach 5 ft; {@damage 1d6 + 3} slashing damage."]},
			{"name": "Tail", "entries": ["{@atk mw} {@hit 7} reach 15 ft; {@damage 2d6 + 4} bludgeoning damage."]}
		]},
		"attack_overrides": {}
	}
	assert(Attacks.active_attack(monster).get("id") == "monster:action:0")
	assert(Attacks.active_range(monster) == 5.0)
	monster["equipped_attack_id"] = "monster:action:1"
	assert(Attacks.active_range(monster) == 15.0, "Monster may select natural attack reach")
	var tail: Dictionary = Attacks.active_attack(monster)
	assert(Attacks.damage_expression(monster, tail) == "2d6+4")
	monster["formula_bonuses"] = [{"id": "tail-damage", "target": "attack_damage:monster:action:1", "expression": "2", "origin_id": ""}]
	assert(Attacks.damage_expression(monster, tail) == "2d6+4+2", "Manual damage bonus must reach roller")
	print("PASS: first equip, sheathing, weapon selection, monster attack reach and dice expressions")
	quit()
