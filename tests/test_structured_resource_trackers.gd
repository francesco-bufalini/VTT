extends SceneTree
# Offline-only regression: no local server and no HTTP.
const Trackers = preload("res://vtt/structured_resource_trackers.gd")


func _initialize() -> void:
	call_deferred("run")


func _find_resource(trackers: Array[Dictionary], resource_name: String) -> Dictionary:
	for tracker: Dictionary in trackers:
		if String(tracker.get("name", "")) == resource_name:
			return tracker
	return {}


func run() -> void:
	var barbarian: Array[Dictionary] = Trackers.for_creature({
		"kind": "character",
		"classes": [{"name": "Barbarian", "source": "PHB", "level": 3}]
	})
	assert(int(_find_resource(barbarian, "Ira").get("max", 0)) == 3)
	assert(String(_find_resource(barbarian, "Ira").get("origin", "")) == "Rage")
	assert(Trackers.for_creature({
		"kind": "character",
		"classes": [{"name": "Barbarian", "source": "PHB", "level": 20}]
	}).is_empty(), "Unlimited Rage must not become a finite counter")

	var druid_first: Array[Dictionary] = Trackers.for_creature({
		"kind": "character",
		"classes": [{"name": "Druid", "source": "XPHB", "level": 1}]
	})
	assert(druid_first.is_empty(), "No Wild Shape until its feature is unlocked")
	var druid_second: Array[Dictionary] = Trackers.for_creature({
		"kind": "character",
		"classes": [{"name": "Druid", "source": "XPHB", "level": 2}]
	})
	assert(int(_find_resource(druid_second, "Forma Selvatica").get("max", 0)) == 2)
	assert(Trackers.for_creature({
		"kind": "character",
		"classes": [{"name": "Druid", "source": "PHB", "level": 2}]
	}).is_empty(), "2014 Wild Shape count is prose, not a numeric table column")

	var mixed: Array[Dictionary] = Trackers.for_creature({
		"kind": "character", "level": 12,
		"classes": [
			{"name": "Monk", "source": "PHB", "level": 5},
			{"name": "Sorcerer", "source": "XPHB", "level": 7}
		]
	})
	assert(int(_find_resource(mixed, "Punti Ki").get("max", 0)) == 5)
	assert(int(_find_resource(mixed, "Punti Stregoneria").get("max", 0)) == 7)
	assert(mixed.size() == 2, "Each resource is tied to its class level")

	var monster: Array[Dictionary] = Trackers.for_creature({
		"kind": "monster",
		"stat_block": {
			"legendaryActions": 2,
			"trait": [
				{"name": "Legendary Resistance (3/Day)", "entries": ["Text limit"]},
				{"name": "Ability (Recharges after a Short or Long Rest)", "entries": []}
			],
			"action": [
				{"name": "Flame Breath {@recharge 5}", "entries": []},
				{"name": "Shadow Breath {@recharge}", "entries": []}
			],
			"spellcasting": [{"daily": {"1": ["some spell"]}}]
		}
	})
	assert(monster.size() == 3, "No counters from natural prose or spellcasting")
	assert(int(_find_resource(monster, "Azioni leggendarie").get("max", 0)) == 2)
	assert(int(_find_resource(monster, "Flame Breath").get("recharge_min", 0)) == 5)
	assert(int(_find_resource(monster, "Shadow Breath").get("recharge_min", 0)) == 6)
	assert(_find_resource(monster, "Legendary Resistance").is_empty())
	print("Structured 5etools resource trackers: PASS")
	quit()
