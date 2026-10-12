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
	var fallback_record := _record([])
	var fallback_attacks: Array[Dictionary] = AttackData.definitions(fallback_record)
	var unarmed := _attack(fallback_attacks, "unarmed")
	var improvised := _attack(fallback_attacks, "improvised")
	assert(not unarmed.is_empty() and not improvised.is_empty(), "Both fallback attacks exist for characters")
	assert(unarmed.proficient and not improvised.proficient, "Only unarmed strikes are automatically proficient")
	assert(AttackData.attack_bonus(fallback_record, improvised, 2) == 1
		and AttackData.damage_label(fallback_record, improvised) == "1d4 +1 contundenti",
		"Improvised weapons use STR and base d4 damage without automatic proficiency")
	assert(not ItemRules.has_equipped_weapon([]), "No equipment must allow fallback attacks")
	assert(not ItemRules.has_equipped_weapon([shield]), "A shield is not an equipped weapon")
	var stowed_rapier := rapier.duplicate(true)
	stowed_rapier["equipped_slots"] = []
	assert(not ItemRules.has_equipped_weapon([stowed_rapier, shield]),
		"Owning a weapon without equipping it does not hide fallback attacks")
	assert(ItemRules.has_equipped_weapon([rapier, shield]), "An equipped melee weapon is detected even when fallback attacks stay selectable")
	var fallback_with_weapon: Dictionary = fallback_record.duplicate(true)
	fallback_with_weapon["inventory"] = [rapier, shield]
	fallback_with_weapon["equipped_attack_id"] = "unarmed"
	assert(AttackData.active_attack(fallback_with_weapon).get("id", "") == "unarmed",
		"Selecting an unarmed attack must work even while holding a weapon")
	fallback_with_weapon["equipped_attack_id"] = "improvised"
	assert(AttackData.active_attack(fallback_with_weapon).get("id", "") == "improvised",
		"Improvised weapons remain selectable even while a weapon is equipped")
	fallback_with_weapon["kind"] = "monster"
	assert(AttackData.definitions(fallback_with_weapon).all(func(attack: Dictionary) -> bool:
		return String(attack.get("id", "")) not in ["unarmed", "improvised"]),
		"Bestiary creatures must not receive the player-only fallback attacks")
	var offhand_rapier := rapier.duplicate(true)
	offhand_rapier["equipped_slots"] = ["off"]
	assert(ItemRules.has_equipped_weapon([offhand_rapier]), "An offhand weapon counts too")
	var record := _record([rapier, shield])
	var attacks: Array[Dictionary] = AttackData.definitions(record)
	var weapon := _attack(attacks, "item:test:rapier")
	assert(not weapon.is_empty() and weapon.range_feet == 5)
	assert(AttackData.attack_bonus(record, weapon, 2) == 4)
	assert("1d8 +4" in AttackData.damage_label(record, weapon))
	assert(ItemRules.shield_bonus(record.inventory) == 2)
	# The weapon's effective size follows its wielder unless explicitly
	# overridden, including for Tiny/Small (standard catalog damage).
	var big_record := _record([rapier])
	big_record["size_name"] = "Large"
	var big_attack := _attack(AttackData.definitions(big_record), "item:test:rapier")
	assert(big_attack.weapon_size == "Large")
	assert(AttackData.damage_label(big_record, big_attack).begins_with("1d8 + 1d8 +4"))
	assert(AttackData.damage_expression(big_record, big_attack) == "1d8+1d8+4")
	assert(ItemRules.weapon_dice_multiplier("Huge") == 3
		and ItemRules.weapon_dice_multiplier("Gargantuan") == 4)
	big_record["size_name"] = "Tiny"
	big_attack = _attack(AttackData.definitions(big_record), "item:test:rapier")
	assert(AttackData.damage_label(big_record, big_attack).begins_with("1d8 +4"))
	var oversized := rapier.duplicate(true)
	oversized["instance_overrides"] = {"weapon_size": "Huge"}
	big_record["inventory"] = [oversized]
	big_attack = _attack(AttackData.definitions(big_record), "item:test:rapier")
	assert(big_attack.weapon_size == "Huge"
		and AttackData.damage_label(big_record, big_attack).begins_with("1d8 + 2d8 +4"))
	assert(AttackData.damage_expression(big_record, big_attack) == "1d8+2d8+4")
	assert(AttackData.weapon_size_dice("2d6 + 1d4", "Large") == "2d6 + 2d6 + 1d4",
		"Only the first weapon dice pool, not additional damage riders, scales with size")

	record["attack_ability"] = "str"
	assert(AttackData.attack_bonus(record, weapon, 2) == 1, "Finesse respects the preferred STR/DEX ability")
	record["attack_ability"] = "dex"
	record["formula_bonuses"] = [{"id": "hit-bonus", "target": "attack_hit:item:test:rapier", "expression": "1", "origin_id": ""}]
	record["proficiency_choices"] = [{"kind": "weapon", "key": "martial", "origin_id": "class|phb|fighter"}]
	assert(AttackData.attack_bonus(record, weapon, 2) == 7, "Shared martial proficiency and an originless bonus apply only once")
	var normalized: Dictionary = PlayerStore.new().normalize_character({
		"inventory": [rapier, shield], "armor_class_base": 12,
		"formula_bonuses": [{"id": "ac-bonus", "target": "ac", "expression": "1", "origin_id": ""}]
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
	# The inventory checkbox is independent of hand/body slots.
	var trinket := {"id": "test:trinket", "name": "Trinket", "quantity": 1, "type": "G",
		"equipped": false, "equipped_slots": []}
	assert(not ItemRules.origin_active(trinket), "An owned generic item is not equipped by default")
	trinket["equipped"] = true
	assert(ItemRules.origin_active(trinket), "Generic equipment has no slot limit")

	# Natural AC is an expression; empty hands still use ordinary DEX.
	var store := PlayerStore.new()
	var natural := store.normalize_character({
		"id": "test:natural", "kind": "character",
		"abilities": {"str": 10, "dex": 18, "con": 10, "int": 10, "wis": 10, "cha": 10},
		"inventory": []
	})
	assert(natural.get("armor_natural_formula", "") == "10 + dex_mod"
		and natural.armor_class == 14, "The default unarmored formula is 10 + DEX")
	natural["armor_natural_formula"] = "13 + dex_mod"
	assert(store.normalize_character(natural).armor_class == 17,
		"Custom unarmored formulas must be persisted and evaluated")
	var main_shield := shield.duplicate(true)
	main_shield["equipped_slots"] = ["main"]
	assert(ItemRules.valid_slot(main_shield, "main")
		and ItemRules.shield_bonus([main_shield]) == 2,
		"A shield may be chosen in either hand")
	assert(ItemRules.shield_bonus([main_shield, shield]) == 2,
		"Two shields cannot stack their base AC benefits")

	# Finesse is only a display filter; the 2014 offhand rule requires Light.
	var first_dagger := _item("test:first_dagger", "First dagger", "M", "1d4", ["L", "F"])
	first_dagger["equipped_slots"] = ["main"]
	var second_dagger := _item("test:second_dagger", "Second dagger", "M", "1d4", ["L", "F"])
	second_dagger["equipped_slots"] = ["off"]
	var dual := _record([first_dagger, second_dagger])
	var second_attack := _attack(AttackData.definitions(dual), "item:off:test:second_dagger")
	assert(AttackData.offhand_bonus_attack_allowed(dual))
	assert(AttackData.attack_bonus(dual, second_attack, 2) == 4,
		"Offhand attack rolls retain the full ability modifier")
	assert(not "+4" in AttackData.damage_label(dual, second_attack),
		"Offhand bonus action damage omits positive DEX without the fighting style")
	dual["fighting_styles"] = ["Two-Weapon Fighting"]
	assert("+4" in AttackData.damage_label(dual, second_attack),
		"Selected structured Two-Weapon Fighting style restores offhand ability damage")
	dual["fighting_styles"] = []
	first_dagger["properties"] = ["F"]
	second_dagger["properties"] = ["F"]
	dual["inventory"] = [first_dagger, second_dagger]
	assert(not AttackData.offhand_bonus_attack_allowed(dual),
		"Finesse without Light does not grant the bonus-action attack")
	dual["feats_catalog"] = [{"name": "Dual Wielder", "source": "PHB"}]
	assert(AttackData.offhand_bonus_attack_allowed(dual),
		"Dual Wielder overrides the 2014 Light requirement")
	# Explicit grip selection takes precedence over a legacy per-attack toggle.
	var versatile_record := _record([sword])
	versatile_record["hand_grip_two_handed"] = true
	assert("1d10" in AttackData.damage_label(versatile_record,
		_attack(AttackData.definitions(versatile_record), "item:test:longsword")),
		"Two-hand versatile grip uses its dedicated damage dice")

	tab.queue_free()
	await process_frame
	print("PASS: equipment, natural AC, both shields, dual wield damage, light/style/feat and versatile grip")
	quit()
