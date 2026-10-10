extends SceneTree

const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Items = preload("res://vtt/creature_item_rules.gd")
const Attacks = preload("res://vtt/creature_attack_data.gd")


func _initialize() -> void:
	call_deferred("run")


func _owned(id: String, name: String, type_code: String, slot: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"id": id, "name": name, "type": type_code, "source": "Test",
		"quantity": 1, "equipped_slots": [slot] if not slot.is_empty() else [],
		"active": true, "attuned": false
	}
	result.merge(extra, true)
	return result


func run() -> void:
	# Use unique identifiers not in the core catalog; entry_for() falls back
	# to saved snapshots, exactly as it does for an offline/homebrew item.
	var armor: Dictionary = _owned("test:armor:medium", "Armatura test", "MA", "body", {"ac": 15, "bonus_ac": 2})
	var shield: Dictionary = _owned("test:shield", "Scudo test", "S", "off", {"ac": 2, "bonus_ac": 1})
	var weapon: Dictionary = _owned("test:weapon", "Spada test", "M", "main", {
		"damage": "1d8", "weapon_category": "martial", "bonus_weapon": 2
	})
	var ring: Dictionary = _owned("test:ring", "Anello test", "RG", "", {
		"bonus_saving_throw": 1, "req_attune": true
	})
	var character: Dictionary = {
		"kind": "character", "level": 3, "abilities": {
			"str": 14, "dex": 18, "con": 10, "int": 10, "wis": 10, "cha": 10
		},
		"armor_class_base": 12, "armor_class_bonus": 0,
		"initiative_bonus": 0, "formula_bonuses": [],
		"proficiency_choices": [], "proficiency_origins": [],
		"inventory": [armor, shield, weapon, ring]
	}
	assert(Items.equipped_armor(character.inventory).get("id", "") == "test:armor:medium")
	assert(Items.shield_bonus(character.inventory) == 2, "Base shield AC must exclude magic enhancement")
	assert(Bonuses.value(character, "ac") == 22,
		"Medium armor 15 + capped DEX 2 + shield 2 + two item magic enhancements (2 + 1)")
	var found_auto := false
	for grant: Dictionary in Bonuses.grants(character):
		if String(grant.get("id", "")) == "auto|item:test:shield|bonus_ac|ac":
			found_auto = true
			assert(bool(grant.get("automatic", false)))
	assert(found_auto, "Structured source must appear as a distinct UI grant")
	var attack: Dictionary = {}
	for row: Dictionary in Attacks.definitions(character):
		if String(row.get("id", "")) == "item:test:weapon":
			attack = row
	assert(not attack.is_empty())
	assert(Attacks.attack_bonus(character, attack, 2) == 4,
		"Magic weapon +2 must be counted exactly once, not both directly and through bonuses")
	assert("+4" in Attacks.damage_label(character, attack),
		"Magic damage is included as a target-specific origin grant")
	assert(Bonuses.value(character, "save:wis") == 0,
		"Unattuned items do not confer their structured bonuses")
	(character.inventory[3] as Dictionary)["attuned"] = true
	assert(Bonuses.value(character, "save:wis") == 1)
	character.formula_bonuses = [{
		"id": "auto|item:test:shield|bonus_ac|ac",
		"origin_id": "item:test:shield", "target": "ac", "expression": "1",
		"automatic": true, "disabled": true
	}]
	assert(Bonuses.value(character, "ac") == 21,
		"Disabling an automatic row must preserve the other grants")
	(character.inventory[0] as Dictionary)["equipped_slots"] = []
	assert(Bonuses.value(character, "ac") == 14,
		"Unequipping armor restores the manual AC base and withdraws its magic")
	(character.inventory[2] as Dictionary)["equipped_slots"] = []
	assert(Bonuses.bonus(character, "attack_hit:item:test:weapon") == 0,
		"Sheathed weapon enhancements must not remain active")
	(character.inventory[3] as Dictionary)["active"] = false
	assert(Bonuses.value(character, "save:wis") == 0,
		"Disabled item effects withdraw immediately")
	# Two independently named manual grants of the same amount both survive.
	character.formula_bonuses = [
		{"id": "first", "target": "ac", "expression": "2", "origin_name": "A"},
		{"id": "second", "target": "ac", "expression": "2", "origin_name": "B"}
	]
	assert(Bonuses.bonus(character, "ac") == 5,
		"Two independent +2 AC grants stack alongside the +1 shield enhancement")
	character.inventory = []
	assert(Bonuses.value(character, "ac") == 16)
	assert(Bonuses.grants(character).size() == 2,
		"Withdrawing items removes automatic grants, not unrelated manual grants")
	# 5etools reqAttune is bool OR a qualifying String (e.g. "by a
	# spellcaster"). Comparing the two variant types must never throw.
	var conditional_ring := _owned("test:string-attunement", "Anello riservato", "RG", "", {
		"bonus_saving_throw": 2, "reqAttune": "by a spellcaster"
	})
	character.inventory = [conditional_ring]
	assert(Bonuses.value(character, "save:wis") == 0,
		"String attunement requirements must suppress bonuses before attunement")
	(character.inventory[0] as Dictionary)["attuned"] = true
	assert(Bonuses.value(character, "save:wis") == 2,
		"Attuning an item with a string requirement must enable its bonus")
	(character.inventory[0] as Dictionary)["reqAttune"] = ""
	(character.inventory[0] as Dictionary)["attuned"] = false
	assert(Bonuses.value(character, "save:wis") == 2,
		"An empty attunement string must not require attunement")
	(character.inventory[0] as Dictionary)["reqAttune"] = false
	assert(Bonuses.value(character, "save:wis") == 2,
		"A boolean false requirement must not require attunement")
	(character.inventory[0] as Dictionary)["reqAttune"] = true
	assert(Bonuses.value(character, "save:wis") == 0,
		"A boolean true requirement must still require attunement")
	print("PASS: structured item bonuses, equipped armor AC, attunement, provenance and stacking")
	quit()
