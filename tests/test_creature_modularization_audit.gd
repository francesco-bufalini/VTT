extends SceneTree

# Compare the board-independent mutators with the implementations which were
# in CreatureArea before PR #88. This test does not create UI or a 3D board.
const Controller = preload("res://vtt/creature_sheet_controller.gd")
const Rules = preload("res://vtt/creature_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Profs = preload("res://vtt/creature_proficiency_rules.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const AttackData = preload("res://vtt/creature_attack_data.gd")


func _initialize() -> void:
	call_deferred("run")


func _check(value: bool, detail: String) -> bool:
	if not value:
		push_error("REGRESSION: " + detail)
		quit(1)
	return value


func _legacy_mirrors(record: Dictionary) -> void:
	record["max_hp"] = maxi(0, Bonuses.value(record, "hp"))
	record["armor_class"] = maxi(0, Bonuses.value(record, "ac"))
	record["initiative_base"] = Bonuses.value(record, "ability_mod:dex")
	record["initiative"] = Bonuses.value(record, "initiative")
	record["proficiency_bonus"] = Bonuses.value(record, "proficiency")
	record["speed"] = maxi(0, Bonuses.value(record, "speed"))
	record["reach_feet"] = AttackData.active_range(record)


func _legacy_trackers(record: Dictionary, trackers: Array, origins: Array) -> void:
	var merged: Dictionary = {}
	for source: Variant in record.get("proficiency_origins", []):
		if source is Dictionary:
			merged[String(source.get("id", ""))] = (source as Dictionary).duplicate(true)
	for source: Variant in origins:
		if source is Dictionary:
			merged[String(source.get("id", ""))] = (source as Dictionary).duplicate(true)
	record["proficiency_origins"] = merged.values()
	record["resource_trackers"] = trackers.duplicate(true)
	Profs.reconcile_origin_dependents(record)
	var spent: Dictionary = record.get("resource_tracker_spent", {}).duplicate(true)
	var valid: Dictionary = {}
	for tracker: Dictionary in Trackers.for_creature(record):
		var tid: String = String(tracker.get("id", ""))
		valid[tid] = true
		var cap: int = maxi(0, Bonuses.add(record, "tracker:" + tid, int(tracker.get("max", 0))))
		if spent.has(tid):
			spent[tid] = clampi(int(spent[tid]), 0, cap)
	for id: String in spent.keys():
		if not valid.has(id):
			spent.erase(id)
	record["resource_tracker_spent"] = spent


func run() -> void:
	var checks := 0
	for current: int in [0, 1, 9, 20, 30]:
		for temporary: int in [0, 3, 17]:
			for second_form: int in [0, 7, 22]:
				for damage: int in [-50, -20, -8, -1, 0, 1, 4, 40]:
					var sheet: Dictionary = {
						"kind": "character", "level": 3,
						"current_hp": current, "temporary_hp": temporary,
						"second_form_hp": second_form, "second_form_max_hp": 22,
						"max_hp_base": 30, "max_hp": 30
					}
					var expected: Dictionary = sheet.duplicate(true)
					if damage < 0:
						var resolved: Dictionary = Rules.apply_damage_layers(expected, -damage)
						for key: String in ["temporary_hp", "second_form_hp", "current_hp"]:
							expected[key] = int(resolved.get(key, 0))
					else:
						expected["current_hp"] = mini(maxi(0, Bonuses.value(expected, "hp")), int(expected["current_hp"]) + damage)
					Controller.change_hit_points(sheet, damage)
					if not _check(sheet == expected, "Layered PF / cura mismatch: " + str([current, temporary, second_form, damage])):
						return
					checks += 1

	for condition: String in ["prone", "concentrating", "poisoned"]:
		for enabled: bool in [true, false]:
			var record: Dictionary = {"conditions": ["prone", "concentrating"], "concentrating_spell_id": "test"}
			var baseline: Dictionary = record.duplicate(true)
			var active: Array = baseline["conditions"].duplicate()
			if enabled and condition not in active:
				active.append(condition)
			elif not enabled:
				active.erase(condition)
			if condition == "concentrating" and not enabled:
				baseline["concentrating_spell_id"] = ""
			baseline["conditions"] = active
			Controller.set_condition(record, condition, enabled)
			if not _check(record == baseline, "Condition changed semantics: " + condition):
				return
			checks += 1

	for value: int in [-10, 0, 2, 12]:
		var record: Dictionary = {"resource_tracker_spent": {"rage": 2, "other": 4}}
		var baseline: Dictionary = record.duplicate(true)
		var spent: Dictionary = baseline["resource_tracker_spent"].duplicate(true)
		spent["rage"] = clampi(int(spent["rage"]) + value, 0, 4)
		baseline["resource_tracker_spent"] = spent
		Controller.change_tracker(record, "rage", value, 4)
		if not _check(record == baseline, "Tracker consumption mismatch"):
			return
		checks += 1

	for form: int in [0, 1, 3]:
		var record: Dictionary = {
			"kind": "character", "level": 3, "class": "Fighter",
			"max_hp_base": 22, "armor_class_base": 11,
			"proficiency_bonus_base": 2, "speed_base": 30,
			"abilities": {"str": 12, "dex": 14, "con": 14, "int": 10, "wis": 10, "cha": 8},
			"second_form_hp": form, "resource_tracker_spent": {"missing": 3},
			"proficiency_origins": [{"id": "custom:test", "name": "Test", "group": "custom"}]
		}
		var mirror: Dictionary = record.duplicate(true)
		_legacy_mirrors(mirror)
		Controller.recalculate_bonus_mirrors(record)
		if not _check(record == mirror, "Bonus mirrors mismatch"):
			return
		checks += 1
		var expected: Dictionary = record.duplicate(true)
		var choices: Array = [{"id": "custom:extra", "name": "Extra", "group": "custom"}]
		var edited: Array = [{"id": "custom tracker", "name": "Custom", "max": 3, "origin_id": "custom:extra"}]
		_legacy_trackers(expected, edited, choices)
		Controller.update_trackers(record, edited, choices)
		if not _check(record == expected, "Tracker editor reconciles differently"):
			return
		checks += 1

	# Reproduce the UI-to-model bridge with deliberately stale display values.
	# Pre-PR #88 damage always used the saved record's layers, whereas healing
	# started from the SpinBox's displayed base HP.
	var stored: Dictionary = {"kind": "character", "current_hp": 20,
		"temporary_hp": 5, "second_form_hp": 8, "second_form_max_hp": 8,
		"max_hp": 30, "max_hp_base": 30}
	for delta: int in [-22, -8, -2, 0, 2, 18]:
		var ui_hp: int = 3
		var ui_temp: int = 1
		var ui_form: int = 6
		var before_ui: Dictionary = stored.duplicate(true)
		var after_ui: Dictionary = stored.duplicate(true)
		if delta < 0:
			var resolved: Dictionary = Rules.apply_damage_layers(before_ui, -delta)
			before_ui["current_hp"] = resolved["current_hp"]
			before_ui["temporary_hp"] = resolved["temporary_hp"]
			before_ui["second_form_hp"] = resolved["second_form_hp"]
		else:
			before_ui["current_hp"] = mini(maxi(0, Bonuses.value(before_ui, "hp")), ui_hp + delta)
			before_ui["temporary_hp"] = ui_temp
			before_ui["second_form_hp"] = ui_form
		if delta >= 0:
			after_ui["current_hp"] = ui_hp
		Controller.change_hit_points(after_ui, delta)
		if delta >= 0:
			after_ui["temporary_hp"] = ui_temp
			after_ui["second_form_hp"] = ui_form
		for key: String in ["current_hp", "temporary_hp", "second_form_hp"]:
			if not _check(before_ui[key] == after_ui[key],
					"Desktop HP bridge is not backward compatible: " + str([delta, key])):
				return
		checks += 1

	print("PASS: creature domain differential audit (%d comparisons)" % checks)
	quit()
