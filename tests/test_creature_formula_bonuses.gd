extends SceneTree

const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Attacks = preload("res://vtt/creature_attack_data.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var record: Dictionary = {
		"kind": "character", "level": 3, "classes": [],
		"abilities": {"str": 14, "dex": 12, "con": 10, "int": 10, "wis": 10, "cha": 10},
		"armor_class_base": 12,
		"speed_base": 30,
		"max_hp_base": 18,
		"proficiency_choices": [],
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

	# A dependency chain must use the *effective* (bonused) source score.
	var cascade: Dictionary = record.duplicate(true)
	cascade["formula_bonuses"] = [
		{"id": "strength", "target": "ability:str", "expression": "2"},
		{"id": "dexterity", "target": "ability:dex", "expression": "str_mod"},
		{"id": "initiative", "target": "initiative", "expression": "str_mod"}
	]
	assert(Bonuses.value(cascade, "ability:str") == 16)
	assert(Bonuses.value(cascade, "ability:dex") == 15,
		"Dependent ability must use the effective STR modifier")
	assert(Bonuses.value(cascade, "initiative") == 5,
		"Initiative must use the new DEX modifier and the STR-based grant")

	# Reject both directions of a mutual cycle, regardless of query order,
	# without suppressing an unrelated additive bonus on the same target.
	var mutual: Dictionary = record.duplicate(true)
	mutual["formula_bonuses"] = [
		{"id": "fixed", "target": "ability:str", "expression": "2"},
		{"id": "str-from-dex", "target": "ability:str", "expression": "dex_mod"},
		{"id": "dex-from-str", "target": "ability:dex", "expression": "str_mod"}
	]
	assert(Bonuses.value(mutual, "ability:dex") == 12)
	assert(Bonuses.value(mutual, "ability:str") == 16)
	assert(Bonuses.value(mutual, "ability:dex") == 12,
		"Cyclic scores must be independent of evaluation order")
	assert("Dipendenza circolare" in Bonuses.description(mutual, "ability:str"))
	assert("Dipendenza circolare" in Bonuses.description(mutual, "ability:dex"))

	var self_reference: Dictionary = record.duplicate(true)
	self_reference["formula_bonuses"] = [
		{"id": "self", "target": "ability:str", "expression": "str_score + 1"},
		{"id": "save-cycle", "target": "ability:wis", "expression": "skill_perception"}
	]
	assert(Bonuses.value(self_reference, "ability:str") == 14)
	assert(Bonuses.value(self_reference, "ability:wis") == 10,
		"Implicit skill-to-ability feedback must also be rejected")
	(self_reference["formula_bonuses"] as Array)[1]["disabled"] = true
	assert(Bonuses.value(self_reference, "ability:wis") == 10)

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
	record["inventory"] = [{"id": "magic_shield", "name": "Magic shield", "quantity": 1, "equipped": true}]
	assert(Bonuses.value(record, "ac") == 14, "A live item source activates its bonus")
	record["inventory"] = []
	assert(Bonuses.value(record, "ac") == 12, "Removing an item revokes only its own bonus")
	# Bonuses without an origin are first-class, additive grants.
	var originless: Dictionary = record.duplicate(true)
	originless["formula_bonuses"] = [
		{"id": "free-1", "target": "ability:str", "expression": "2", "origin_id": "", "disabled": false},
		{"id": "free-2", "target": "ability:str", "expression": "2", "origin_id": "", "disabled": false}
	]
	assert(Bonuses.value(originless, "ability:str") == 18,
		"Two originless bonuses must accumulate like other grants")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(originless))
	var normalized: Dictionary = restored
	assert(Bonuses.value(normalized, "ability:str") == 18,
		"Saving and loading must preserve originless grants")
	var originless_count: int = 0
	for grant: Dictionary in Bonuses.grants(normalized):
		if String(grant.get("origin_id", "")) == "" and String(grant.get("target", "")) == "ability:str":
			originless_count += 1
	assert(originless_count == 2, "Originless grants must not be deduplicated")
	(normalized["formula_bonuses"] as Array)[0]["disabled"] = true
	assert(Bonuses.value(normalized, "ability:str") == 16,
		"Each originless bonus must remain independently toggleable")
	# Spent pact slots must be capped by the effective (grant-adjusted) maximum.
	var pact: Dictionary = {"kind": "character", "classes": [], "abilities": {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10}}
	pact["pact_slots_total"] = 1
	pact["pact_slots_spent"] = 3
	pact["formula_bonuses"] = [
		{"id": "pact-extra", "target": "pact_slot", "expression": "2", "origin_id": ""}
	]
	assert(pact["pact_slots_spent"] == 3 and Bonuses.add(pact, "pact_slot", 1) == 3,
		"Pact slot bonuses must retain their independently spent amounts")
	print("PASS: additive bonuses, dynamic references, originless grants, cycles and persistence")
	quit()
