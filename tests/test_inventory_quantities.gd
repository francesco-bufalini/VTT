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
	tab.queue_free()
	await process_frame
	print("PASS: saved inventory selection, quantity editing, callbacks and removal")
	quit()
