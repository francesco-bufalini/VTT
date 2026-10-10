extends SceneTree

const InventoryTab = preload("res://vtt/creature_inventory_tab.gd")
var changes: Array[Array] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var tab := InventoryTab.new()
	root.add_child(tab)
	tab.setup(func(items: Array) -> void: changes.append(items), Callable())
	tab.load_record({"inventory": [
		{"id": "arrows|phb", "name": "Arrows", "source": "PHB", "quantity": 20},
		{"id": "rope|phb", "name": "Rope", "source": "PHB", "quantity": 2},
	]})
	assert(not tab._quantity.editable and tab._remove_button.disabled)
	tab._inventory_list.select(0)
	tab._inventory_list.item_selected.emit(0)
	assert(tab._quantity.editable, "Selecting a saved item must enable quantity editing")
	assert(not tab._remove_button.disabled, "Selecting a saved item must enable removal")
	assert(tab._quantity.value == 20 and changes.is_empty())
	tab._quantity.value = 37
	assert(changes.size() == 1 and changes.back()[0].quantity == 37)
	assert(tab._inventory_list.get_item_text(0).begins_with("37 ×"))
	assert(tab._selected_inventory_index() == 0)
	tab._inventory_list.select(1)
	tab._inventory_list.item_selected.emit(1)
	assert(tab._quantity.value == 2 and changes.size() == 1)
	tab._remove_selected()
	assert(changes.back().size() == 1 and changes.back()[0].quantity == 37)
	assert(not tab._quantity.editable and tab._remove_button.disabled)
	# 5etools stores conditional attunement as a String, unlike the
	# boolean for unconditional attunement. Selecting it must not crash.
	assert(not tab.ItemRules.requires_attunement({"reqAttune": false}))
	assert(not tab.ItemRules.requires_attunement({"reqAttune": ""}))
	assert(tab.ItemRules.requires_attunement({"reqAttune": true}))
	assert(tab.ItemRules.requires_attunement({"req_attune": "by a cleric"}))
	tab._catalog.append({
		"id": "test:attunement-string", "name": "Anello della prova",
		"source": "Test", "type": "RG", "reqAttune": "by a spellcaster"
	})
	tab.load_record({"inventory": [
		{"id": "test:attunement-string", "name": "Anello della prova",
			"source": "Test", "quantity": 1}
	]})
	tab._inventory_list.select(0)
	tab._inventory_list.item_selected.emit(0)
	assert(not tab._attuned.disabled,
		"Conditional string attunement must enable the inventory toggle")
	tab._catalog[tab._catalog.size() - 1]["reqAttune"] = false
	tab._update_equip_buttons()
	assert(tab._attuned.disabled,
		"An item without required attunement disables the toggle")
	tab._catalog[tab._catalog.size() - 1]["reqAttune"] = true
	tab._update_equip_buttons()
	assert(not tab._attuned.disabled,
		"Boolean true attunement is enabled consistently")
	tab.queue_free()
	await process_frame
	print("PASS: saved inventory selection, quantity editing, callbacks and removal")
	quit()
