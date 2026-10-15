extends RefCounted

# Shared creature-sheet mutations. No UI controls, scene tree, Node3D or
# network dependency. Operates on an already detached mutable record; callers
# are responsible for saving through CreatureArchive and refreshing their UI.
const Rules = preload("res://vtt/creature_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const AttackData = preload("res://vtt/creature_attack_data.gd")


static func set_condition(record: Dictionary, id: String, enabled: bool) -> void:
	var active: Array = record.get("conditions", []).duplicate()
	if enabled and id not in active:
		active.append(id)
	elif not enabled:
		active.erase(id)
	if id == "concentrating" and not enabled:
		record["concentrating_spell_id"] = ""
	record["conditions"] = active


static func change_hit_points(record: Dictionary, delta: int) -> void:
	if delta < 0:
		var resolved: Dictionary = Rules.apply_damage_layers(record, -delta)
		record["temporary_hp"] = int(resolved.get("temporary_hp", 0))
		record["second_form_hp"] = int(resolved.get("second_form_hp", 0))
		record["current_hp"] = int(resolved.get("current_hp", 0))
	else:
		record["current_hp"] = mini(
			maxi(0, Bonuses.value(record, "hp")),
			int(record.get("current_hp", 0)) + delta
		)


static func change_tracker(record: Dictionary, id: String, delta: int, maximum: int) -> void:
	var spent: Dictionary = record.get("resource_tracker_spent", {}).duplicate(true)
	spent[id] = clampi(int(spent.get(id, 0)) + delta, 0, maximum)
	record["resource_tracker_spent"] = spent


static func recalculate_bonus_mirrors(record: Dictionary) -> void:
	record["max_hp"] = maxi(0, Bonuses.value(record, "hp"))
	record["armor_class"] = maxi(0, Bonuses.value(record, "ac"))
	record["initiative_base"] = Bonuses.value(record, "ability_mod:dex")
	record["initiative"] = Bonuses.value(record, "initiative")
	record["proficiency_bonus"] = Bonuses.value(record, "proficiency")
	record["speed"] = maxi(0, Bonuses.value(record, "speed"))
	record["reach_feet"] = AttackData.active_range(record)



# Derived progression is a cache of current class/ability data. Never replace
# selected spells, origin choices, or usages when levels/origins change.
static func sync_automatic_progression(record: Dictionary) -> void:
	record["xp"] = maxi(int(record.get("xp", 0)), Rules.minimum_experience(record))
	var has_classes: bool = Rules.class_levels(record) > 0
	record["hit_dice"] = Rules.automatic_hit_dice(record) if has_classes else ""
	if not has_classes:
		record["spellcasting_calculation"] = {}
		if bool(record.get("spell_slots_automatic", false)) and not bool(record.get("spell_slots_manual", false)):
			record["spell_slots_total"] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
			record["spell_slots_spent"] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
			record["pact_slots_total"] = 0
			record["pact_slots_spent"] = 0
		return
	var context: Dictionary = record.duplicate(false)
	var effective: Dictionary = {}
	for ability: String in ["str", "dex", "con", "int", "wis", "cha"]:
		effective[ability] = Bonuses.value(record, "ability_mod:" + ability)
	context["effective_ability_modifiers"] = effective
	record["spellcasting_calculation"] = Rules.spellcasting_limits(context)
	# Keep explicit edits and legacy imported slot totals untouched. Otherwise
	# class progression is authoritative and resource consumption is retained.
	if bool(record.get("spell_slots_manual", false)):
		return
	var previous: Array = record.get("spell_slots_total", [])
	var has_legacy_totals: bool = false
	if previous is Array:
		for raw: Variant in previous:
			has_legacy_totals = has_legacy_totals or int(raw) > 0
	if has_legacy_totals and not bool(record.get("spell_slots_automatic", false)):
		return
	var progression: Dictionary = Rules.spell_slot_progression(record)
	var totals: Array = progression.get("slots", []).duplicate()
	if totals.size() < 10:
		return
	record["spell_slots_total"] = totals
	var spent: Array = record.get("spell_slots_spent", []).duplicate()
	while spent.size() < 10:
		spent.append(0)
	for index: int in range(1, 10):
		spent[index] = clampi(int(spent[index]), 0,
			maxi(0, Bonuses.add(record, "slot:" + str(index), int(totals[index]))))
	record["spell_slots_spent"] = spent
	record["pact_slots_total"] = int(progression.get("pact_total", 0))
	record["pact_slot_level"] = int(progression.get("pact_level", 1))
	record["pact_slots_spent"] = clampi(int(record.get("pact_slots_spent", 0)),
		0, maxi(0, Bonuses.add(record, "pact_slot", int(record["pact_slots_total"]))))
	record["spell_slots_automatic"] = true


static func sync_origin_resources(record: Dictionary) -> void:
	var spent: Dictionary = record.get("resource_tracker_spent", {}).duplicate(true)
	for tracker: Dictionary in Trackers.for_creature(record):
		var id: String = String(tracker.get("id", ""))
		if spent.has(id):
			spent[id] = clampi(int(spent[id]), 0,
				maxi(0, Bonuses.add(record, "tracker:" + id, int(tracker.get("max", 0)))))
	record["resource_tracker_spent"] = spent


static func update_bonuses(
	record: Dictionary, rows: Array, origins: Array,
	feats: Array = [], dice_rows: Array = []
) -> void:
	record["formula_bonuses"] = rows.duplicate(true)
	record["dice_bonuses"] = dice_rows.duplicate(true)
	record["proficiency_origins"] = origins.duplicate(true)
	if not feats.is_empty():
		record["feats_catalog"] = feats.duplicate(true)
	Proficiencies.reconcile_origin_dependents(record)
	recalculate_bonus_mirrors(record)


static func update_trackers(record: Dictionary, trackers: Array, origins: Array) -> void:
	# Tracker editors expose a filtered origin list. Merge rather than
	# discarding origins created by the feat, bonus or proficiency editors.
	var merged: Dictionary = {}
	for source: Variant in record.get("proficiency_origins", []):
		if source is Dictionary:
			merged[String(source.get("id", ""))] = (source as Dictionary).duplicate(true)
	for source: Variant in origins:
		if source is Dictionary:
			merged[String(source.get("id", ""))] = (source as Dictionary).duplicate(true)
	record["proficiency_origins"] = merged.values()
	record["resource_trackers"] = trackers.duplicate(true)
	Proficiencies.reconcile_origin_dependents(record)
	var spent: Dictionary = record.get("resource_tracker_spent", {}).duplicate(true)
	var valid: Dictionary = {}
	for tracker: Dictionary in Trackers.for_creature(record):
		var tracker_id: String = String(tracker.get("id", ""))
		valid[tracker_id] = true
		var cap: int = maxi(0, Bonuses.add(
			record, "tracker:" + tracker_id, int(tracker.get("max", 0))
		))
		if spent.has(tracker_id):
			spent[tracker_id] = clampi(int(spent[tracker_id]), 0, cap)
	for id: String in spent.keys():
		if not valid.has(id):
			spent.erase(id)
	record["resource_tracker_spent"] = spent


static func update_origin_spells(record: Dictionary, grants: Array, configs: Dictionary) -> void:
	record["origin_spell_grants"] = grants.duplicate(true)
	record["origin_spell_configs"] = configs.duplicate(true)
	Proficiencies.reconcile_origin_dependents(record)
