extends SceneTree

const Infusions = preload("res://vtt/creature_infusions.gd")
const Items = preload("res://vtt/creature_item_rules.gd")
const Instances = preload("res://vtt/item_instance.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const InventoryTab = preload("res://vtt/creature_inventory_tab.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var option: Dictionary = {}
	var replicate: Dictionary = {}
	for entry: Dictionary in Infusions.catalog():
		if entry.get("name", "") == "Enhanced Defense":
			option = entry
		if entry.get("name", "") == "Replicate Magic Item":
			replicate = entry
	assert(Infusions.catalog().size() == 16 and not option.is_empty() and not replicate.is_empty())

	var armor := {
		"id": "test:armor", "name": "Chain Shirt", "type": "MA", "ac": 13,
		"quantity": 1, "rarity": "none", "equipped_slots": ["body"],
		"equipped": true, "attuned": false, "active": true
	}
	var record: Dictionary = {
		"id": "test:artificer", "class": "Artificer", "class_source": "TCE", "level": 2,
		"classes": [{"name": "Artificer", "source": "TCE", "level": 2}],
		"kind": "character", "inventory": [armor], "optional_features_catalog": [],
		"proficiency_choices": [], "proficiency_origins": [], "formula_bonuses": [],
		"abilities": {"str": 10, "dex": 10, "con": 10, "int": 16, "wis": 10, "cha": 10}
	}
	assert(Infusions.active_limit(record) == 2 and Infusions.known_limit(record) == 4)
	assert(Infusions.item_eligible(option, armor))
	assert(not Infusions.item_eligible(option, {"id": "magic_item:enchanted_armor", "name": "Enchanted Armor", "type": "MA", "rarity": "rare"}))
	assert(Infusions.replicable(replicate, {"id": "magic_item:bag", "name": "Bag of holding", "rarity": "uncommon"}, 2))
	assert(not Infusions.replicable(replicate, {"id": "magic_item:bag", "name": "Bag of holding", "rarity": "uncommon"}, 1))

	var tab := InventoryTab.new()
	root.add_child(tab)
	var changed: Array = []
	tab.setup(func(inventory: Array) -> void: changed.append(inventory.duplicate(true)), Callable())
	tab.load_record(record)
	assert(tab._infusion_panel.visible)
	var index := -1
	for i: int in range(tab._infusion_candidates.size()):
		if tab._infusion_candidates[i].get("id", "") == option.get("id", ""):
			index = i
			break
	assert(index >= 0)
	tab._infusion_catalog_picker.select(index)
	tab._learn_infusion()
	assert(tab.optional_features().size() == 1 and changed.size() == 1)
	tab._inventory_list.select(0)
	tab._infusion_known_picker.select(0)
	tab._apply_infusion()
	assert(changed.size() == 2 and not (changed.back()[0].get("infusion", {}) as Dictionary).is_empty())
	record.optional_features_catalog = tab.optional_features()
	record.inventory = [Instances.from_saved(changed.back()[0])]
	assert(Bonuses.bonus(record, "ac") == 1, "Equipped infused armor must use ordinary item bonus pipeline")
	record.classes[0].level = 10
	assert(Bonuses.bonus(record, "ac") == 2, "Bonus must scale with its creator's Artificer level")
	record.inventory[0].equipped_slots = []
	assert(Bonuses.bonus(record, "ac") == 0, "Unequipping removes native item bonuses")
	tab._clear_infusion()
	assert(changed.back()[0].get("infusion", {}).is_empty(), "Ending infusion must remove its item metadata")
	tab._forget_infusion()
	assert(tab.optional_features().is_empty())
	tab.queue_free()
	await process_frame
	await process_frame
	print("PASS: artificer infusion catalog, limits, native bonus, item persistence and removal")
	quit()
