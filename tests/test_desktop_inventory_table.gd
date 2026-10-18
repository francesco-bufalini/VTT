extends SceneTree

const InventoryTab = preload("res://vtt/creature_inventory_tab.gd")
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const AttackData = preload("res://vtt/creature_attack_data.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var tab := InventoryTab.new()
	root.add_child(tab)
	var updates: Array = []
	tab.setup(func(items: Array) -> void: updates.append(items.duplicate(true)), Callable())
	var weapon := {
		"id": "test:rapier", "name": "Stocco", "type": "M",
		"source": "PHB", "quantity": 2, "properties": ["F", "L"],
		"value_gp": 15, "weight": 2
	}
	var armor := {
		"id": "test:armor", "name": "Armatura modificata", "type": "MA",
		"source": "PHB", "quantity": 1, "ac": 14, "dexterity_max": 3
	}
	var shield := {"id": "test:shield", "name": "Scudo", "type": "S",
		"source": "PHB", "quantity": 1, "ac": 2}
	var torch := {"id": "test:torch", "name": "Torcia", "type": "G",
		"source": "PHB", "quantity": 3, "weight": 1}
	var ring := {"id": "test:ring", "name": "Anello", "type": "RG",
		"source": "DMG", "quantity": 1, "reqAttune": true}
	var scroll := {"id": "test:scroll", "name": "Spell Scroll (3rd Level)",
		"type": "SC", "source": "DMG", "quantity": 1, "spellLevel": 3}
	tab.load_record({"inventory": [weapon, armor, shield, torch, ring, scroll],
		"attunement_max_base": 3})
	var desktop: Control = tab._desktop_ui
	var owned_tree: Tree = desktop.get("_owned_tree")
	var scroll_tree: Tree = desktop.get("_scroll_tree")
	var attunement_tree: Tree = desktop.get("_attunement_tree")
	var off_picker: OptionButton = desktop.get("_off")
	var maximum: SpinBox = desktop.get("_maximum")
	var first: TreeItem = owned_tree.get_root().get_first_child()
	assert(first.get_text(7) == "Stocco", "Owned item name must be the last column")
	assert(first.get_text(1) == "30 mo" and first.get_text(2) == "4 lb",
		"Cost and weight are multiplied by the stack quantity")
	assert(first.get_text(6) == "Accurata, Leggera", "Weapon properties use readable names")
	assert(desktop.call("_characteristic", armor) == "CA 14 + min(DES, 3)",
		"Custom armor Dexterity caps must match the actual AC rules")
	assert(desktop.call("_characteristic", shield) == "CA +2")
	var scroll_row: TreeItem = scroll_tree.get_root().get_first_child()
	assert(scroll_row != null and scroll_row.get_text(1) == "3",
		"Spell scrolls belong in their own level-sorted metadata table")
	assert(scroll_row.get_text(2) == "Incantesimo non specificato",
		"Generic scroll titles must not masquerade as spell names")
	assert(owned_tree.get_root().get_child_count() == 5,
		"Scrolls are excluded from the ordinary owned item table")
	# All embedded scrollable controls must let the enclosing creature sheet
	# receive wheel events (especially once their own scrollbar hits a limit).
	assert(owned_tree.mouse_force_pass_scroll_events and scroll_tree.mouse_force_pass_scroll_events
		and attunement_tree.mouse_force_pass_scroll_events and tab._details.mouse_force_pass_scroll_events
		and tab._catalog_list.mouse_force_pass_scroll_events,
		"Desktop inventory controls must not trap the sheet's vertical scrolling")
	var plus_icon: Texture2D = desktop.get("_plus_icon")
	assert(plus_icon.get_width() == 14,
		"Equipment and quantity indicators must be compact")

	# Only one table can retain a selection, even when it was previously
	# selected in a different Tree.
	first.select(0)
	desktop.call("_on_owned_selected")
	scroll_row.select(0)
	desktop.call("_on_scroll_selected")
	assert(owned_tree.get_selected() == null and scroll_tree.get_selected() != null,
		"Selecting a scroll must deselect previously highlighted owned items")
	first.select(0)
	desktop.call("_on_owned_selected")
	assert(scroll_tree.get_selected() == null and owned_tree.get_selected() != null,
		"Selecting an owned item must deselect the scroll")
	# Dispatch the same Tree button_clicked signal used by mouse selection.
	# The saved quantity must not change synchronously: rebuilding a Tree
	# inside that signal causes Godot's blocked > 0 / null-create_item error.
	owned_tree.button_clicked.emit(first, 4, 101, 1)
	assert(int(tab._inventory[0].quantity) == 2,
		"Quantity button should defer the inventory mutation")
	await process_frame
	assert(int(tab._inventory[0].quantity) == 3,
		"Deferred item quantity change must persist on the owner")
	assert(owned_tree.get_root().get_first_child().get_text(1) == "45 mo",
		"Deferred refresh must rebuild totals after the mouse event")
	scroll_row = scroll_tree.get_root().get_first_child()
	scroll_tree.button_clicked.emit(scroll_row, 0, 101, 1)
	assert(int(tab._inventory[5].quantity) == 1)
	await process_frame
	assert(int(tab._inventory[5].quantity) == 2 and scroll_tree.get_selected() != null,
		"Scroll quantities must use the same deferred edit path")

	# The hand/armor selectors persist the same item slots used by game rules.
	tab._inventory_list.select(0)
	tab._equip_selected("main")
	assert("main" in ItemRules.slots(tab._inventory[0]))
	assert(owned_tree.get_root().get_first_child().get_text(0).contains("⚔"))
	tab._inventory_list.select(2)
	tab._equip_selected("off")
	assert("off" in ItemRules.slots(tab._inventory[2]))
	var test_record := {"kind": "character", "inventory": tab._inventory,
		"abilities": {"str": 12, "dex": 12, "con": 12, "int": 12, "wis": 12, "cha": 12}}
	var has_improvised := false
	for attack: Dictionary in AttackData.definitions(test_record):
		if String(attack.get("id", "")) == "improvised":
			has_improvised = true
	assert(has_improvised, "An off-hand shield grants the improvised strike")
	# Generic equipment alone activates its item origin.
	tab._inventory_list.select(3)
	tab._set_generic_equipment(true)
	assert(ItemRules.origin_active(tab._inventory[3]))
	assert(updates.size() >= 3)
	# A spell-requiring item only lights its attunement row when attuned.
	tab._inventory_list.select(4)
	tab._set_attunement(true)
	assert(ItemRules.origin_active(tab._inventory[4]))
	assert(attunement_tree.get_root().get_first_child().is_checked(0))
	maximum.value = 4
	assert(tab.attunement_max_base() == 4 and tab.attunement_capacity() == 4,
		"The editable capacity must be exported through the inventory owner")
	tab.set_gui_language("en")
	assert(owned_tree.get_column_title(1) == "Value" and
		scroll_tree.get_column_title(2) == "Spell",
		"Desktop table titles must follow the creature language")
	# Equipping a two-handed weapon locks the off-hand menu.
	var glaive := {"id": "test:glaive", "name": "Alabarda", "type": "M",
		"quantity": 1, "source": "PHB", "properties": ["2H"]}
	tab.load_record({"inventory": [glaive, shield]})
	tab._inventory_list.select(0)
	tab._equip_selected("main")
	assert(off_picker.disabled and off_picker.get_item_text(0).contains("two hands"))
	assert(ItemRules.occupying(tab._inventory, "off").is_empty())
	tab.queue_free()
	await process_frame
	print("PASS: desktop inventory tables, scrolls, slot icons, shield attacks and attunement")
	quit()
