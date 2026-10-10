extends SceneTree

const Instances = preload("res://vtt/item_instance.gd")
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const InventoryTab = preload("res://vtt/creature_inventory_tab.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var definition := {
		"id": "test:blade", "name": "Longsword", "source": "PHB",
		"type": "M", "damage": "1d8", "properties": ["V"]
	}
	var owned: Dictionary = Instances.from_catalog(definition)
	assert(owned.id == definition.id and owned.quantity == 1)
	owned["instance_overrides"] = {
		"dimensions_m": {"length": 1.25},
		"damage": "1d10"
	}
	var changed: Dictionary = Instances.resolve(definition, owned)
	assert(changed.damage == "1d10")
	assert(changed.dimensions_m.length == 1.25)
	assert(definition.damage == "1d8" and not definition.has("dimensions_m"))
	assert(Instances.from_saved(owned).instance_overrides.dimensions_m.length == 1.25)
	assert(ItemRules.entry_for(owned).damage == "1d10", "Instance effects reach attack mechanics")

	var events: Array = []
	var tab := InventoryTab.new()
	root.add_child(tab)
	tab.setup(func(items: Array) -> void: events.append(items.duplicate(true)), Callable())
	tab.load_record({"inventory": [
		{"id": "test:blade", "name": "Longsword", "source": "PHB", "quantity": 3, "type": "M", "damage": "1d8", "properties": ["V"]}
	]})
	tab._inventory_list.select(0)
	tab._inventory_list.item_selected.emit(0)
	var length_box: SpinBox = tab._size_fields["length"]
	length_box.value = 1.25
	assert(events.size() == 1)
	assert(events[0].size() == 2, "Editing an individual object splits a stack")
	assert(events[0][0].quantity == 2 and events[0][1].quantity == 1)
	assert(not events[0][0].instance_overrides.has("dimensions_m"))
	assert(events[0][1].instance_overrides.dimensions_m.length == 1.25)
	tab.load_record({"inventory": events.back()})
	assert(tab._inventory.size() == 2)
	assert(tab._inventory[1].instance_overrides.dimensions_m.length == 1.25)
	tab.queue_free()
	await process_frame
	print("PASS: item instance dimensions and mechanics do not mutate compendium; legacy inventory persists")
	quit()
