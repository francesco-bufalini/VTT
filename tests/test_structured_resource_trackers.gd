extends SceneTree
# Offline-only regression: no local server and no HTTP.
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const Classes = preload("res://vtt/structured_class_mechanics.gd")
const Rules = preload("res://vtt/creature_rules.gd")
const Locale = preload("res://vtt/creature_gui_locale.gd")


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
	assert(int(_find_resource(barbarian, "Rages").get("max", 0)) == 3)
	assert(String(_find_resource(barbarian, "Rages").get("origin", "")) == "Rage")
	assert(String(_find_resource(barbarian, "Rages").get("id", "")) == "class:barbarian:phb:rages",
		"Stable resource IDs must preserve already-spent rage uses")
	assert(Locale.text_for("Rages", "it") == "Ira" and Locale.text_for("Rages", "en") == "Rages",
		"Localized name must not be stored in structured resource data")
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
	assert(int(_find_resource(druid_second, "Wild Shape").get("max", 0)) == 2)
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
	assert(int(_find_resource(mixed, "Ki Points").get("max", 0)) == 5)
	assert(int(_find_resource(mixed, "Sorcery Points").get("max", 0)) == 7)
	assert(mixed.size() == 2, "Each resource is tied to its class level")

	# Every former hand-curated resource progression is reproduced from raw
	# class table columns, without a class-to-feature mapping.
	for reference: Array in [
		["Barbarian", "PHB", "Rages", "Rage", 9, 4],
		["Barbarian", "XPHB", "Rages", "Rage", 20, 6],
		["Cleric", "XPHB", "Channel Divinity", "Channel Divinity", 18, 4],
		["Druid", "XPHB", "Wild Shape", "Wild Shape", 18, 4],
		["Fighter", "XPHB", "Second Wind", "Second Wind", 10, 4],
		["Monk", "PHB", "Ki Points", "Ki", 10, 10],
		["Monk", "XPHB", "Focus Points", "Monk's Focus", 10, 10],
		["Paladin", "XPHB", "Channel Divinity", "Channel Divinity", 11, 3],
		["Sorcerer", "PHB", "Sorcery Points", "Font of Magic", 10, 10],
		["Sorcerer", "XPHB", "Sorcery Points", "Font of Magic", 10, 10]
	]:
		var resource: Dictionary = _find_resource(Trackers.for_creature({
			"kind": "character",
			"classes": [{"name": reference[0], "source": reference[1], "level": reference[4]}]
		}), String(reference[2]))
		assert(int(resource.get("max", 0)) == int(reference[5])
			and String(resource.get("origin", "")) == String(reference[3]),
			"5etools class table and feature link regression: " + str(reference))
	var rage_class := Classes.class_definition("Barbarian", "PHB")
	assert(Classes.resource_columns(rage_class).size() == 1,
		"Typed Rage Damage bonus must never become a resource counter")
	var rage_damage: Dictionary = {}
	for column: Dictionary in rage_class.get("columns", []):
		if String(column.get("name", "")) == "Rage Damage":
			rage_damage = column
	assert(not rage_damage.is_empty()
		and rage_damage["levels"][8] is Dictionary
		and int(rage_damage["levels"][8].get("value", -1)) == 3,
		"Structured Rage Damage progressions remain available without interpreting prose")
	assert(Classes.resource_columns(Classes.class_definition("Barbarian", "XPHB")).size() == 1,
		"Weapon Mastery selection capacity must not be treated as expendable")
	assert(Classes.resource_columns(Classes.class_definition("Artificer", "TCE")).is_empty(),
		"Infused Items represent a capacity, not a spent resource")
	assert(Classes.resource_columns(Classes.class_definition("Ranger", "XPHB")).is_empty(),
		"Spell-related Favored Enemy capacity is not a nonspell tracker")
	assert(Classes.hit_die("Barbarian", "PHB") == 12
		and Classes.hit_die("Fighter", "XPHB") == 10
		and Classes.hit_die("Wizard", "PHB") == 6
		and Classes.hit_die("Artificer", "TCE") == 8,
		"Hit dice must come from structured hd.faces, not a handwritten table")
	assert(Rules.automatic_hit_dice({"classes": [{"name": "Barbarian", "source": "PHB", "level": 3}]}) == "3d12 (Barbarian)",
		"Hit die displays must keep their old format")
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
	print("PASS: structured 5etools resource trackers and class-mechanics parity")
	quit()
