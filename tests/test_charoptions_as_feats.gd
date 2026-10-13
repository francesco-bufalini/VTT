extends SceneTree
const Player = preload("res://vtt/player_5etools_catalog.gd")
const Features = preload("res://vtt/creature_features.gd")
const Prof = preload("res://vtt/creature_proficiency_rules.gd")
const Adapter = preload("res://vtt/native_5etools_adapter.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var feat_catalog: Array[Dictionary] = Player.entries("feats")
	var options: Array[Dictionary] = []
	for row: Dictionary in feat_catalog:
		if String(row.get("id", "")).begins_with("charoption:"):
			options.append(row)
	assert(options.size() == 44, "Every 5etools Character Creation Option is selectable as a feat")
	var iconoclast: Dictionary = {}
	for row: Dictionary in options:
		assert(row.get("entries", []) is Array, "Keep unstructured text and structured nested entries")
		assert(String(row.get("source", "")) != "" and String(row.get("feature_type", "")) != "")
		if row.get("name") == "Iconoclast" and row.get("source") == "MOT":
			iconoclast = row
	assert(not iconoclast.is_empty(), "MOT Iconoclast must be included")
	assert(iconoclast.get("feature_type", "") == "Supernatural Gift")
	assert(Player.search("feats", "Supernatural Gift", {}, 500).any(
		func(row: Dictionary) -> bool: return String(row.get("id", "")) == String(iconoclast.id)),
		"Compendium search must index character-option subtype")
	var desc: String = Player.description_text("feats", iconoclast)
	assert("Enlightened Protection" in desc and "Iconoclast Paragon" in desc)
	var saved_feat: Dictionary = {"id": iconoclast.id, "name": "Iconoclast", "source": "MOT", "origin_id": "", "disabled": false}
	var record: Dictionary = {"kind": "player", "rules_version": "2014", "level": 1,
		"feats_catalog": [saved_feat]}
	var feature_names: Array[String] = []
	for entry: Dictionary in Features.collect_features(record):
		feature_names.append(String(entry.get("name", "")))
	assert("Enlightened Protection" in feature_names and "Reject the Gods" in feature_names)
	assert("Iconoclast Hero" not in feature_names and "Iconoclast Paragon" not in feature_names)
	assert(Prof.origin_enabled_map(record).get(Prof.feat_source_id(saved_feat), false),
		"Character creation options are valid feat origins")
	record["level"] = 11
	feature_names.clear()
	for entry: Dictionary in Features.collect_features(record):
		feature_names.append(String(entry.get("name", "")))
	assert("Iconoclast Hero" in feature_names and "Iconoclast Paragon" in feature_names)
	assert("Iconoclast Archetype" not in feature_names)
	record["level"] = 17
	feature_names.clear()
	for entry: Dictionary in Features.collect_features(record):
		feature_names.append(String(entry.get("name", "")))
	assert("Iconoclast Archetype" in feature_names)
	var homebrew: Dictionary = {"_meta": {"sources": [{"json": "HBTEST"}]},
		"charoption": [{"name": "Sample Gift", "source": "HBTEST", "optionType": ["SG"],
			"entries": ["A sample supernatural gift."]}]}
	var converted: Dictionary = Adapter.normalize(homebrew, "user://charoptions-test.json")
	assert(converted.get("diagnostics", []).is_empty())
	var entries: Array = converted.get("entries", [])
	assert(entries.size() == 1 and entries[0].get("category", "") == "feats")
	assert(entries[0].get("feature_type", "") == "Supernatural Gift")
	print("PASS: 44 character options, subtype, sources, homebrew mapping and level-gated feat traits")
	quit()
