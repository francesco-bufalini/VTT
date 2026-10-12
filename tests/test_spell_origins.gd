extends SceneTree

const Origins = preload("res://vtt/creature_origin_choices.gd")
const Rules = preload("res://vtt/creature_proficiency_rules.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const Defenses = preload("res://vtt/creature_damage_defenses_tab.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Spells = preload("res://vtt/spells/spell_catalog.gd")
const ActiveSpells = preload("res://vtt/creature_active_spells.gd")
const CreatureArea = preload("res://vtt/creature_area.gd")


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
	# A spell added from the Conditions page is an origin even with no grants.
	var standalone: Dictionary = {
		"kind": "character", "rules_version": "2024",
		"proficiency_origins": [], "proficiency_choices": [],
		"formula_bonuses": [], "resource_trackers": [],
		"damage_defense_entries": [], "feats_catalog": []
	}
	assert(ActiveSpells.apply(standalone, "acid_splash"))
	assert(ActiveSpells.active_origins(standalone).size() == 1)
	assert(bool((standalone["proficiency_origins"][0] as Dictionary).get("applied", false)))
	var standalone_trait_found := false
	for feature: Dictionary in Traits.collect_features(standalone):
		if String(feature.get("origin_key", "")) == "spell:acid_splash":
			standalone_trait_found = true
	assert(standalone_trait_found, "Spells directly applied from Conditions must appear in Traits")
	Rules.reconcile_origin_dependents(standalone)
	assert(ActiveSpells.active_origins(standalone).size() == 1,
		"Reconciliation must preserve spells directly applied with no grants")
	var reloaded_origins: Array[Dictionary] = Rules.origins(standalone)
	assert(bool(reloaded_origins[0].get("applied", false)),
		"Origin reload must preserve the explicit applied flag")
	assert(ActiveSpells.apply(standalone, "acid_splash"))
	assert(ActiveSpells.active_origins(standalone).size() == 1,
		"Reapplying the same spell must not create duplicate origins")
	standalone["formula_bonuses"] = [{
		"id": "spell-boost", "origin_id": "spell:acid_splash",
		"origin_name": "Incantesimo · Acid Splash",
		"target": "ac", "expression": "3", "automatic": false
	}]
	standalone["damage_defense_entries"] = [{
		"key": "cold", "rank": 1, "origin_id": "spell:acid_splash", "automatic": false
	}]
	standalone["resource_trackers"] = [{
		"id": "from-spell", "name": "Spell resource", "origin_id": "spell:acid_splash", "max": 2
	}, {
		"id": "unrelated", "name": "Other resource", "origin_id": "", "max": 2
	}]
	assert(Bonuses.bonus(standalone, "ac") == 3 and Defenses.rank(standalone, "cold") == 1)
	# A disabled spell can be reapplied directly in Conditions.
	(standalone["proficiency_origins"][0] as Dictionary)["disabled"] = true
	assert(ActiveSpells.active_origins(standalone).is_empty())
	assert(ActiveSpells.apply(standalone, "acid_splash"))
	assert(ActiveSpells.active_origins(standalone).size() == 1)
	assert(ActiveSpells.remove(standalone, "spell:acid_splash"))
	assert(ActiveSpells.active_origins(standalone).is_empty()
		and (standalone["proficiency_origins"] as Array).is_empty(),
		"Removing an active spell must remove its origin")
	assert(Bonuses.bonus(standalone, "ac") == 0 and Defenses.rank(standalone, "cold") == 0,
		"Removing the source withdraws dependent bonuses and defenses")
	assert(standalone["resource_trackers"].size() == 1
		and String(standalone["resource_trackers"][0].get("id", "")) == "unrelated",
		"Removing a spell must clean only spell-granted trackers")
	assert(not ActiveSpells.remove(standalone, "spell:acid_splash"),
		"Deleting a spell twice must not modify other origins")

	# The Conditions UI must place spells first and Other Effects directly below.
	var view := CreatureArea.new()
	root.add_child(view)
	view._condition_rows = VBoxContainer.new()
	view.add_child(view._condition_rows)
	assert(ActiveSpells.apply(standalone, "acid_splash"))
	view._refresh_conditions(standalone)
	var first_row: HBoxContainer = view._condition_rows.get_child(0) as HBoxContainer
	assert(first_row != null and (first_row.get_child(0) as Label).text == "Incantesimi attivi")
	var headers: Array[String] = []
	for child: Node in view._condition_rows.get_children():
		if child is Label and String((child as Label).text) in [
			"Altri effetti", "Conditions", "Diseases / magical diseases"
		]:
			headers.append(String((child as Label).text))
	assert(not headers.is_empty() and headers[0] == "Altri effetti",
		"Other Effects must follow the spell section, before regular conditions")
	view.queue_free()
	print("PASS: spell origin choice, trait display, defense/bonus activation and cleanup")
	quit()
