extends SceneTree

const ItemRules = preload("res://vtt/creature_item_rules.gd")
const AttackData = preload("res://vtt/creature_attack_data.gd")
const PlayerStore = preload("res://vtt/player_character_store.gd")
const InventoryTab = preload("res://vtt/creature_inventory_tab.gd")


func _initialize() -> void:
	call_deferred("run")


func _item(id: String, name: String, type_code: String, damage: String, properties: Array, range_text: String = "") -> Dictionary:
	return {
		"id": id, "name": name, "source": "PHB", "quantity": 1,
		"type": type_code, "weapon_category": "martial",
		"damage": damage, "damage_type": "P",
		"properties": properties, "range": range_text,
		"versatile_damage": "", "equipped_slots": []
	}


func _record(inventory: Array) -> Dictionary:
	return {
		"kind": "character", "attack_ability": "dex",
		"abilities": {"str": 12, "dex": 18},
		"ability_bonuses": {"str": 0, "dex": 0},
		"attack_overrides": {},
		"inventory": inventory
	}


func _attack(attacks: Array[Dictionary], id: String) -> Dictionary:
	for attack: Dictionary in attacks:
		if String(attack.get("id", "")) == id:
			return attack
	return {}


func run() -> void:
	var rapier := _item("test:rapier", "Rapier", "M", "1d8", ["F"])
	var shield := {"id": "test:shield", "name": "Shield", "source": "PHB", "quantity": 1, "type": "S", "ac": 2, "equipped_slots": ["off"]}
	rapier["equipped_slots"] = ["main"]
	var record := _record([rapier, shield])
	var attacks: Array[Dictionary] = AttackData.definitions(record)
	var weapon := _attack(attacks, "item:test:rapier")
	assert(not weapon.is_empty() and weapon.range_feet == 5)
	assert(AttackData.attack_bonus(record, weapon, 2) == 4)
	assert("1d8 +4" in AttackData.damage_label(record, weapon))
	assert(ItemRules.shield_bonus(record.inventory) == 2)
	record["attack_ability"] = "str"
	assert(AttackData.attack_bonus(record, weapon, 2) == 1, "Finesse respects the preferred STR/DEX ability")
	record["attack_ability"] = "dex"
	record["attack_overrides"] = {"item:test:rapier": {"proficient": true, "bonus": 1}}
	assert(AttackData.attack_bonus(record, weapon, 2) == 7, "Proficiency and manual bonus apply only once")
	var normalized: Dictionary = PlayerStore.new().normalize_character({
		"inventory": [rapier, shield], "armor_class_base": 12, "armor_class_bonus": 1
	})
	assert(normalized.armor_class == 15 and normalized.armor_class_base == 12, "Equipped shield adds AC without altering manual base")

	var glaive := _item("test:glaive", "Glaive", "M", "1d10", ["R", "2H", "H"])
	glaive["equipped_slots"] = ["main"]
	record = _record([glaive])
	attacks = AttackData.definitions(record)
	weapon = _attack(attacks, "item:test:glaive")
	assert(weapon.range_feet == 10 and AttackData.first_melee_range(record) == 10.0, "Reach is tied to equipped melee weapon")
	assert(AttackData.attack_bonus(record, weapon, 2) == 1, "Non-finesse melee weapons cannot use preferred DEX")
	assert(not ItemRules.valid_slot(glaive, "off"), "Two-handed weapons cannot occupy the secondary hand")

	var bow := _item("test:longbow", "Longbow", "R", "1d8", ["A", "2H"], "150/600")
	bow["equipped_slots"] = ["main"]
	record = _record([bow])
	attacks = AttackData.definitions(record)
	weapon = _attack(attacks, "item:test:longbow")
	assert(not weapon.melee and weapon.range_feet == 150 and weapon.long_range_feet == 600)
	assert(AttackData.attack_bonus(record, weapon, 2) == 4, "Ranged weapons use DEX regardless of finesse")

	var dagger := _item("test:dagger", "Dagger", "M", "1d4", ["F", "T", "L"], "20/60")
	dagger["equipped_slots"] = ["main"]
	record = _record([dagger])
	attacks = AttackData.definitions(record)
	assert(_attack(attacks, "item:test:dagger").range_feet == 5)
	var thrown := _attack(attacks, "item:throw:main:test:dagger")
	assert(not thrown.is_empty() and thrown.range_feet == 20 and thrown.long_range_feet == 60)
	assert(AttackData.attack_bonus(record, thrown, 2) == 4, "Thrown finesse melee weapons keep their preferred DEX")

	var sword := _item("test:longsword", "Longsword", "M", "1d8", ["V"])
	sword["versatile_damage"] = "1d10"
	sword["equipped_slots"] = ["main"]
	record = _record([sword])
	weapon = _attack(AttackData.definitions(record), "item:test:longsword")
	assert("1d8" in AttackData.damage_label(record, weapon))
	record["attack_overrides"] = {"item:test:longsword": {"two_handed": true}}
	assert("1d10" in AttackData.damage_label(record, weapon))
	record["inventory"].append(shield)
	assert("1d8" in AttackData.damage_label(record, weapon), "Versatile two-handed grip requires a free secondary hand")

	# Equipping is persisted on inventory rows; two copies may fill both hands.
	var tab := InventoryTab.new()
	root.add_child(tab)
	var events: Array = []
	tab.setup(func(items: Array) -> void: events.append(items.duplicate(true)), Callable())
	var paired := rapier.duplicate(true)
	paired["quantity"] = 2
	paired["equipped_slots"] = []
	var glaive_clean := glaive.duplicate(true)
	glaive_clean["equipped_slots"] = []
	tab.load_record({"inventory": [paired, shield, glaive_clean]})
	tab._inventory_list.select(0)
	tab._equip_selected("main")
	tab._inventory_list.select(0)
	tab._equip_selected("off")
	assert(ItemRules.slots(events.back()[0]).size() == 2, "Two owned copies can be equipped in both hands")
	tab._inventory_list.select(1)
	tab._equip_selected("off")
	assert("off" in ItemRules.slots(events.back()[1]), "A shield is allowed in the secondary hand")
	tab._inventory_list.select(2)
	tab._equip_selected("main")
	assert("main" in ItemRules.slots(events.back()[2]))
	assert(ItemRules.occupying(events.back(), "off").is_empty(), "Two-handed main weapon clears secondary hand")
	tab.queue_free()
	await process_frame
	print("PASS: 2014 structured item properties, equipped hands, shield AC, attack ability, reach, ranged and versatile damage")
	quit()
