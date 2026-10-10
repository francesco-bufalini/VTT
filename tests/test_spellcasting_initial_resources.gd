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
	assert(tab._totals.size() == 10 and tab._slot_bonuses.size() == 10
		and tab._spent.size() == 10,
		"setup must initialize all spell-slot arrays before rendering formulas")
	for lvl: int in range(1, 10):
		assert(tab._remaining_labels[lvl].text == "0 /",
			"An uninitialized creature must show zero available slots")
		assert(tab._slot_formula_values[lvl].value_label.text == "0",
			"Slot maximum formula must render as zero before a creature loads")
		assert(tab._slot_use[lvl].disabled and tab._slot_recharge[lvl].disabled,
			"No slots should be usable or recharged before load_record")

	# Defensive rendering also works if a caller resets the buffers early.
	tab._totals.clear()
	tab._slot_bonuses.clear()
	tab._spent.clear()
	tab._update_resource_labels()
	assert(tab._slot_formula_values[1].value_label.text == "0",
		"Missing arrays must not cause out-of-bounds access in slot formula")

	tab.queue_free()
	await process_frame
	print("PASS: spellcasting setup renders slot resources without a loaded creature")
	quit()
