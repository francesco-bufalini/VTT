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
	var druid_tracker := _tracker(druid, "Wild Shape")
	assert(String(druid_tracker.get("origin_id", "")).begins_with("feature:class|phb|druid|"))
	var disabled := druid.duplicate(true)
	disabled["origin_enabled"] = {String(druid_tracker.origin_id): false}
	disabled["resource_tracker_spent"] = {String(druid_tracker.id): 1}
	assert(_time(disabled, "Forma selvatica") == -1)
	assert(bool(_tracker(disabled, "Wild Shape").get("disabled", false)))
	assert(int(disabled.resource_tracker_spent[druid_tracker.id]) == 1)
	var sorc_actions := Actions.entries(_sheet("Sorcerer", "2014", 5))
	var conversions := 0
	for action: Dictionary in sorc_actions:
		assert(String(action.get("name", "")) != "Conversione slot e punti stregoneria", "A descriptive override must not duplicate the executable trait")
		if action.get("class_feature_id", "") == "class_feature:font_of_magic": conversions += 1
	assert(conversions == 1)
	assert(_time(_sheet("Rogue", "2014", 2), "Scattare") == 1)
	assert(_time(_sheet("Rogue", "2024", 3, "Thief"), "Utilizzare") == 1)
	assert(_time(_sheet("Ranger", "2014", 14), "Nascondersi") == 1)
	var nature := _sheet("Cleric", "2014", 17, "Nature")
	var tempest := _sheet("Cleric", "2014", 17, "Tempest")
	var nature_actions := Mechanics.action_entries(nature, Trackers.for_creature(nature))
	var tempest_actions := Mechanics.action_entries(tempest, Trackers.for_creature(tempest))
	assert(nature_actions.size() == 3)
	assert(tempest_actions.size() == 2)
	assert(String(nature_actions[0].get("activation", "")) == "action")
	assert(String(nature_actions[0].get("tracker_id", "")) == String(_tracker(nature, "Channel Divinity").get("id", "")))
	assert(String(tempest_actions[0].get("activation", "")) == "reaction")
	assert(String(tempest_actions[0].get("tracker_id", "")) == String(_tracker(tempest, "Wrath of the Storm").get("id", "")))
	assert(String(tempest_actions[1].get("tracker_id", "")) == String(_tracker(tempest, "Channel Divinity").get("id", "")))
	assert(Mechanics.action_entries(_sheet("Cleric", "2024", 17, "Tempest"), []).is_empty())
	var undying := _sheet("Warlock", "2014", 14, "The Undying")
	var defy_death := _tracker(undying, "Defy Death")
	var indestructible_life := _tracker(undying, "Indestructible Life")
	assert(int(defy_death.get("max", 0)) == 1)
	assert(String(defy_death.get("recharge", "")) == "long_rest")
	assert(int(indestructible_life.get("max", 0)) == 1)
	assert(String(indestructible_life.get("recharge", "")) == "short_rest")
	assert(String(defy_death.get("origin_id", "")).contains("|subclass|"))
	assert(_tracker(_sheet("Warlock", "2014", 14, "The Fiend"), "Defy Death").is_empty())
	var undying_actions := Mechanics.action_entries(undying, Trackers.for_creature(undying))
	assert(undying_actions.size() == 1)
	assert(String(undying_actions[0].get("activation", "")) == "bonus")
	assert(String(undying_actions[0].get("tracker_id", "")) == String(indestructible_life.get("id", "")))
	var long_death := _sheet("Monk", "2014", 6, "Long Death")
	var reaping := Mechanics.action_entries(long_death, Trackers.for_creature(long_death))
	assert(reaping.size() == 1)
	assert(String(reaping[0].get("activation", "")) == "action")
	var crown := _sheet("Paladin", "2014", 20, "Oath of the Crown")
	var crown_tracker := _tracker(crown, "Exalted Champion")
	assert(int(crown_tracker.get("max", 0)) == 1)
	assert(String(crown_tracker.get("recharge", "")) == "long_rest")
	var crown_actions := Mechanics.action_entries(crown, Trackers.for_creature(crown))
	assert(crown_actions.size() == 4)
	assert(String(crown_actions[3].get("tracker_id", "")) == String(crown_tracker.get("id", "")))
	assert(_tracker(_sheet("Paladin", "2014", 20, "Oath of Devotion"), "Exalted Champion").is_empty())
	var samurai := _sheet("Fighter", "2014", 18, "Samurai")
	assert(int(_tracker(samurai, "Fighting Spirit").get("max", 0)) == 3)
	assert(int(_tracker(samurai, "Strength before Death").get("max", 0)) == 1)
	var samurai_actions := Mechanics.action_entries(samurai, Trackers.for_creature(samurai))
	assert(samurai_actions.size() == 2)
	assert(String(samurai_actions[0].get("activation", "")) == "bonus")
	var cavalier := _sheet("Fighter", "2014", 7, "Cavalier")
	cavalier["abilities"]["str"] = 16
	cavalier["abilities"]["con"] = 16
	assert(int(_tracker(cavalier, "Unwavering Mark (Special Attack)").get("max", 0)) == 3)
	assert(int(_tracker(cavalier, "Warding Maneuver").get("max", 0)) == 3)
	assert(Mechanics.action_entries(cavalier, Trackers.for_creature(cavalier)).size() == 1)
	var dreams := _sheet("Druid", "2014", 14, "Circle of Dreams")
	assert(int(_tracker(dreams, "Balm of the Summer Court").get("max", 0)) == 14)
	assert(int(_tracker(dreams, "Hidden Paths").get("max", 0)) == 3)
	assert(int(_tracker(dreams, "Walker in Dreams").get("max", 0)) == 1)
	var dreams_actions := Mechanics.action_entries(dreams, Trackers.for_creature(dreams))
	assert(dreams_actions.size() == 3, "Two paths plus base Wild Shape")
	var multiclass_dreams := _sheet("Druid", "2014", 15, "Circle of Dreams")
	multiclass_dreams["classes"] = [
		{"name": "Druid", "source": "PHB", "level": 10, "subclass": "Circle of Dreams", "subclass_source": "XGE"},
		{"name": "Fighter", "source": "PHB", "level": 5}
	]
	assert(int(_tracker(multiclass_dreams, "Balm of the Summer Court").get("max", 0)) == 10)
	var shepherd := _sheet("Druid", "2014", 14, "Circle of the Shepherd")
	assert(String(_tracker(shepherd, "Spirit Totem").get("recharge", "")) == "short_rest")
	assert(int(_tracker(shepherd, "Faithful Summons").get("max", 0)) == 1)

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
