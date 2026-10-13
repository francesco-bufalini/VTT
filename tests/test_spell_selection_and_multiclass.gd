extends SceneTree
const Rules = preload("res://vtt/creature_rules.gd")
const Choices = preload("res://vtt/class_spell_selection.gd")
const Selection = preload("res://vtt/spell_selection_dialog.gd")
const Casting = preload("res://vtt/creature_spellcasting_tab.gd")

func _initialize() -> void:
	call_deferred("run")

func progression(first: String, first_level: int, second: String, second_level: int, edition: String = "2014") -> Dictionary:
	return Rules.spell_slot_progression({"rules_version": edition, "classes": [{"name": first, "level": first_level}, {"name": second, "level": second_level}]})

func run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 720)
	await process_frame
	var ranger_wizard := progression("Ranger", 4, "Wizard", 3)
	assert(ranger_wizard.slots == [0, 4, 3, 2, 0, 0, 0, 0, 0, 0])
	assert(progression("Paladin", 3, "Fighter", 2).slots[1] == 3)
	assert(progression("Paladin", 3, "Warlock", 2).slots[1] == 3)
	assert(progression("Paladin", 3, "Wizard", 1).slots[1] == 3)
	assert(progression("Paladin", 3, "Ranger", 3).caster_level == 2)
	assert(progression("Paladin", 3, "Wizard", 1, "2024").caster_level == 3)
	var wizard_warlock := progression("Wizard", 3, "Warlock", 5)
	assert(wizard_warlock.slots[2] == 2 and wizard_warlock.pact_total == 2 and wizard_warlock.pact_level == 3)
	var members := Choices.classes({"rules_version": "2014", "classes": [{"name": "Ranger", "level": 4}, {"name": "Wizard", "level": 3}]})
	assert(members[0].max_level == 1 and members[1].max_level == 2, "Combined higher slots do not grant higher class spell selections")
	var dialog := Selection.new()
	root.add_child(dialog)
	var options: Array[Dictionary] = [{"id": "z", "name": "Zeta", "level": 1}, {"id": "a", "name": "Alpha", "level": 2}, {"id": "b", "name": "Beta", "level": 0}]
	dialog.choose(options, {"class_spell_ids": ["z", "b"], "selected": ["a"]}, func(_result: Dictionary) -> void: pass)
	assert(dialog._checks.size() == 2 and not dialog._checks.has("a"))
	assert(dialog._selected.has("a"), "Filtering must preserve selections outside the class list")
	dialog._class_only.button_pressed = false
	assert(dialog._checks.size() == 3)
	assert(dialog._catalog[0].id == "a")
	dialog._sort.select(1)
	dialog._rebuild()
	assert(dialog._catalog[0].id == "b" and dialog._catalog[2].id == "a")
	dialog._sort.select(2)
	dialog._rebuild()
	assert(dialog._catalog[0].id == "a")
	dialog._class_only.button_pressed = true
	assert(dialog._selected.has("a"))
	dialog.hide()
	var casting := Casting.new()
	root.add_child(casting)
	casting.setup(func(_value: Dictionary) -> void: pass, Callable(), func(_spell: Dictionary, _level: int) -> bool: return true)
	casting.load_record({"spell_slots_total": [0, 2, 0, 0, 0, 0, 0, 0, 0, 0]})
	casting._request_cast_spell_for_grant({"id": "description-test", "name": "Test", "level": 1, "description": "A long spell description.\nAt higher levels: test."}, {"payment_mode": "slot"})
	await process_frame
	await process_frame
	assert(casting._cast_dialog.visible and casting._cast_description.text.contains("At higher levels"))
	assert(casting._cast_dialog.size.y <= root.get_visible_rect().size.y, "Cast dialog must fit the viewport")
	assert(casting._cast_dialog.dialog_text.is_empty() and not casting._cast_dialog.get_label().visible)
	assert(casting._cast_prompt.get_global_rect().end.y <= casting._cast_description.get_global_rect().position.y, "Cast prompt and description must not overlap")
	assert(casting._cast_description.get_global_rect().end.y <= casting._cast_slot_choice.get_global_rect().position.y, "Description and slot selection must not overlap")
	
	assert(casting._cast_slot_choice.get_global_rect().end.y <= casting._cast_dialog.get_ok_button().get_global_rect().position.y, "Slot selection must remain above confirmation buttons")
	assert(casting._spent[1] == 0, "Opening the description must not consume a slot")
	casting._cast_dialog.hide()
	casting._view_edit_class(members[1])
	assert(casting._selection_dialog._class_only.button_pressed)
	assert(casting._selection_dialog._catalog.size() > casting._selection_dialog._class_spell_ids.size())
	casting._selection_dialog.hide()
	casting._view_edit_manual()
	assert(casting._selection_dialog._class_only.visible and not casting._selection_dialog._class_only.button_pressed)
	casting._selection_dialog.hide()
	casting.queue_free()
	dialog.queue_free()
	await process_frame
	print("PASS: cast description, class filter, sorting, preserved selections and 2014/2024 multiclass slots")
	quit()