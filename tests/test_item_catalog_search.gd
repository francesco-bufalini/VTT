extends SceneTree

const InventoryTab = preload("res://vtt/creature_inventory_tab.gd")
const Locale = preload("res://vtt/creature_gui_locale.gd")


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
	assert(tab._search_toggle.get_parent().get_child(0) is Label
		and tab._search_panel.get_index() == tab._search_toggle.get_parent().get_index() + 1,
		"Search Items must appear next to Inventory title and expand directly underneath")
	var shields: Array[Dictionary] = [
		{"id": "armor:shield|phb|s", "name": "Shield", "source": "PHB", "type": "S", "ac": 2},
		{"id": "mundane_item:shield|phb|s", "name": "Shield", "source": "PHB", "type": "S", "ac": 2},
		{"id": "armor:shield|xphb|s|xphb", "name": "Shield", "source": "XPHB", "type": "S|XPHB", "ac": 2},
		{"id": "mundane_item:shield|xphb|s|xphb", "name": "Shield", "source": "XPHB", "type": "S|XPHB", "ac": 2}
	]
	var unique_shields: Array[Dictionary] = InventoryTab._unique_catalog_items(shields)
	assert(unique_shields.size() == 2
		and unique_shields[0].id == "armor:shield|phb|s"
		and unique_shields[1].id == "armor:shield|xphb|s|xphb",
		"Shield from PHB and XPHB must appear only once per edition")
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
	tab.load_record({"rules_version": "2014", "inventory": [
		{"id": "old-rope", "name": "Rope", "source": "PHB", "quantity": 2}
	]})
	# load_record reloads the production catalog; install this isolated fixture afterwards.
	tab._catalog = [longsword, rapier, moonblade, xphb]
	tab._populate_catalog_options()
	tab._filter_catalog()
	assert(tab._filtered.size() == 4 and tab._catalog_count.text == "Risultati: 3")
	# Reproduction of the regression: localized labels used to make the
	# Italian-only category comparison reject every item.
	Locale.apply(tab, "en")
	assert(tab._category_filter.get_item_text(0) == "All")
	tab._filter_catalog()
	assert(tab._filtered.size() == 4 and tab._catalog_count.text == "Risultati: 3",
		"Localized All filter must still include the entire 2014 catalog")
	tab._category_filter.select(1)
	tab._filter_catalog()
	assert(tab._filtered.size() == 4, "Localized Weapons category must keep matching by stable ID")
	Locale.apply(tab, "it")
	tab._category_filter.select(0)
	tab._filter_catalog()
	# Broad substring search previously tried to instantiate hundreds of
	# rich tooltip descriptions and could crash on weapon property variants.
	tab._search.text = "la"
	tab._filter_catalog()
	assert(not tab._filtered.is_empty() and tab._catalog_list.item_count == tab._filtered.size(),
		"Typing la must populate item results without formatting every item description")
	tab._search.clear()
	tab._filter_catalog()
	tab._set_search_visible(true)
	assert(tab._search_panel.visible and tab._search_toggle.button_pressed)
	tab._category_filter.select(1)
	tab._property_filter.select(_choice_index(tab._property_filter, "F"))
	tab._filter_catalog()
	assert(tab._filtered.size() == 2 and tab._filtered[1].id == rapier.id,
		"Weapon type and structured property filters must combine")
	tab._reset_catalog_filters()
	tab._search.text = "moon legendary"
	tab._filter_catalog()
	assert(tab._filtered.size() == 2 and tab._filtered[1].id == moonblade.id,
		"Search words must match different structured fields")
	tab._search.clear()
	tab._rarity_filter.select(_choice_index(tab._rarity_filter, "legendary"))
	tab._source_filter.select(_choice_index(tab._source_filter, "DMG"))
	tab._filter_catalog()
	assert(tab._filtered.size() == 2 and tab._filtered[1].id == moonblade.id,
		"Rarity and source filters must work together")
	tab._reset_catalog_filters()
	tab._catalog_list.select(2)
	tab._catalog_list.item_selected.emit(2)
	assert(tab._details.visible and tab._details_from_catalog
		and tab._details.get_parent() == tab._inventory_list.get_parent()
		and tab._details.text.contains("Rapier")
		and not tab._add_button.disabled,
		"Selecting a search result must display its description in the owned-item details panel")
	tab._add_selected()
	assert(events.size() == 1 and events.back().size() == 2,
		"Adding catalog items must keep already saved items")
	tab._set_search_visible(false)
	assert(not tab._search_panel.visible and tab._add_button.disabled
		and tab._inventory_list.visible and tab._inventory_list.item_count == 2
		and not tab._details_from_catalog)
	tab._set_search_visible(true)
	assert(tab._filtered.size() == 4 and tab._catalog_list.item_count == 4)
	tab.load_record({"rules_version": "2024", "inventory": events.back()})
	tab._catalog = [longsword, rapier, moonblade, xphb]
	tab._populate_catalog_options()
	tab._filter_catalog()
	assert(tab._filtered.size() == 5 and _choice_index(tab._source_filter, "XPHB") >= 0,
		"2024 entries remain available for 2024 characters")
	# The selected generic item's real checkbox and attunement control
	# must persist independently. A visible checkbox is provided instead
	# of relying solely on hitting a tiny ItemList icon.
	var amulet := {
		"id": "magic_item:attunement_test", "name": "Amulet of Tests", "source": "DMG",
		"quantity": 1, "type": "G", "reqAttune": "by a spellcaster"
	}
	tab._catalog.append(amulet)
	tab._inventory.append({
		"id": amulet.id, "name": amulet.name, "source": amulet.source,
		"quantity": 1, "type": "G", "reqAttune": "by a spellcaster",
		"equipped": false, "attuned": false, "active": true, "equipped_slots": []
	})
	var amulet_index: int = tab._inventory.size() - 1
	tab._refresh_inventory(amulet_index)
	assert(tab._generic_equip.visible and not tab._generic_equip.disabled
		and not tab._generic_equip.button_pressed,
		"Selected generic items need a usable equip checkbox")
	assert(not tab._attuned.disabled and not tab._attuned.button_pressed,
		"Items with structured reqAttune must allow attunement")
	tab._set_generic_equipment(true)
	assert(bool(events.back()[amulet_index].get("equipped", false))
		and tab._generic_equip.button_pressed,
		"Equipment checkbox must save and immediately reflect its new value")
	tab._set_attunement(true)
	assert(bool(events.back()[amulet_index].get("attuned", false))
		and tab._attuned.button_pressed,
		"Attunement checkbox must save and stay checked")
	tab.load_record({"rules_version": "2024", "inventory": events.back()})
	tab._inventory_list.select(amulet_index)
	tab._on_inventory_selected(amulet_index)
	assert(tab._generic_equip.button_pressed and tab._attuned.button_pressed,
		"Equipment and attunement must survive reloading a creature")
	tab._set_generic_equipment(false)
	assert(not bool(events.back()[amulet_index].get("equipped", true))
		and bool(events.back()[amulet_index].get("attuned", false)),
		"Stowing an item must not silently remove its attunement")
	tab._inventory_list.select(0)
	tab._on_inventory_selected(0)
	assert(tab._attuned.disabled and not tab._generic_equip.disabled,
		"Ordinary items can be equipped but do not request attunement")
	tab.queue_free()
	await process_frame
	print("PASS: locale-safe catalog search, selectable item equip, attunement and persistence")
	quit()
