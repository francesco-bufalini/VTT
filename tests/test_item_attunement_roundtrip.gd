extends SceneTree

const ItemInstance = preload("res://vtt/item_instance.gd")
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const InventoryTab = preload("res://vtt/creature_inventory_tab.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var stone: Dictionary = {"id": "test:luckstone", "name": "Stone of Good Luck", "quantity": 4,
		"req_attune": true, "attuned": true, "attuned_count": 3}
	var saved: Dictionary = ItemInstance.from_saved(stone)
	assert(saved["quantity"] == 4 and saved["attuned_count"] == 3 and saved["attuned"])
	assert(ItemInstance.from_saved(saved) == saved, "Native archive roundtrips preserve PWA allocations")
	var smaller: Dictionary = saved.duplicate(true)
	smaller["quantity"] = 1
	assert(ItemInstance.from_saved(smaller)["attuned_count"] == 1)
	var legacy: Dictionary = stone.duplicate(true)
	legacy.erase("attuned_count")
	assert(not ItemInstance.from_saved(legacy).has("attuned_count"), "Reading legacy saves must not invent allocations")
	assert(ItemRules.requires_attunement({"requires_attunement": true}))
	assert(ItemRules.requires_attunement({"requiresAttunement": "by a spellcaster"}))
	var tab := InventoryTab.new()
	root.add_child(tab)
	tab.setup(func(_items: Array) -> void: pass, Callable())
	tab._catalog.append({"id": "test:luckstone", "name": "Stone of Good Luck", "req_attune": true})
	tab._catalog.append({"id": "test:ring", "name": "Ring", "req_attune": true})
	tab.load_record({"attunement_max_base": 3, "inventory": [stone,
		{"id": "test:ring", "name": "Ring", "quantity": 1, "req_attune": true}]})
	tab._inventory_list.select(1)
	tab._inventory_list.item_selected.emit(1)
	tab._set_attunement(true)
	assert(not tab._inventory[1].get("attuned", false), "Three allocations occupy all native slots")
	tab._inventory_list.select(0)
	tab._inventory_list.item_selected.emit(0)
	tab._quantity.value = 2
	assert(tab._inventory[0]["attuned_count"] == 2, "Shrinking a native stack cannot leave excess allocations")
	tab._set_attunement(false)
	assert(tab._inventory[0]["attuned_count"] == 0 and not tab._inventory[0]["attuned"])
	tab.queue_free()
	await process_frame
	print("PASS: native archive preserves per-copy attunements, legacy records, quantity bounds and shared capacity")
	quit()
