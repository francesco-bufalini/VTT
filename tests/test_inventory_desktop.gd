extends SceneTree

const InventoryTab = preload("res://vtt/creature_inventory_tab.gd")
const Items = preload("res://vtt/creature_item_rules.gd")
const Attacks = preload("res://vtt/creature_attack_data.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")


func _initialize() -> void:
	call_deferred("run")


func _select(tab: Node, index: int) -> void:
	tab._inventory_list.select(index)
	tab._inventory_list.item_selected.emit(index)


func run() -> void:
	var tab := InventoryTab.new()
	root.add_child(tab)
	var updates: Array = []
	tab.setup(func(rows: Array) -> void: updates.append(rows.duplicate(true)), Callable())
	var greatsword := {"id": "test:greatsword", "name": "Greatsword", "source": "PHB",
		"type": "M", "damage": "2d6", "properties": ["2H"], "quantity": 1}
	var shield := {"id": "test:shield", "name": "Shield", "source": "PHB",
		"type": "S", "ac": 2, "quantity": 1}
	var ring := {"id": "test:ring", "name": "Ring of Protection", "source": "DMG",
		"type": "RG", "req_attune": true, "bonus_saving_throw": 1, "quantity": 1}
	var amulet := {"id": "test:amulet", "name": "Amulet", "source": "DMG",
		"type": "RG", "reqAttune": "by a spellcaster", "quantity": 1}
	var rope := {"id": "test:rope", "name": "Rope", "source": "PHB",
		"weight": 10, "value": 100, "quantity": 2}
	tab.load_record({"id": "test:inventory", "kind": "character", "inventory":
		[greatsword, shield, ring, amulet, rope], "attunement_max_base": 1})
	var desktop = tab._desktop_ui
	assert(desktop != null and desktop.visible)
	assert(desktop._owned_tree.columns == 8)
	assert(desktop._scroll_tree.columns == 3)
	assert(desktop._maximum.value == 1)
	assert(desktop._value_total(rope, 2) == "2 mo")
	assert(desktop._weight_total(rope, 2) == "20 lb")

	_select(tab, 0)
	tab._equip_selected("main")
	assert("main" in Items.slots(tab._inventory[0]))
	assert(desktop._off.disabled, "Two-handed main weapon must lock secondary hand")
	tab._clear_slot("main")
	assert(not desktop._off.disabled)
	_select(tab, 1)
	tab._equip_selected("off")
	assert("off" in Items.slots(tab._inventory[1]))
	var shield_attack := false
	for attack: Dictionary in Attacks.definitions({"inventory": tab._inventory,
		"hand_main_special": "none", "hand_off_special": "none"}):
		if String(attack.get("id", "")) == "improvised":
			shield_attack = true
	assert(shield_attack, "A held shield must unlock the improvised attack")

	_select(tab, 2)
	tab._set_attunement(true)
	assert(bool(tab._inventory[2].get("attuned", false)))
	assert(bool(tab._inventory[2].get("equipped", false)),
		"Attuned worn magic items must activate their origin")
	_select(tab, 3)
	tab._set_attunement(true)
	assert(not bool(tab._inventory[3].get("attuned", false)),
		"The capacity limit must reject one extra attunement")
	desktop._maximum.value = 2
	assert(tab.attunement_max_base() == 2)
	tab._set_attunement(true)
	assert(bool(tab._inventory[3].get("attuned", false)))
	_select(tab, 4)
	tab._set_generic_equipment(true)
	assert(Items.origin_active(tab._inventory[4]))
	tab._on_quantity_changed(4)
	assert(int(tab._inventory[4].get("quantity", 0)) == 4)
	assert(desktop._weight_total(tab._inventory[4], 4) == "40 lb")

	var record := {"attunement_max_base": 3, "formula_bonuses": [
		{"id": "attunement-grant", "target": "attunement_max",
			"expression": "2", "origin_id": "", "origin_name": "Test"}]}
	assert(Bonuses.value(record, "attunement_max") == 5,
		"Privileges must modify attunement maximum through normal formulas")
	assert(not updates.is_empty())
	tab.queue_free()
	await process_frame
	print("PASS: desktop inventory columns, quantities, slot locking, shield attacks, item origins and attunement capacity")
	quit()
