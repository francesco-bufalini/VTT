extends SceneTree
# Offline-only regression: no local server and no HTTP.
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const ClassMechanics = preload("res://vtt/class_mechanics_5etools.gd")
const ResourceOverrides = preload("res://vtt/class_resource_overrides.gd")
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
	assert(Locale.text_for("Rages", "it") == "Rages"
		and Locale.text_for("Rages", "en") == "Rages",
		"Catalog resource names remain unchanged in both GUI languages")
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
	var druid_2014: Dictionary = _find_resource(Trackers.for_creature({
		"kind": "character",
		"classes": [{"name": "Druid", "source": "PHB", "level": 2}]
	}), "Wild Shape")
	assert(int(druid_2014.get("max", 0)) == 2
		and String(druid_2014.get("recharge", "")) == "short_rest",
		"2014 Wild Shape must come from the checked-in Fight Club supplement")

	var mixed: Array[Dictionary] = Trackers.for_creature({
		"kind": "character", "level": 12,
		"classes": [
			{"name": "Monk", "source": "PHB", "level": 5},
			{"name": "Sorcerer", "source": "XPHB", "level": 7}
		]
	})
	assert(int(_find_resource(mixed, "Ki Points").get("max", 0)) == 5)
	assert(int(_find_resource(mixed, "Sorcery Points").get("max", 0)) == 7)
	assert(mixed.size() == 3 and int(_find_resource(mixed, "Innate Sorcery").get("max", 0)) == 2, "Each resource is tied to its class level; 2024 innate sorcery has its own uses")
	assert(String(_find_resource(mixed, "Sorcery Points").get("origin", "")) == "Font of Magic",
		"Structured class feature association for sorcery points must be preserved")
	var revised_multiclass: Array[Dictionary] = Trackers.for_creature({
		"kind": "character", "level": 10,
		"classes": [
			{"name": "Paladin", "source": "XPHB", "level": 3},
			{"name": "Wizard", "source": "XPHB", "level": 7}
		]
	})
	var lay_on_hands: Dictionary = _find_resource(revised_multiclass, "Lay on Hands")
	assert(int(lay_on_hands.get("max", 0)) == 15
		and String(lay_on_hands.get("id", "")) == "class:paladin:xphb:lay_on_hands"
		and String(lay_on_hands.get("origin", "")) == "Lay on Hands"
		and String(lay_on_hands.get("recharge", "")) == "long_rest",
		"Lay on Hands must use Paladin level, retain its spent-use ID and recover on long rest")
	var arcane_recovery: Dictionary = _find_resource(revised_multiclass, "Arcane Recovery")
	assert(int(arcane_recovery.get("max", 0)) == 1
		and String(arcane_recovery.get("id", "")) == "class:wizard:xphb:arcane_recovery"
		and String(arcane_recovery.get("recharge", "")) == "long_rest",
		"2024 Arcane Recovery must remain a once-per-long-rest use")
	assert(String(_find_resource(mixed, "Innate Sorcery").get("id", "")) == "class:sorcerer:xphb:innate_sorcery"
		and String(_find_resource(mixed, "Innate Sorcery").get("recharge", "")) == "long_rest",
		"2024 Innate Sorcery retains its stored use ID and recovery")
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
	assert(druid_locale == "Wild Shape")
	var cleric: Array[Dictionary] = Trackers.for_creature({
		"kind": "character", "classes": [{"name": "Cleric", "source": "XPHB", "level": 2}]
	})
	assert(int(_find_resource(cleric, "Channel Divinity").get("max", 0)) == 2)
	var fighter: Array[Dictionary] = Trackers.for_creature({
		"kind": "character", "classes": [{"name": "Fighter", "source": "XPHB", "level": 4}]
	})
	assert(int(_find_resource(fighter, "Second Wind").get("max", 0)) == 3)
	for example: Array in [[2, 1, 0], [9, 1, 1], [13, 1, 2], [17, 2, 3]]:
		var fighter_resources: Array[Dictionary] = Trackers.for_creature({
			"kind": "character", "classes": [{"name": "Fighter", "source": "XPHB", "level": example[0]}]
		})
		var surge: Dictionary = _find_resource(fighter_resources, "Action Surge")
		var indomitable: Dictionary = _find_resource(fighter_resources, "Indomitable")
		assert(int(surge.get("max", 0)) == example[1]
			and String(surge.get("id", "")) == "class:fighter:xphb:action_surge"
			and String(surge.get("recharge", "")) == "short_rest",
			"Action Surge must keep its spent-use ID and 2024 progression")
		assert(int(indomitable.get("max", 0)) == example[2]
			and (indomitable.is_empty() or (
				String(indomitable.get("id", "")) == "class:fighter:xphb:indomitable"
				and String(indomitable.get("recharge", "")) == "long_rest")),
			"Indomitable must appear only at level 9 and keep its 2024 progression")
	for example: Array in [
		["Warlock", "The Fiend", 6, "Dark One's Own Luck", "class:warlock:phb:dark_one's_luck"],
		["Wizard", "School of Illusion", 10, "Illusory Self", "class:wizard:phb:illusory_step"],
		["Wizard", "School of Divination", 10, "The Third Eye", "class:wizard:phb:third_eye"]
	]:
		var alias_row: Dictionary = _find_resource(Trackers.for_creature({
			"kind": "character", "classes": [{"name": example[0], "source": "PHB",
				"level": example[2], "subclass": example[1]}]
		}), String(example[3]))
		assert(String(alias_row.get("id", "")) == String(example[4])
			and String(alias_row.get("origin", "")) == String(example[3])
			and String(alias_row.get("origin_id", "")).begins_with("feature:")
			and String(alias_row.get("recharge", "")) == "short_rest",
			"Fight Club counter alias must retain stored ID and use the 5etools trait: " + str(example))

	# The runtime accepts only the existing VTT formula symbols, never the
	# Fight Club placeholders consumed by the offline asset generator.
	var sample: Dictionary = {"kind": "character", "level": 3, "abilities": {"cha": 18}}
	assert(ResourceOverrides.evaluate_max("%6", sample, 3).is_empty(),
		"External Fight Club placeholders must not be accepted by the game")
	assert(ResourceOverrides.evaluate_max("1 + %6", sample, 3).is_empty(),
		"Mixed source-native counter expressions must not be interpreted")
	assert(int(ResourceOverrides.evaluate_max("cha_mod", sample, 3).get("max", 0)) == 4,
		"Use the same cha_mod symbol as creature numeric bonuses")
	assert(int(ResourceOverrides.evaluate_max("1 + cha_mod", sample, 3).get("max", 0)) == 5,
		"Native arithmetic formulas should use the ordinary bonus evaluator")
	var integrated: FileAccess = FileAccess.open(
		"res://vtt/data/class_resource_overrides.json", FileAccess.READ)
	assert(integrated != null, "Compiled resource supplement should be bundled locally")
	var supplement: Dictionary = JSON.parse_string(integrated.get_as_text())
	integrated.close()
	for group: Dictionary in supplement.get("classes", []):
		for resource: Dictionary in group.get("resources", []):
			for step: Dictionary in resource.get("steps", []):
				assert(not String(step.get("value", "")).contains("%"),
					"Bundled counter values must not contain Fight Club placeholders")

	# Complementary Fight Club metadata: formulas, recovery progression and
	# subclass gating. No runtime downloads or natural-language parsing.
	var low_cha: Dictionary = _find_resource(Trackers.for_creature({
		"kind": "character", "abilities": {"cha": 8},
		"classes": [{"name": "Bard", "source": "PHB", "level": 1}]
	}), "Bardic Inspiration")
	assert(int(low_cha.get("max", 0)) == 1
		and String(low_cha.get("max_formula", "")) == "cha_mod"
		and String(low_cha.get("recharge", "")) == "long_rest",
		"Ability-modifier counter must respect its minimum and first recharge")
	var high_cha: Dictionary = _find_resource(Trackers.for_creature({
		"kind": "character", "abilities": {"cha": 18},
		"classes": [{"name": "Bard", "source": "PHB", "level": 5}]
	}), "Bardic Inspiration")
	assert(int(high_cha.get("max", 0)) == 4
		and String(high_cha.get("recharge", "")) == "short_rest",
		"Font of Inspiration updates existing counter without duplicating it")
	var bard_2024: Dictionary = _find_resource(Trackers.for_creature({
		"kind": "character", "abilities": {"cha": 16},
		"classes": [{"name": "Bard", "source": "XPHB", "level": 5}]
	}), "Bardic Inspiration")
	assert(int(bard_2024.get("max", 0)) == 3
		and String(bard_2024.get("recharge", "")) == "short_rest",
		"2024 Bardic Inspiration keeps its own edition-specific resource")
	var used_record: Dictionary = {
		"kind": "character", "abilities": {"cha": 16},
		"classes": [{"name": "Bard", "source": "PHB", "level": 1}],
		"resource_trackers": [{"id": "manual_one", "name": "Manual", "max": 2, "recharge": "manual"}],
		"resource_tracker_spent": {"class:bard:phb:bardic_inspiration": 1, "manual_one": 1}
	}
	assert(int(Trackers.spent_after_recovery(used_record, "short_rest").get(
		"class:bard:phb:bardic_inspiration", 0)) == 1,
		"Before Font of Inspiration, a short rest must not replenish uses")
	var after_long: Dictionary = Trackers.spent_after_recovery(used_record, "long_rest")
	assert(not after_long.has("class:bard:phb:bardic_inspiration")
		and int(after_long.get("manual_one", 0)) == 1,
		"Rest recovery must leave manual trackers untouched")
	used_record["classes"] = [{"name": "Bard", "source": "PHB", "level": 5}]
	assert(not Trackers.spent_after_recovery(used_record, "short_rest").has(
		"class:bard:phb:bardic_inspiration"),
		"Short rest replenishes Bardic Inspiration after Font of Inspiration")
	var paladin_2014: Array[Dictionary] = Trackers.for_creature({
		"kind": "character", "abilities": {"cha": 14},
		"classes": [{"name": "Paladin", "source": "PHB", "level": 3}]
	})
	assert(int(_find_resource(paladin_2014, "Divine Sense").get("max", 0)) == 3)
	assert(int(_find_resource(paladin_2014, "Lay on Hands").get("max", 0)) == 15)
	assert(int(_find_resource(paladin_2014, "Channel Divinity").get("max", 0)) == 1)
	assert(_find_resource(Trackers.for_creature({
		"kind": "character", "classes": [{"name": "Wizard", "source": "PHB", "level": 3}]
	}), "Portents").is_empty(), "Subclass counters must not leak into other subclasses")
	var diviner: Dictionary = _find_resource(Trackers.for_creature({
		"kind": "character",
		"classes": [{"name": "Wizard", "source": "PHB", "level": 14,
			"subclass": "Divination"}]
	}), "Portents")
	assert(int(diviner.get("max", 0)) == 3 and diviner.get("recharge", "") == "long_rest")
	assert(_find_resource(Trackers.for_creature({
		"kind": "character", "classes": [{"name": "Warlock", "source": "PHB", "level": 18}]
	}), "Eldritch Invocations Known").is_empty(),
		"Selection capacity must never become a consumable tracker")
	assert(_find_resource(Trackers.for_creature({
		"kind": "character", "classes": [{"name": "Druid", "source": "PHB", "level": 2}]
	}), "Natural Recovery").is_empty(), "No unselected Circle of the Land resource")
	var manual_formula: Dictionary = _find_resource(Trackers.for_creature({
		"kind": "character", "level": 3, "abilities": {"cha": 16},
		"resource_trackers": [{"id": "special", "name": "Custom", "max": 1,
			"max_formula": "1 + cha_mod", "recharge": "long_rest"}]
	}), "Custom")
	assert(int(manual_formula.get("max", 0)) == 4
		and manual_formula.get("recharge", "") == "long_rest",
		"Saved custom formulas and rest types must survive normalization")

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

	# Source-qualified Fight Club supplements enrich only matching 5etools
	# features; 5etools {@recharge} and numeric legendaryActions take priority.
	var archaic: Dictionary = {
		"kind": "monster",
		"stat_block": {
			"source": "SCC", "name": "Archaic",
			"trait": [{"name": "Legendary Resistance (3/Day)"}],
			"action": [{"name": "Gravity Shift {@recharge 5}"}],
			"reaction": [{"name": "Spell Mimicry (1/Day)"}],
			"legendary": [{"name": "Claw"}]
		}
	}
	var enriched: Array[Dictionary] = Trackers.for_creature(archaic)
	assert(enriched.size() == 4, "Fight Club must add only missing counters and a legendary pool")
	assert(int(_find_resource(enriched, "Legendary Resistance (3/Day)").get("max", 0)) == 3)
	assert(String(_find_resource(enriched, "Legendary Resistance (3/Day)").get("recharge", "")) == "long_rest")
	assert(int(_find_resource(enriched, "Spell Mimicry (1/Day)").get("max", 0)) == 1)
	assert(String(_find_resource(enriched, "Gravity Shift").get("id", "")) == "recharge:action:0",
		"5etools-native d6 counters must keep their ID and avoid duplicates")
	assert(int(_find_resource(enriched, "Azioni leggendarie").get("max", 0)) == 3)
	archaic["resource_tracker_spent"] = {
		"fightclub:trait:0": 1, "fightclub:reaction:0": 1,
		"recharge:action:0": 1, "legendary_actions": 2
	}
	var rested: Dictionary = Trackers.spent_after_recovery(archaic, "long_rest")
	assert(not rested.has("fightclub:trait:0") and not rested.has("fightclub:reaction:0"))
	assert(rested.has("recharge:action:0"), "d6 recharge must not be reset by rests")
	assert(rested.has("legendary_actions"), "long rest must not trigger a turn reset")
	assert(not Trackers.spent_after_recovery(archaic, "turn").has("legendary_actions"))
	archaic["stat_block"]["legendaryActions"] = 2
	var explicit_pool: Array[Dictionary] = Trackers.for_creature(archaic)
	assert(int(_find_resource(explicit_pool, "Azioni leggendarie").get("max", 0)) == 2,
		"Native legendaryActions must override Fight Club's pool count")
	archaic["stat_block"]["source"] = "OTHER"
	assert(Trackers.for_creature(archaic).size() == 2,
		"Supplement must never match a different source with the same monster name")
	archaic["stat_block"]["source"] = "SCC"
	archaic["stat_block"]["name"] = "Variant Archaic"
	assert(Trackers.for_creature(archaic).size() == 2,
		"Supplement must not guess from a different monster variant")
	var short_rest_creature: Dictionary = {
		"kind": "monster",
		"stat_block": {
			"source": "AI", "name": "Chaos Quadrapod",
			"action": [{"name": "Chaos Cloud (Recharges after a Short or Long Rest)"}]
		},
		"resource_tracker_spent": {"fightclub:action:0": 1}
	}
	var short_counter: Dictionary = _find_resource(
		Trackers.for_creature(short_rest_creature),
		"Chaos Cloud (Recharges after a Short or Long Rest)")
	assert(String(short_counter.get("recharge", "")) == "short_rest")
	assert(not Trackers.spent_after_recovery(short_rest_creature, "short_rest").has("fightclub:action:0"))


	# Monster Manual 2014 supplements must be exported and loaded the same
	# way as other books, without stealing priority from native 5etools.
	var mm_dragon: Dictionary = {
		"kind": "monster",
		"stat_block": {
			"source": "MM", "name": "Adult Black Dragon",
			"trait": [{"name": "Legendary Resistance (3/Day)"}],
			"action": [{"name": "Acid Breath {@recharge 5}"}],
			"legendary": [{"name": "Detect"}]
		}
	}
	var dragon_trackers: Array[Dictionary] = Trackers.for_creature(mm_dragon)
	assert(int(_find_resource(dragon_trackers, "Legendary Resistance (3/Day)").get("max", 0)) == 3,
		"MM 2014 legendary resistance should come from Fight Club structured recharge")
	assert(String(_find_resource(dragon_trackers, "Legendary Resistance (3/Day)").get("recharge", "")) == "long_rest")
	assert(String(_find_resource(dragon_trackers, "Acid Breath").get("id", "")) == "recharge:action:0",
		"Keep native 5etools breath recharge instead of duplicating MM")
	assert(int(_find_resource(dragon_trackers, "Azioni leggendarie").get("max", 0)) == 3,
		"MM legendary pool count is used only when 5etools numeric count is absent")
	assert(dragon_trackers.size() == 3, "MM supplementary counters must not duplicate native ones")
	mm_dragon["stat_block"]["legendaryActions"] = 2
	assert(int(_find_resource(Trackers.for_creature(mm_dragon), "Azioni leggendarie").get("max", 0)) == 2)
	mm_dragon["stat_block"]["source"] = "XMM"
	assert(_find_resource(Trackers.for_creature(mm_dragon), "Legendary Resistance (3/Day)").is_empty(),
		"2024 Monster Manual must not borrow MM 2014 resources")

	print("PASS: structured 5etools resource trackers")
	quit()
