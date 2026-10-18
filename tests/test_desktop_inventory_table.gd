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
	var first: TreeItem = desktop._owned_tree.get_root().get_first_child()
	assert(first.get_text(7) == "Stocco", "Owned item name must be the last column")
	assert(first.get_text(1) == "30 mo" and first.get_text(2) == "4 lb",
		"Cost and weight are multiplied by the stack quantity")
	assert(first.get_text(6) == "Accurata, Leggera", "Weapon properties use readable names")
	assert(desktop._characteristic(armor) == "CA 14 + min(DES, 3)",
		"Custom armor Dexterity caps must match the actual AC rules")
	assert(desktop._characteristic(shield) == "CA +2")
	var scroll_row: TreeItem = desktop._scroll_tree.get_root().get_first_child()
	assert(scroll_row != null and scroll_row.get_text(1) == "3",
		"Spell scrolls belong in their own level-sorted metadata table")
	assert(scroll_row.get_text(2) == "Incantesimo non specificato",
		"Generic scroll titles must not masquerade as spell names")
	assert(desktop._owned_tree.get_root().get_child_count() == 5,
		"Scrolls are excluded from the ordinary owned item table")
	# The hand/armor selectors persist the same item slots used by game rules.
	tab._inventory_list.select(0)
	tab._equip_selected("main")
	assert("main" in ItemRules.slots(tab._inventory[0]))
	assert(desktop._owned_tree.get_root().get_first_child().get_text(0).contains("⚔"))
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
	assert(desktop._attunement_tree.get_root().get_first_child().is_checked(0))
	desktop._maximum.value = 4
	assert(tab.attunement_max_base() == 4 and tab.attunement_capacity() == 4,
		"The editable capacity must be exported through the inventory owner")
	tab.set_gui_language("en")
	assert(desktop._owned_tree.get_column_title(1) == "Value" and
		desktop._scroll_tree.get_column_title(2) == "Spell",
		"Desktop table titles must follow the creature language")
	# Equipping a two-handed weapon locks the off-hand menu.
	var glaive := {"id": "test:glaive", "name": "Alabarda", "type": "M",
		"quantity": 1, "source": "PHB", "properties": ["2H"]}
	tab.load_record({"inventory": [glaive, shield]})
	tab._inventory_list.select(0)
	tab._equip_selected("main")
	assert(desktop._off.disabled and desktop._off.get_item_text(0).contains("two hands"))
	assert(ItemRules.occupying(tab._inventory, "off").is_empty())
	tab.queue_free()
	await process_frame
	print("PASS: desktop inventory tables, scrolls, slot icons, shield attacks and attunement")
	quit()
