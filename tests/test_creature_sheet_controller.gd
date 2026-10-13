extends SceneTree

const Controller = preload("res://vtt/creature_sheet_controller.gd")
const Rules = preload("res://vtt/creature_rules.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# The controller requires no scene, CanvasLayer or board. Tests exercise
	# the same mutators used by the desktop creature editor.
	var sheet: Dictionary = {
		"conditions": ["poisoned", "concentrating"],
		"concentrating_spell_id": "spell:test",
		"current_hp": 20,
		"temporary_hp": 5,
		"second_form_hp": 8,
		"second_form_max_hp": 8,
		"max_hp": 30,
		"max_hp_base": 30,
		"resource_tracker_spent": {"rage": 2}
	}
	Controller.set_condition(sheet, "concentrating", false)
	assert(not "concentrating" in sheet["conditions"])
	assert(sheet["concentrating_spell_id"] == "")
	Controller.set_condition(sheet, "poisoned", true)
	assert(sheet["conditions"].count("poisoned") == 1)
	Controller.set_condition(sheet, "prone", true)
	assert("prone" in sheet["conditions"])

	var before_damage: Dictionary = sheet.duplicate(true)
	var expected: Dictionary = Rules.apply_damage_layers(before_damage, 17)
	Controller.change_hit_points(sheet, -17)
	for field: String in ["temporary_hp", "second_form_hp", "current_hp"]:
		assert(int(sheet[field]) == int(expected[field]),
			"Layered HP diverges for " + field)
	assert(sheet["current_hp"] == 16)
	Controller.change_hit_points(sheet, 3)
	assert(sheet["current_hp"] == 19)
	Controller.change_tracker(sheet, "rage", 1, 3)
	assert(sheet["resource_tracker_spent"]["rage"] == 3)
	Controller.change_tracker(sheet, "rage", -10, 3)
	assert(sheet["resource_tracker_spent"]["rage"] == 0)

	# Origin spell changes must be copied rather than retaining UI arrays.
	var grants: Array = [{"id": "test", "origin_id": "feature:test", "spell_id": "magic-missile"}]
	var configs: Dictionary = {"feature:test": {"ability": "int"}}
	Controller.update_origin_spells(sheet, grants, configs)
	grants.clear()
	configs.clear()
	assert(sheet["origin_spell_grants"].size() == 1)
	assert(sheet["origin_spell_configs"].has("feature:test"))

	print("PASS: standalone creature controller conditions, HP, trackers, origin spells")
	quit()
