extends SceneTree
# Offline-only regression: no local server and no HTTP.
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const ClassMechanics = preload("res://vtt/class_mechanics_5etools.gd")
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
	var rage: Dictionary = _find_resource(barbarian, "Rages")
	assert(int(rage.get("max", 0)) == 3 and String(rage.get("origin", "")) == "Rage")
	assert(String(rage.get("id", "")) == "class:barbarian:phb:rages",
		"Stored resource use keys must survive table regeneration")
	assert(Locale.text_for("Rages", "it") == "Ira"
		and Locale.text_for("Rages", "en") == "Rages",
		"Translation must be in GUI locale, never in mechanics data")
	assert(ClassMechanics.column_value("Barbarian", "PHB", "Rage Damage", 9) == 3
		and ClassMechanics.column("Barbarian", "PHB", "Rage Damage").get("kind") == "bonus",
		"Typed bonus column is available but must never become a spent resource")
	assert(ClassMechanics.column_value("Barbarian", "PHB", "Rages", 20) == "unlimited",
		"Non-numeric cap must remain identifiable without inventing a finite value")
	assert(ClassMechanics.hit_die("Barbarian", "PHB") == 12
		and ClassMechanics.hit_die("Wizard", "XPHB") == 6
		and ClassMechanics.hit_die("Fighter", "") == 10
		and ClassMechanics.hit_die("unknown", "") == 0,
		"Hit dice must come from 5etools hd.faces and retain legacy source fallback")
	assert(ClassMechanics.resource_columns("Ranger", "XPHB").is_empty(),
		"Favored Enemy and Weapon Mastery capacities are not spent-resource trackers")
	var hit_die_record := {
		"kind": "character", "classes": [{"name": "Barbarian", "source": "PHB", "level": 3}],
		"abilities": {"con": 10}
	}
	assert(Rules.automatic_hit_dice(hit_die_record) == "3d12 (Barbarian)",
		"Hit dice display must remain compatible with the previous formula")
	assert(int(Rules.automatic_hit_points(hit_die_record).get("value", 0)) == 26,
		"HP formula must retain max first level and 7 average on following d12s")
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
	assert(String(_find_resource(mixed, "Sorcery Points").get("origin", "")) == "Font of Magic",
		"Structured class feature association for sorcery points must be preserved")
	# Legacy sheets lacking an explicit edition must use the resolved
	# class edition in resource IDs and labels, not an empty source.
	var legacy_barbarian: Dictionary = _find_resource(Trackers.for_creature({
		"kind": "character",
		"classes": [{"name": "Barbarian", "level": 3}]
	}), "Rages")
	assert(String(legacy_barbarian.get("id", "")) == "class:barbarian:phb:rages")
	assert(String(legacy_barbarian.get("source_label", "")) == "Barbarian · PHB")

	# Parity with all ten former hand-maintained class progressions. A raw
	# table import must not change their numerical limits or feature origins.
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
		var derived: Dictionary = _find_resource(Trackers.for_creature({
			"kind": "character",
			"classes": [{"name": reference[0], "source": reference[1], "level": reference[4]}]
		}), String(reference[2]))
		assert(int(derived.get("max", 0)) == int(reference[5])
			and String(derived.get("origin", "")) == String(reference[3]),
			"Structured class resource regression: " + str(reference))

	var druid_locale := Locale.text_for("Wild Shape", "it")
	assert(druid_locale == "Forma Selvatica")
	var cleric: Array[Dictionary] = Trackers.for_creature({
		"kind": "character", "classes": [{"name": "Cleric", "source": "XPHB", "level": 2}]
	})
	assert(int(_find_resource(cleric, "Channel Divinity").get("max", 0)) == 2)
	var fighter: Array[Dictionary] = Trackers.for_creature({
		"kind": "character", "classes": [{"name": "Fighter", "source": "XPHB", "level": 4}]
	})
	assert(int(_find_resource(fighter, "Second Wind").get("max", 0)) == 3)

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
	print("PASS: structured 5etools resource trackers")
	quit()
