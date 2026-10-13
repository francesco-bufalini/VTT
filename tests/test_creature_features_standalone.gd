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

	var found := false
	for feature: Dictionary in Features.collect_features(fixtures[1]):
		if String(feature.get("name", "")) == "Claw":
			found = true
	assert(found, "Structured monster features were lost")
	print("PASS: shared feature projection, cache isolation and standalone tracker derivation")
	quit()
