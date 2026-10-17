extends SceneTree
const Mechanics = preload("res://vtt/feature_timing_recovery_rules.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const Actions = preload("res://vtt/creature_action_economy_tab.gd")

func _initialize() -> void:
	call_deferred("run")

func _sheet(name: String, edition: String, level: int, subclass: String = "") -> Dictionary:
	return {
		"kind": "character", "class": name, "rules_version": edition,
		"class_source": "XPHB" if edition == "2024" else "PHB",
		"level": level, "subclass": subclass,
		"abilities": {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 16, "cha": 16}
	}

func _tracker(record: Dictionary, name: String) -> Dictionary:
	for row: Dictionary in Trackers.for_creature(record):
		if String(row.get("name", "")) == name:
			return row
	return {}

func _time(record: Dictionary, action: String) -> int:
	for row: Dictionary in Actions.entries(record):
		if String(row.get("name", "")) == action:
			return int(row.get("time", -1))
	return -1

func run() -> void:
	var druid := _sheet("Druid", "2014", 2)
	assert(_time(druid, "Forma selvatica") == 0)
	assert(_time(_sheet("Druid", "2014", 2, "Circle of the Moon"), "Forma selvatica") == 1)
	assert(_time(_sheet("Druid", "2024", 2), "Forma selvatica") == 1)
	assert(_time(_sheet("Druid", "2014", 1), "Forma selvatica") == -1)
	assert(_time(_sheet("Rogue", "2014", 2), "Scattare (azione scaltra)") == 1)
	assert(_time(_sheet("Rogue", "2024", 3, "Thief"), "Utilizzare (Mani veloci)") == 1)
	assert(_time(_sheet("Ranger", "2014", 14), "Nascondersi (Svanire)") == 1)

	for kind: String in ["Barbarian", "Cleric", "Druid", "Fighter", "Paladin"]:
		var level := 3
		var name: String = String({"Barbarian": "Rages", "Cleric": "Channel Divinity",
			"Druid": "Wild Shape", "Fighter": "Second Wind", "Paladin": "Channel Divinity"}[kind])
		var record := _sheet(kind, "2024", level)
		var tracker := _tracker(record, name)
		assert(not tracker.is_empty(), kind + ": missing class resource")
		assert(String(tracker.get("recharge", "")) == "long_rest", kind + ": full reset is long rest")
		var id := String(tracker.get("id", ""))
		record["resource_tracker_spent"] = {id: mini(2, int(tracker.get("max", 1)))}
		var short_patch: Dictionary = Trackers.recovery_patch(record, "short_rest")
		assert(int((short_patch.get("resource_tracker_spent", {}) as Dictionary).get(id, 0)) ==
			maxi(0, int(record["resource_tracker_spent"][id]) - 1))
		var long_patch: Dictionary = Trackers.recovery_patch(record, "long_rest")
		assert(not (long_patch.get("resource_tracker_spent", {}) as Dictionary).has(id))

	var early := _tracker(_sheet("Bard", "2014", 4), "Bardic Inspiration")
	var later := _tracker(_sheet("Bard", "2014", 5), "Bardic Inspiration")
	assert(String(early.get("recharge", "")) == "long_rest")
	assert(String(later.get("recharge", "")) == "short_rest")

	var sorcerer := _sheet("Sorcerer", "2024", 7)
	var sorc_tracker := _tracker(sorcerer, "Sorcery Points")
	assert(not sorc_tracker.is_empty())
	var tracker_id := String(sorc_tracker.get("id", ""))
	sorcerer["resource_tracker_spent"] = {tracker_id: 6}
	var after_rest := Trackers.recovery_patch(sorcerer, "short_rest")
	assert(int((after_rest["resource_tracker_spent"] as Dictionary).get(tracker_id, 0)) == 6)
	var ready: Dictionary = after_rest["resource_recovery_ready"]
	assert(ready.size() == 1)
	var rule_id := String(ready.keys()[0])
	var available := sorcerer.merged(after_rest, true)
	var choice: Dictionary = Trackers.optional_recovery_patch(available, rule_id)
	assert(int((choice["resource_tracker_spent"] as Dictionary).get(tracker_id, 0)) == 3)
	assert(Trackers.optional_recovery_patch(available.merged(choice, true), rule_id).is_empty())
	var long_rest := Trackers.recovery_patch(available.merged(choice, true), "long_rest")
	assert((long_rest["resource_recovery_used"] as Dictionary).is_empty())
	assert((long_rest["resource_recovery_ready"] as Dictionary).is_empty())
	print("PASS: typed feature activation, partial reset and optional recovery")
	quit(0)
