extends SceneTree

const InventoryTab = preload("res://vtt/creature_inventory_tab.gd")
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const AttackData = preload("res://vtt/creature_attack_data.gd")
const Player5eTools = preload("res://vtt/player_5etools_catalog.gd")


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
	var main_size: OptionButton = desktop.get("_main_size")
	var off_size: OptionButton = desktop.get("_off_size")
	var menu: PopupMenu = desktop.get("_context_menu")
	var first: TreeItem = owned_tree.get_root().get_first_child()
	assert(first.get_text(6) == "Stocco", "Owned item name must be the last column")
	assert(owned_tree.columns == 7 and owned_tree.get_column_title(0) == "Eq.",
		"The owned table must have seven compact, labeled columns without rarity")
	assert(owned_tree.get_column_title(6) == "Nome", "The final column must be the item name")
	var equipment_panel: PanelContainer = desktop.get("_equipment_panel")
	var attune_panel: PanelContainer = desktop.get("_attunement_panel")
	assert(equipment_panel.get_index() == 0 and attune_panel.get_index() == 1,
		"Boxed equipment and attunement sections belong at the top of the inventory")
	assert((desktop.get("_main") as OptionButton).get_parent().get_parent() == equipment_panel.get_child(0).get_child(1)
		and (desktop.get("_main") as OptionButton).get_parent() != off_picker.get_parent(),
		"Main and off-hand selectors must live on distinct equipment rows")
	assert(menu.get_item_text(0) == "Rimuovi" and menu.get_item_text(1) == "Vedi nel bestiario",
		"Desktop right-click menu must expose removal and bestiary lookup")
	assert(not tab._legacy_actions.visible and not tab._legacy_switches.visible
		and not tab._legacy_size_row.visible and not tab._item_share_button.visible,
		"Obsolete remove/activate/send-copy/weapon-size controls must be hidden on desktop")
	assert(owned_tree.get_column_title(1) == "mo",
		"Compact value column shows its unit in a two-letter header")
	assert((desktop.get("_main") as OptionButton).size_flags_horizontal == Control.SIZE_FILL
		and (desktop.get("_main") as OptionButton).custom_minimum_size.x == 215
		and (desktop.get("_main") as OptionButton).get_parent().size_flags_horizontal == Control.SIZE_SHRINK_BEGIN,
		"Hand equipment controls must not stretch across the full sheet width")
	assert(first.get_text(1) == "30" and first.get_text(2) == "4 lb",
		"Costs are numeric gold pieces (unit only in header); weights scale with quantity")
	assert(first.get_text(5) == "Accurata · Leggera" or first.get_text(5) == "Accurata, Leggera",
		"Weapon properties use readable names")
	assert(desktop.call("_property_summary", {"name": "Test", "rarity": "rare"}) == "Raro",
		"Rarity appears in the properties column only when present")
	assert(desktop.call("_property_summary", weapon) == "Accurata, Leggera",
		"Absence of rarity must not add an extra property label")
	assert(desktop.call("_characteristic", armor) == "CA 14 + min(DES, 3)",
		"Custom armor Dexterity caps must match the actual AC rules")
	assert(desktop.call("_characteristic", shield) == "CA +2")
	var scroll_row: TreeItem = scroll_tree.get_root().get_first_child()
	assert(scroll_row != null and scroll_row.get_text(1) == "3",
		"Spell scrolls belong in their own level-sorted metadata table")
	assert(scroll_row.get_text(2) == "Incantesimo non specificato",
		"Generic scroll titles must not masquerade as spell names")
	assert(owned_tree.get_root().get_first_child().get_next().get_button_id(3, 0) == 102,
		"Quantity 1 must show the removal X instead of a disabled minus button")
	assert(scroll_row.get_button_id(0, 0) == 102,
		"Quantity 1 spell scrolls must also show the removal X")
	assert(owned_tree.get_root().get_child_count() == 5,
		"Scrolls are excluded from the ordinary owned item table")
	# Wheel events must remain owned by a nested scrollable widget even at
	# its boundary; the parent sheet must not jump unexpectedly.
	assert(not owned_tree.mouse_force_pass_scroll_events
		and scroll_tree.mouse_force_pass_scroll_events
		and attunement_tree.mouse_force_pass_scroll_events
		and not tab._details.mouse_force_pass_scroll_events
		and not tab._catalog_list.mouse_force_pass_scroll_events,
		"Fully expanded scroll and attunement tables must pass wheel input to the parent, unlike bounded lists")
	assert(attunement_tree.custom_minimum_size.y <= 90.0,
		"Attunement table must not reserve empty height beyond the single entry")
	assert(not attunement_tree.scroll_vertical_enabled and not scroll_tree.scroll_vertical_enabled,
		"Attunement and scroll rows must never use inner vertical scrolling")
	assert(not tab._details.scroll_active and tab._details.fit_content
		and tab._details.custom_minimum_size.y == 0,
		"Desktop full-length descriptions must grow with their text and use only outer scrolling")
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
	owned_tree.button_clicked.emit(first, 3, 101, 1)
	assert(int(tab._inventory[0].quantity) == 2,
		"Quantity button should defer the inventory mutation")
	await process_frame
	assert(int(tab._inventory[0].quantity) == 3,
		"Deferred item quantity change must persist on the owner")
	assert(owned_tree.get_root().get_first_child().get_text(1) == "45",
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
	assert(not main_size.disabled and main_size.get_parent() == (desktop.get("_main") as OptionButton).get_parent(),
		"Weapon size is editable directly beside the main hand picker")
	assert(owned_tree.get_root().get_first_child().get_text(0).contains("⚔"))
	tab._inventory_list.select(2)
	tab._equip_selected("off")
	assert("off" in ItemRules.slots(tab._inventory[2]))
	assert(off_size.disabled, "A shield must not expose weapon-size options")
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
	# Attunable objects with no weapon/armor/shield slot also use the first
	# column for the equipped state.
	tab._inventory_list.select(4)
	tab._set_generic_equipment(false)
	assert(not bool(tab._inventory[4].get("equipped", true)),
		"Attunable non-slot objects must support the same equipped toggle")
	tab._set_generic_equipment(true)
	assert(attunement_tree.get_root().get_first_child().is_checked(0))
	assert(attunement_tree.custom_minimum_size.y <= 60.0,
		"Attunement table height should track its entry count")
	maximum.value = 4
	assert(tab.attunement_max_base() == 4 and tab.attunement_capacity() == 4,
		"The editable capacity must be exported through the inventory owner")
	tab.set_gui_language("en")
	assert(owned_tree.get_column_title(1) == "gp" and
		scroll_tree.get_column_title(2) == "Spell",
		"Desktop table titles must follow the creature language")
	# 5etools stores long item prose in a separate compendium index.
	# On selection it must be rendered instead of only the synthesized
	# property/value text from the search catalog.
	var described_item: Dictionary = {}
	var original_prose := ""
	for candidate: Dictionary in Player5eTools.entries("items"):
		if not String(candidate.get("id", "")).begins_with("magic_item:"):
			continue
		var prose: String = Player5eTools.description_text("items", candidate)
		if prose.length() > 160:
			described_item = candidate
			original_prose = prose
			break
	assert(not described_item.is_empty(), "The full 5etools item prose index must be available")
	tab.call("_show_details", described_item)
	assert(tab._details.text.contains(original_prose.substr(0, 80)),
		"Selected item details must include the full 5etools compendium description")
	assert(not tab._details.text.contains("Dati strutturati:"),
		"Desktop item descriptions must not append the verbose structured-data footer")
	assert(Player5eTools.compact_item_info_text(weapon, "Full prose").split("\n\n")[0].split("\n").size() <= 4,
		"Structured item mechanics must be summarized into a few lines")

	# The bestiary action must resolve the installed catalog entry by ID.
	tab._catalog.append(torch.duplicate(true))
	tab.call("_show_owned_item_in_catalog", 3)
	var found_in_catalog: PackedInt32Array = tab._catalog_list.get_selected_items()
	assert(tab._search_panel.visible and not found_in_catalog.is_empty()
		and String(tab._filtered[found_in_catalog[0]].get("id", "")) == "test:torch"
		and tab._details_from_catalog,
		"View in bestiary must select the owned item's definition in the catalog")

	# Equipping a two-handed weapon locks the off-hand menu.
	var glaive := {"id": "test:glaive", "name": "Alabarda", "type": "M",
		"quantity": 1, "source": "PHB", "properties": ["2H"]}
	tab.load_record({"inventory": [glaive, shield]})
	tab._inventory_list.select(0)
	tab._equip_selected("main")
	assert(off_picker.disabled and off_picker.get_item_text(0).contains("two hands"))
	assert(ItemRules.occupying(tab._inventory, "off").is_empty())
	desktop.call("_on_slot_size_selected", 4, "main")
	await process_frame
	assert(String((tab._inventory[0].get("instance_overrides", {}) as Dictionary).get("weapon_size", "")) == "Large",
		"Main hand size control must edit the equipped weapon's instance")
	assert(main_size.get_selected_id() == 4 and off_size.disabled,
		"Hand-size selectors must follow the current occupied weapon slot")
	# Entering zero removes an owned entry; the context-menu removal uses
	# that same owner-managed path and must never leave stale table rows.
	var before := tab._inventory.size()
	desktop.call("_update_quantity", 1, 0)
	assert(tab._inventory.size() == before - 1,
		"Setting quantity to zero must delete the stack")
	desktop.set("_context_index", 0)
	desktop.call("_on_context_action", 1)
	await process_frame
	assert(tab._inventory.is_empty(),
		"Right-click Remove must delete the selected owned entry")
	# When two equal weapons occupy both hands, resizing the main-hand
	# instance must preserve the off-hand equipped copy.
	var paired := {"id": "test:paired", "name": "Daghe", "type": "M",
		"properties": ["L"], "quantity": 2, "equipped_slots": ["main", "off"]}
	tab.load_record({"inventory": [paired]})
	tab.set_weapon_size_at(0, 4, "main")
	assert(tab._inventory.size() == 2
		and "off" in ItemRules.slots(tab._inventory[0])
		and "main" in ItemRules.slots(tab._inventory[1])
		and String(tab._inventory[1].get("instance_overrides", {}).get("weapon_size", "")) == "Large",
		"Weapon size overrides must not steal the opposite hand's equipped copy")

	# The attunement and scroll tables should expand for any number of rows,
	# without fixed caps that hide content behind private scrollbars.
	var many: Array[Dictionary] = []
	for i: int in range(11):
		many.append({"id": "test:attune:%d" % i, "name": "Attune %d" % i,
			"type": "RG", "reqAttune": true, "quantity": 1})
		many.append({"id": "test:scroll:%d" % i,
			"name": "Spell Scroll (3rd Level)", "type": "SC", "quantity": 1})
	tab.load_record({"inventory": many})
	await process_frame
	await process_frame
	assert(attunement_tree.get_root().get_child_count() == 11
		and scroll_tree.get_root().get_child_count() == 11,
		"Large inventory tables must keep every attunement and scroll row")
	assert(attunement_tree.custom_minimum_size.y > 275.0
		and scroll_tree.custom_minimum_size.y > 275.0,
		"All attunement and scroll entries must grow beyond the old fixed height")
	assert(not attunement_tree.scroll_vertical_enabled and not scroll_tree.scroll_vertical_enabled,
		"Long auxiliary tables must rely on the outer sheet's scroll viewport")
	tab.queue_free()
	await process_frame
	print("PASS: desktop inventory tables, scrolls, slot icons, shield attacks and attunement")
	quit()
