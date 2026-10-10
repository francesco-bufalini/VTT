extends SceneTree

const InventoryTab = preload("res://vtt/creature_inventory_tab.gd")


func _initialize() -> void:
	call_deferred("_run")


func _choice_index(option: OptionButton, wanted: String) -> int:
	for i: int in range(option.item_count):
		if String(option.get_item_metadata(i)) == wanted:
			return i
	return -1


func _run() -> void:
	var tab := InventoryTab.new()
	root.add_child(tab)
	var events: Array = []
	tab.setup(func(items: Array) -> void: events.append(items.duplicate(true)), Callable())
	assert(not tab._search_panel.visible and not tab._search_toggle.button_pressed)
	assert(tab._inventory_list.visible, "Search must not hide the owned inventory")
	var longsword := {
		"id": "sword|phb", "name": "Longsword", "type": "M",
		"source": "PHB", "damage": "1d8", "properties": ["V"], "rarity": "none"
	}
	var rapier := {
		"id": "rapier|phb", "name": "Rapier", "type": "M",
		"source": "PHB", "damage": "1d8", "properties": ["F"], "rarity": "none"
	}
	var moonblade := {
		"id": "magic_item:moonblade", "name": "Moonblade", "type": "M",
		"source": "DMG", "damage": "1d8", "properties": ["V"],
		"rarity": "legendary", "magic": true
	}
	var xphb := {
		"id": "dagger|xphb", "name": "Dagger 2024", "type": "M|XPHB",
		"source": "XPHB", "damage": "1d4", "properties": ["F"], "rarity": "common"
	}
	tab._catalog = [longsword, rapier, moonblade, xphb]
	tab._populate_catalog_options()
	tab.load_record({"rules_version": "2014", "inventory": [
		{"id": "old-rope", "name": "Rope", "source": "PHB", "quantity": 2}
	]})
	# Test fixture replaces the catalog after setup; rebuild its visible results.
	tab._filter_catalog()
	assert(tab._filtered.size() == 3 and tab._catalog_count.text == "Risultati: 3")
	tab._set_search_visible(true)
	assert(tab._search_panel.visible and tab._search_toggle.button_pressed)
	tab._category_filter.select(1)
	tab._property_filter.select(_choice_index(tab._property_filter, "F"))
	tab._filter_catalog()
	assert(tab._filtered.size() == 1 and tab._filtered[0].id == "rapier",
		"Weapon type and structured property filters must combine")
	tab._reset_catalog_filters()
	tab._search.text = "moon legendary"
	tab._filter_catalog()
	assert(tab._filtered.size() == 1 and tab._filtered[0].id == moonblade.id,
		"Search words must match different structured fields")
	tab._search.clear()
	tab._rarity_filter.select(_choice_index(tab._rarity_filter, "legendary"))
	tab._source_filter.select(_choice_index(tab._source_filter, "DMG"))
	tab._filter_catalog()
	assert(tab._filtered.size() == 1 and tab._filtered[0].id == moonblade.id,
		"Rarity and source filters must work together")
	tab._reset_catalog_filters()
	tab._catalog_list.select(1)
	tab._catalog_list.item_selected.emit(1)
	assert(tab._catalog_details.visible and not tab._add_button.disabled)
	tab._add_selected()
	assert(events.size() == 1 and events.back().size() == 2,
		"Adding catalog items must keep already saved items")
	tab._set_search_visible(false)
	assert(not tab._search_panel.visible and tab._add_button.disabled
		and tab._inventory_list.visible and tab._inventory_list.item_count == 2)
	tab._set_search_visible(true)
	assert(tab._filtered.size() == 3 and tab._catalog_list.item_count == 3)
	tab.load_record({"rules_version": "2024", "inventory": events.back()})
	assert(tab._filtered.size() == 4 and _choice_index(tab._source_filter, "XPHB") >= 0,
		"2024 entries remain available for 2024 characters")
	tab.queue_free()
	await process_frame
	print("PASS: inventory catalog search toggle, rarity/source/weapon filters, preview and editions")
	quit()
