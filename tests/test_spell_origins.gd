extends SceneTree

const Origins = preload("res://vtt/creature_origin_choices.gd")
const Rules = preload("res://vtt/creature_proficiency_rules.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const Defenses = preload("res://vtt/creature_damage_defenses_tab.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Spells = preload("res://vtt/spells/spell_catalog.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var definition: Dictionary = Spells.catalog_spell("acid_splash")
	assert(not definition.is_empty(), "Known spell must resolve from the 5etools catalog")
	var record: Dictionary = {
		"kind": "character", "rules_version": "2024",
		"proficiency_choices": [], "resource_trackers": [],
		"formula_bonuses": [], "damage_defense_entries": [],
		"proficiency_origins": []
	}
	var available: Array[Dictionary] = Origins.available(record)
	assert(String(available[0].get("id", "")) == Origins.SPELL_PICKER_ID,
		"Incantesimo must be the first possible origin")
	var spell_id: String = "spell:acid_splash"
	var chosen: Dictionary = {
		"id": spell_id, "group": "spell",
		"name": "Incantesimo · Acid Splash"
	}
	var origins: Array[Dictionary] = []
	Origins.ensure(origins, chosen)
	record["proficiency_origins"] = origins.duplicate(true)
	record["formula_bonuses"] = [{
		"id": "spell-ac-bonus", "target": "ac", "expression": "2",
		"origin_id": spell_id, "origin_name": chosen["name"],
		"disabled": false, "automatic": false
	}]
	var has_spell := false
	for feature: Dictionary in Traits.collect_features(record):
		if String(feature.get("origin_key", "")) == spell_id:
			has_spell = true
			assert(String(feature.get("category", "")) == "incantesimi",
				"Applied spell must be categorized as a trait")
	assert(has_spell, "Spell chosen as an origin appears in Traits")
	assert(Bonuses.bonus(record, "ac") == 2,
		"Spell origins grant manual formula bonuses")
	var persisted: Array[Dictionary] = Origins.available(record)
	var has_persisted := false
	for origin: Dictionary in persisted:
		if String(origin.get("id", "")) == spell_id:
			has_persisted = true
	assert(has_persisted, "Chosen spell must be available again after reloading")

	(record["proficiency_origins"][0] as Dictionary)["disabled"] = true
	assert(not bool(Rules.origin_enabled_map(record).get(spell_id, true)))
	assert(Bonuses.bonus(record, "ac") == 0,
		"Disabling an applied spell withdraws its granted bonus")
	(record["proficiency_origins"][0] as Dictionary)["disabled"] = false
	record["damage_defense_entries"] = [{
		"key": "cold", "rank": 1, "origin_id": spell_id, "automatic": false
	}]
	assert(Defenses.rank(record, "cold") == 1,
		"Spell can grant a manually configured resistance")
	(record["proficiency_origins"][0] as Dictionary)["disabled"] = true
	assert(Defenses.rank(record, "cold") == 0,
		"Disabling a spell withdraws its defensive effects")

	record["damage_defense_entries"] = []
	record["formula_bonuses"] = []
	Rules.reconcile_origin_dependents(record)
	var still_owned := false
	for origin: Dictionary in record.get("proficiency_origins", []):
		if String(origin.get("id", "")) == spell_id:
			still_owned = true
	assert(not still_owned, "Removing the last spell-granted benefit removes the spell origin")
	print("PASS: spell origin choice, trait display, defense/bonus activation and cleanup")
	quit()
