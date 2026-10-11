extends SceneTree

const SpellcastingTab = preload("res://vtt/creature_spellcasting_tab.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# Regression: the creature sheet calls setup() before load_record().
	# No selected creature or populated slot arrays exist at that point.
	var tab := SpellcastingTab.new()
	root.add_child(tab)
	tab.setup(Callable(), Callable())
	assert(tab._totals.size() == 10 and tab._spent.size() == 10,
		"setup must initialize all spell-slot arrays before rendering formulas")
	for lvl: int in range(1, 10):
		assert(tab._remaining_labels[lvl].text == "0 /",
			"An uninitialized creature must show zero available slots")
		assert(tab._slot_formula_values[lvl].value_label.text == "0",
			"Slot maximum formula must render as zero before a creature loads")
		assert(tab._slot_use[lvl].disabled and tab._slot_recharge[lvl].disabled,
			"No slots should be usable or recharged before load_record")
		assert(tab._slot_use[lvl].get_index() + 1 == tab._slot_recharge[lvl].get_index(),
			"Slot − and + must be adjacent before remaining/max")
	assert(tab._pact_use.get_index() + 1 == tab._pact_restore.get_index(),
		"Pact slots must use the same − + remaining/max ordering")

	# Defensive rendering also works if a caller resets the buffers early.
	tab._totals.clear()
	tab._spent.clear()
	tab._update_resource_labels()
	assert(tab._slot_formula_values[1].value_label.text == "0",
		"Missing arrays must not cause out-of-bounds access in slot formula")

	# Exercise the same compact readouts with real creature data and a bonus.
	tab.load_record({"kind": "character", "level": 6, "rules_version": "2014",
		"classes": [{"name": "Wizard", "source": "PHB", "level": 6}],
		"spell_slots_total": [0, 4, 3, 3, 0, 0, 0, 0, 0, 0],
		"formula_bonuses": [{"id": "slot-ui", "target": "slot:1", "expression": "2"}]})
	assert(tab._remaining_labels[1].text == "6 /"
		and tab._slot_formula_values[1].value_label.text == "6",
		"Origin bonuses must update both remaining and the separate maximum readout")
	assert(tab._description.get_parent().get_parent() == tab
		and tab._description.get_parent().get_index() > tab._prepare.get_parent().get_index()
		and tab._description.scroll_active,
		"Spell description must scroll beneath the compact action bar")
	tab._set_search_visible(true)
	tab._search.text = "Magic Missile"
	tab._filter_spells()
	var missile_index := -1
	for index: int in range(tab._visible.size()):
		if String(tab._visible[index].get("name", "")) == "Magic Missile":
			missile_index = index
			break
	assert(missile_index >= 0)
	tab._available.select(missile_index)
	tab._on_spell_list_selected("catalog")
	assert(tab._description.visible and "Magic Missile" in tab._description.text)
	tab._toggle_selected_prepared()
	assert(tab._description.visible and "Magic Missile" in tab._description.text,
		"Preparing a spell must retain the selected detailed description")
	tab.queue_free()
	await process_frame
	print("PASS: spellcasting setup renders slot resources without a loaded creature")
	quit()
