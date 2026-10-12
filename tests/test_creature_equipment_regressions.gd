extends SceneTree

const Items = preload("res://vtt/creature_item_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Instances = preload("res://vtt/item_instance.gd")
const InventoryTab = preload("res://vtt/creature_inventory_tab.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var plate := {"id": "regression:plate", "name": "Plate", "type": "HA", "ac": 18, "quantity": 1, "equipped_slots": ["body"]}
	var record := {
		"kind": "character", "level": 1, "classes": [], "armor_class_base": 10,
		"abilities": {"str": 10, "dex": 6, "con": 10, "int": 10, "wis": 10, "cha": 10},
		"inventory": [plate], "formula_bonuses": [], "proficiency_origins": [], "proficiency_choices": []
	}
	for dexterity: int in [6, 10, 18]:
		record.abilities.dex = dexterity
		assert(Bonuses.value(record, "ac") == 18, "Heavy armor must ignore positive and negative DEX")
	record.abilities.dex = 6
	record.formula_bonuses = [{"id": "dex-from-ac", "target": "ability:dex", "expression": "ac / 6"}]
	assert(Bonuses.value(record, "ability:dex") == 9 and Bonuses.value(record, "ac") == 18,
		"Flat heavy armor AC must not introduce a false DEX dependency cycle")
	record.formula_bonuses = []
	plate.dexterity_max = 0
	assert(Bonuses.value(record, "ac") == 18, "An explicit zero cap still means no heavy-armor DEX penalty")
	plate.dexterity_max = 2
	assert(Bonuses.value(record, "ac") == 16, "Custom heavy armor can explicitly opt into DEX")
	record.abilities.dex = 18
	assert(Bonuses.value(record, "ac") == 20)
	plate.erase("dexterity_max")
	plate.type = "MA"
	plate.ac = 15
	assert(Bonuses.value(record, "ac") == 17)
	record.abilities.dex = 6
	assert(Bonuses.value(record, "ac") == 13, "Medium armor must retain negative DEX modifiers")
	plate.type = "LA"
	plate.ac = 11
	assert(Bonuses.value(record, "ac") == 9, "Light armor must retain negative DEX modifiers")

	# Unknown IDs exercise the exact offline fallback used by catalog gaps.
	var definition := {"id": "regression:offline:ring", "name": "Offline ring", "type": "RG", "source": "Test",
		"bonusSavingThrow": 2, "bonusSpellSaveDc": 1, "bonusAbility": {"int": 1}, "reqAttune": "by a spellcaster"}
	var owned := Instances.from_catalog(definition)
	owned.attuned = true
	owned.equipped = true
	owned.bonusAbility.int = 2
	assert(definition.bonusAbility.int == 1, "Owned snapshots must not mutate catalog dictionaries")
	var restored := Instances.from_saved(JSON.parse_string(JSON.stringify(owned)))
	record.inventory = [restored]
	assert(Bonuses.bonus(record, "save:wis") == 2 and Bonuses.bonus(record, "spell_dc") == 1,
		"Offline magic metadata must survive both item creation and save normalization")
	assert(Bonuses.value(record, "ability:int") == 12)
	restored.attuned = false
	assert(Bonuses.bonus(record, "save:wis") == 0, "Attunement requirement must survive the same round-trip")
	restored.attuned = true
	restored.active = false
	assert(Bonuses.bonus(record, "save:wis") == 0)
	var snake := {"id": "regression:offline:weapon", "name": "Magic blade", "type": "M", "damage": "1d8",
		"bonus_weapon_attack": 1, "bonus_weapon_damage": 3, "bonus_spell_attack": 2, "bonus_ability_check": 1,
		"bonus_saving_throw_concentration": 2, "bonus_proficiency_bonus": 1, "req_attune": false}
	var blade := Instances.from_saved(Instances.from_catalog(snake))
	blade.equipped_slots = ["main"]
	record.inventory = [blade]
	assert(Bonuses.bonus(record, "attack_hit:item:regression:offline:weapon") == 1)
	assert(Bonuses.bonus(record, "attack_damage:item:regression:offline:weapon") == 3)
	assert(Bonuses.bonus(record, "spell_attack") == 2 and Bonuses.bonus(record, "skill:perception") == 1)
	assert(Bonuses.bonus(record, "save_concentration") == 2 and Bonuses.value(record, "proficiency") == 3)
	assert(Items.valid_slot(blade, "main") and Items.valid_slot(blade, "off"))
	assert(not Items.valid_slot(blade, "body") and not Items.valid_slot(blade, "unknown"),
		"One-handed weapons can occupy only hand slots")
	var two_handed := blade.duplicate(true)
	two_handed.properties = ["2H"]
	assert(Items.valid_slot(two_handed, "main") and not Items.valid_slot(two_handed, "off"))

	# Exercise the real inventory button and reject a direct invalid action.
	var tab := InventoryTab.new()
	root.add_child(tab)
	var changes: Array = []
	tab.setup(func(items: Array) -> void: changes.append(items.duplicate(true)), Callable())
	tab.load_record({"inventory": [blade, plate]})
	tab._inventory_list.select(0)
	tab._inventory_list.item_selected.emit(0)
	assert(tab._equip_armor.disabled and not tab._equip_main.disabled)
	tab._equip_selected("body")
	assert(changes.is_empty() and "body" in Items.slots(tab._inventory[1]),
		"Trying to wear a weapon must not displace the equipped armor")
	tab.queue_free()
	await process_frame
	await process_frame
	print("PASS: heavy armor DEX, acyclic formulas, offline magic persistence and valid inventory slots")
	quit()