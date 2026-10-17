extends SceneTree
const Actions = preload("res://vtt/creature_action_economy_tab.gd")
func _initialize() -> void: call_deferred("run")
func find(rows: Array[Dictionary], id: String) -> Dictionary:
	for row: Dictionary in rows:
		if row.get("id", "") == id: return row
	return {}
func run() -> void:
	var base := Actions.entries({"rules_version": "2014"})
	assert(not find(base, "dash").is_empty())
	assert(find(base, "dash")["detail"].begins_with("When you take the Dash action"))
	assert(find(base, "disarm").is_empty(), "Variants must be opt-in")
	assert(find(base, "shove")["parent_action"] == "attack")
	assert(find(base, "grapple")["parent_action"] == "attack")
	assert(find(base, "prone")["action_id"] == "prone")
	assert(find(base, "movement")["time"] == 3)
	var enabled := Actions.entries({"rules_version": "2014"}, ["disarm_dmg", "shove_aside_dmg", "overrun_dmg", "tumble_dmg"])
	assert(find(enabled, "disarm")["parent_action"] == "attack")
	assert(find(enabled, "shove_aside")["parent_action"] == "attack")
	for id: String in ["overrun", "tumble"]:
		assert(find(enabled, id)["time"] == 1 and find(enabled, id)["alternate_action"])
		var count := 0
		for row: Dictionary in enabled:
			if row.get("id", "") == id: count += 1
		assert(count == 1)
	var rogue := Actions.entries({"rules_version": "2014", "kind": "character", "class": "Rogue", "class_source": "PHB", "level": 2})
	for id: String in ["dash", "hide", "disengage"]:
		assert(find(rogue, id)["time"] == 1 and find(rogue, id)["alternate_action"])
		var count := 0
		for row: Dictionary in rogue:
			if row.get("id", "") == id: count += 1
		assert(count == 1, "Cunning Action must replace the standard presentation")
	var typed := Actions.entries({"rules_version": "2014", "action_grants": [{"id": "typed", "name": "Capacità", "action_type": [{"unit": "action"}, {"unit": "bonus"}], "description": "Testo esatto del privilegio"}]})
	assert(find(typed, "typed")["time"] == 1 and find(typed, "typed")["alternate_action"])
	var separate := Actions.entries({"rules_version": "2014", "action_grants": [
		{"id": "paid", "name": "Capacità", "action_type": "action", "tracker_id": "first"},
		{"id": "paid", "name": "Capacità", "action_type": "bonus", "tracker_id": "second"}]})
	var paid := 0
	for row: Dictionary in separate:
		if row.get("id") == "paid": paid += 1
	assert(paid == 2, "Different payments must not be collapsed into one action")
	var wizard := Actions.entries({"rules_version": "2014", "prepared_spells": [{"id": "fixture", "name": "Fireball", "level": 3, "time": "action"}]})
	for row: Dictionary in wizard:
		assert(row.get("kind", "") != "Incantesimo" and row.get("name", "") != "Lanciare un incantesimo")
	var main := {"id": "fixture_main", "name": "Shortsword", "source": "PHB", "type": "M", "weapon_category": "martial", "damage": "1d6", "properties": ["L", "F"], "equipped_slots": ["main"], "quantity": 1}
	var off := main.duplicate(true)
	off["id"] = "fixture_off"
	off["equipped_slots"] = ["off"]
	var weapons := Actions.entries({"rules_version": "2014", "kind": "character", "inventory": [main, off]})
	var count := 0
	for row: Dictionary in weapons:
		if row.get("attack_id", "") == "item:fixture_main":
			assert(row["parent_action"] == "attack")
			count += 1
		if row.get("attack_id", "") == "item:off:fixture_off":
			assert(row["parent_action"] == "two_weapon" and row["time"] == 1)
			count += 1
	assert(count == 2)
	print("PASS: source-backed 2014 actions, opt-in variants, alternate costs, nested attacks and no spells")
	quit(0)
