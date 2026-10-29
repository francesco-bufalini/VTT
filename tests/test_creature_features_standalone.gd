extends SceneTree

const Features = preload("res://vtt/creature_features.gd")
const TraitsView = preload("res://vtt/creature_traits_tab.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# This must remain usable without any scene tree, Control or 3D board.
	var source: String = FileAccess.get_file_as_string("res://vtt/creature_features.gd")
	assert(not source.is_empty())
	assert(not source.contains("creature_traits_tab.gd"))
	var tracker_source: String = FileAccess.get_file_as_string("res://vtt/structured_resource_trackers.gd")
	assert(not tracker_source.contains("creature_traits_tab.gd"))

	# UI modules may display feature descriptions, but no domain engine
	# should depend on a VBoxContainer just to resolve a feature source.
	for path: String in [
		"res://vtt/creature_bonus_rules.gd",
		"res://vtt/creature_structured_bonuses.gd",
		"res://vtt/creature_proficiency_rules.gd",
		"res://vtt/origin_spell_grants.gd",
		"res://vtt/structured_origin_spells_5etools.gd",
		"res://vtt/creature_origin_choices.gd"
	]:
		var domain_source: String = FileAccess.get_file_as_string(path)
		assert(not domain_source.is_empty(), "Missing domain service: " + path)
		assert(not domain_source.contains("creature_traits_tab.gd"),
			"Domain service imports a visual trait tab: " + path)
	

	var fixtures: Array[Dictionary] = [
		{},
		{"kind": "monster", "stat_block": {"name": "Test Wyrm", "source": "MM",
			"trait": [{"name": "Innate Magic", "entries": ["3/day each"]}],
			"action": [{"name": "Claw", "entries": ["Melee attack"]}]}},
		{"kind": "character", "class": "Fighter", "class_source": "PHB", "level": 3,
			"abilities": {"str": 12, "dex": 12, "con": 12, "int": 10, "wis": 10, "cha": 8}},
		{"kind": "character", "feats_catalog": [{"name": "Magic Initiate", "source": "PHB"}]},
		{"kind": "character", "inventory": [{"id": "test-item", "name": "Test Item", "quantity": 1}]}
	]
	for record: Dictionary in fixtures:
		var data: Array[Dictionary] = Features.collect_features(record)
		assert(TraitsView.collect_features(record) == data,
			"Desktop trait view and shared service return different features")
		var changed: Array[Dictionary] = Features.collect_features(record)
		if not changed.is_empty():
			changed[0]["name"] = "CACHE_MUTATION_SENTINEL"
			assert(Features.collect_features(record) == data,
				"Feature cache leaked a mutable dictionary")
		var derived: Array[Dictionary] = Trackers.for_creature(record)
		assert(derived is Array)

	# Every named trait of an inactive item must carry the same display
	# state as its parent. Ownership keeps descriptions visible, equipping
	# controls availability. Do not confuse this with removing an item.
	var owned_item: Dictionary = {
		"id": "test:domain:amulet", "name": "Amuleto",
		"type": "RG", "quantity": 1, "active": true, "equipped": false,
		"entries": [{"name": "Potere latente", "entries": ["Descrizione."]}]
	}
	var item_record: Dictionary = {"kind": "character", "inventory": [owned_item]}
	var locked_found: bool = false
	for feature: Dictionary in Features.collect_features(item_record):
		if String(feature.get("name", "")) == "Potere latente":
			locked_found = true
			assert(bool(feature.get("inactive", false)),
				"Inactive item's nested traits must be inactive too")
	assert(locked_found, "An owned item must retain its nested trait description")
	owned_item["equipped"] = true
	for feature: Dictionary in Features.collect_features(item_record):
		if String(feature.get("name", "")) == "Potere latente":
			assert(not bool(feature.get("inactive", false)),
				"Equipping restores nested traits without rebuilding saved grants")

	var found := false
	for feature: Dictionary in Features.collect_features(fixtures[1]):
		if String(feature.get("name", "")) == "Panoramica":
			for action: Dictionary in feature.get("monster_actions", []):
				if action.get("name", "") == "Claw":
					found = true
	assert(found, "Monster capabilities must remain owned by the overview")
	print("PASS: shared feature projection, cache isolation and standalone tracker derivation")
	quit()
