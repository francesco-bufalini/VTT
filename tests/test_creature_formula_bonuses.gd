extends SceneTree

const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Attacks = preload("res://vtt/creature_attack_data.gd")
const PlayerStore = preload("res://vtt/player_character_store.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var record: Dictionary = {
		"kind": "character", "level": 3, "classes": [],
		"abilities": {"str": 14, "dex": 12, "con": 10, "int": 10, "wis": 10, "cha": 10},
		"ability_bonuses": {},
		"armor_class_base": 12, "armor_class_bonus": 0,
		"speed_base": 30, "speed_bonus": 0,
		"max_hp_base": 18, "max_hp_bonus": 0,
		"initiative_bonus": 0, "proficiency_choices": [],
		"proficiency_origins": [], "formula_bonuses": []
	}
	assert(Bonuses.value(record, "ability:str") == 14)
	assert(Bonuses.value(record, "ability_mod:str") == 2)
	assert(Bonuses.value(record, "initiative") == 1)
	record["formula_bonuses"] = [
		{"id": "a", "target": "ability:str", "expression": "2"},
		{"id": "b", "target": "ability:str", "expression": "1"},
		{"id": "c", "target": "ability_mod:str", "expression": "1"},
		{"id": "d", "target": "initiative", "expression": "str_mod"},
		{"id": "e", "target": "skill:perception", "expression": "wis_mod + 3"},
		{"id": "f", "target": "passive_perception", "expression": "skill_perception / 3"}
	]
	assert(Bonuses.value(record, "ability:str") == 17, "Bonuses from distinct origins must stack")
	assert(Bonuses.value(record, "ability_mod:str") == 4, "Modifier derives from effective score, then takes its own bonuses")
	assert(Bonuses.value(record, "initiative") == 5, "A grant may reference another computed modifier")
	assert(Bonuses.value(record, "passive_perception") == 14,
		"Passive perception uses effective skill and its own bonus")
	(record["formula_bonuses"] as Array).append({
		"id": "cycle", "target": "ability:str", "expression": "str_mod"
	})
	assert(Bonuses.value(record, "ability:str") == 17,
		"Circular grants must be ignored rather than recursing indefinitely")
	assert("Dipendenza circolare" in Bonuses.description(record, "ability:str"))
	(record["formula_bonuses"] as Array).append({
		"id": "dice", "target": "speed", "expression": "1d8"
	})
	assert(Bonuses.value(record, "speed") == 30, "Dice expressions are invalid for static bonuses")
	(record["formula_bonuses"] as Array).append({
		"id": "disabled", "target": "ac", "expression": "5",
		"origin_id": "custom|inactive", "origin_name": "Inactive"
	})
	record["proficiency_origins"] = [
		{"id": "custom|inactive", "name": "Inactive", "group": "custom", "disabled": true}
	]
	assert(Bonuses.value(record, "ac") == 12, "Disabled sources must not contribute")
	(record["formula_bonuses"] as Array).append({
		"id": "item", "target": "ac", "expression": "2",
		"origin_id": "item:magic_shield", "origin_name": "Magic shield"
	})
	assert(Bonuses.value(record, "ac") == 12, "Withdrawn items must not grant bonuses")
	record["inventory"] = [{"id": "magic_shield", "name": "Magic shield"}]
	assert(Bonuses.value(record, "ac") == 14, "A live item source activates its bonus")
	record["inventory"] = []
	assert(Bonuses.value(record, "ac") == 12, "Removing an item revokes only its own bonus")
	var migrated: Dictionary = record.duplicate(true)
	migrated["formula_bonuses"] = []
	migrated["ability_bonuses"] = {"str": 2}
	migrated["initiative_bonus"] = 3
	migrated["spell_slots_bonus"] = [0, 1, 0, 0, 0, 0, 0, 0, 0, 0]
	migrated["attack_overrides"] = {"test": {"bonus": 2, "range_bonus": 10}}
	Bonuses.migrate_legacy(migrated)
	assert(Bonuses.value(migrated, "ability:str") == 16)
	assert(Bonuses.value(migrated, "initiative") == 4)
	assert(Bonuses.add(migrated, "slot:1", 2) == 3)
	assert(Attacks.range_for(migrated, {"id": "test", "range_feet": 30}) == 40)
	var saved: String = JSON.stringify(migrated)
	var restored: Dictionary = JSON.parse_string(saved)
	Bonuses.migrate_legacy(restored)
	assert(Bonuses.value(restored, "initiative") == 4 and Bonuses.grants(restored).size() == Bonuses.grants(migrated).size(),
		"Migrated records must round-trip without duplicate grants")
	var store := PlayerStore.new()
	var normalized: Dictionary = store.normalize_character(migrated)
	assert(Bonuses.value(normalized, "ability:str") == 16)
	assert(Bonuses.add(normalized, "slot:1", 2) == 3)
	print("PASS: additive bonuses, dynamic references, provenance, cycles, migration and persistence")
	quit()
