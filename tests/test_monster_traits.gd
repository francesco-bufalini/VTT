extends SceneTree

const Features = preload("res://vtt/creature_features.gd")
const MonsterProjection = preload("res://vtt/monster_trait_projection.gd")
const Metadata = preload("res://vtt/monster_action_metadata.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const Actions = preload("res://vtt/creature_action_economy_tab.gd")
const Attacks = preload("res://vtt/creature_attack_data.gd")
const Bestiary = preload("res://vtt/bestiary_5etools_client.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/monster_traits.json"))
	record.stat_block = Metadata.prepare(record.stat_block)
	var features: Array[Dictionary] = Features.collect_features(record)
	assert(features[0].name == "Panoramica")
	var origins: Dictionary = {}
	for feature: Dictionary in features:
		origins[feature.origin_key] = true
		assert(feature.name not in ["Bite", "Frightful Presence", "Quick Step", "Deflect"])
	assert(origins.size() == 1)
	var old_source: String = "feature:monster|action|monster|action|0|bite"
	assert(preload("res://vtt/creature_proficiency_rules.gd").origin_enabled_map(record).get(old_source, false), "Saved action-card origins remain valid after regrouping")
	var older: Dictionary = record.duplicate(true)
	older["formula_bonuses"] = [{"id": "old-bite-bonus", "origin_id": "feature:trait:monster|action|monster|action|0|bite", "target": "attack_hit:monster:action:1", "expression": "2"}]
	preload("res://vtt/creature_proficiency_rules.gd").reconcile_origin_dependents(older)
	assert(older.formula_bonuses.size() == 1, "Regrouping must not delete saved custom benefits")
	assert("monster:action:1" in features[0].monster_attack_ids)
	assert(Attacks.definitions(record)[0].get("origin_id", "") == "feature:" + String(features[0].key))
	var trackers: Array[Dictionary] = Trackers.for_creature(record)
	assert(trackers.any(func(row: Dictionary) -> bool: return row.id == "legendary_actions" and row.max == 3))
	assert(trackers.any(func(row: Dictionary) -> bool: return row.id == "lair_actions" and row.max == 1))
	assert(trackers.any(func(row: Dictionary) -> bool: return row.id == "legendary_resistance" and row.max == 3))
	var projected: Array[Dictionary] = MonsterProjection.traits(record)
	for feature: Dictionary in projected:
		if feature.monster_role == "resistance":
			assert(feature.monster_actions.is_empty())
		if feature.monster_role == "lair":
			assert(feature.monster_actions.size() == 2)
	var actions: Array[Dictionary] = Actions.entries(record)
	assert(actions.any(func(row: Dictionary) -> bool: return row.name == "Wing Attack (Costs 2 Actions)" and row.time == 5 and row.cost == 2))
	assert(actions.any(func(row: Dictionary) -> bool: return row.name == "Frightful Presence" and row.time == 0 and not String(row.origin_id).is_empty()))
	assert(actions.any(func(row: Dictionary) -> bool: return row.name == "Resistenza leggendaria" and row.time == 6))
	assert(actions.any(func(row: Dictionary) -> bool: return row.name == "Azioni di tana" and row.time == 7))
	var lore: Dictionary = {"name": "Young Test Dragon", "source": "TEST"}
	Bestiary._apply_details(lore, {"monsterFluff": [{"name": "Young Test Dragon", "source": "TEST", "_copy": {"name": "Test Dragon", "source": "TEST"}}, {"name": "Test Dragon", "source": "TEST", "entries": ["Shared dragon lore."]}]}, "fluff")
	assert(lore.fluff.entries == ["Shared dragon lore."])
	Bestiary._apply_details(lore, {"monsterFluff": [{"name": "Young Test Dragon", "source": "TEST", "entries": ["Changed upstream."]}]}, "fluff")
	assert(lore.fluff.entries == ["Shared dragon lore."], "Existing lore must remain intact")
	lore["legendaryGroup"] = {"name": "Dragon", "source": "TEST"}
	Bestiary._apply_details(lore, {"legendaryGroup": [{"name": "Dragon", "source": "OTHER", "lairActions": ["Wrong book"]}, {"name": "Dragon", "source": "TEST", "lairActions": ["Correct book"]}]}, "legendary")
	assert(lore.lairActions == ["Correct book"])
	var tab = Actions.new()
	root.add_child(tab)
	await process_frame
	tab.load_record(record)
	assert(tab._panels[5].visible and tab._panels[6].visible and tab._panels[7].visible)
	assert(int(tab._section_counts[5].text) == 3, "Legendary base rule and two options")
	tab.queue_free()
	var view = preload("res://vtt/creature_traits_tab.gd").new()
	root.add_child(view)
	view.setup()
	view.load_record(record)
	assert(view._features[0].name == "Panoramica")
	assert(view._origin_choice.item_count == 2, "All origins plus one monster race")
	assert(view._monster_benefits(view._features[0]).size() >= 5)
	view.queue_free()
	print("PASS: monster traits, provenance, costs, lore and lair import")
	quit()
