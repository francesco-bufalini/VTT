extends SceneTree
const Catalog = preload("res://vtt/content_catalog.gd")
const Player = preload("res://vtt/player_5etools_catalog.gd")
const Spells = preload("res://vtt/spells/spell_catalog.gd")
const Token = preload("res://token.tscn")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")

func _initialize() -> void:
	call_deferred("run")

func write_package(path: String, entries: Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 1, "namespace": "regression", "entries": entries}))
	file.close()

func run() -> void:
	var folder := "user://test_homebrew_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var entries := [
		{"id": "mark", "name": "Mark", "category": "conditions", "icon_id": "poisoned", "data": {"entries": [{"type": "list", "items": ["Homebrew {@condition poisoned} effect"]}]}},
		{"id": "owl", "name": "Owl", "category": "monsters", "data": {"hp": {"average": 11}}},
		{"id": "mage", "name": "Mage", "category": "classes", "data": {"trackers": [{"id": "charge", "label": "Charge", "maximum": 4, "min_level": 2}]}},
		{"id": "star", "name": "Star", "category": "races", "data": {"entries": ["Playable species"]}},
		{"id": "spark", "name": "Spark", "category": "spells", "data": {"level": 0, "target_mode": "self_emanation", "aoe_shape": "sphere", "aoe_radius_feet": 5, "classes": ["Mago"]}}
	]
	write_package(folder.path_join("a.json"), entries)
	write_package(folder.path_join("b.json"), [{"id": "mark", "name": "Duplicate", "category": "conditions", "data": {}}])
	Catalog.reload_homebrew([folder])
	assert(Catalog.diagnostics.size() == 1, "Duplicate ID must be diagnosed")
	var definitions := Catalog.condition_definitions()
	assert(definitions.size() > 30, "Conditions, diseases and related effects available offline")
	# Only real 5etools conditions/statuses are selectable, not the old
	# hidden/dead tactical markers, while historical IDs remain valid.
	var names_2014: Dictionary = {}
	for row: Dictionary in definitions:
		names_2014[String(row.id)] = true
		assert(String(row.get("name", "")) not in ["Accecato", "Avvelenato"], "Use English effect names")
		if String(row.get("origin", "")) == "5etools" and String(row.get("edition", "")) != "":
			assert(String(row.edition) == "2014", "No mixed 2014/2024 sources")
	assert(names_2014.has("blinded") and names_2014.has("concentrating") and names_2014.has("surprised"))
	assert(not names_2014.has("hidden") and not names_2014.has("dead"))
	assert(Catalog.valid_effect_id("hidden") and Catalog.valid_effect_id("dead"))
	var definitions_2024 := Catalog.condition_definitions("2024")
	var names_2024: Dictionary = {}
	for row: Dictionary in definitions_2024:
		names_2024[String(row.id)] = true
		if String(row.get("origin", "")) == "5etools" and String(row.get("edition", "")) != "":
			assert(String(row.edition) == "2024", "Edition must filter every 5etools entry")
	assert(names_2024.has("5etools:effects:xphb:bloodied"))
	assert(not names_2014.has("5etools:effects:xphb:bloodied"))

	var custom: Dictionary = {}
	for row: Dictionary in definitions:
		if row.id == "homebrew:regression:conditions:mark":
			custom = row
	assert(custom.icon == Catalog.icon_for("poisoned"))
	assert("Homebrew poisoned effect" in Catalog.description(custom), "Nested 5eTools markup must be readable")
	assert(Catalog.valid_effect_id(custom.id))
	assert(not Catalog.valid_effect_id("unknown") and not Catalog.valid_effect_id("homebrew:../bad:conditions:x"))
	assert(Player.entries("races").size() > 100)
	assert(Player.entries("classes").size() > 20)
	assert(Spells.catalog_spell("homebrew:regression:spells:spark").name == "Spark")
	var home_classes: Array[Dictionary] = Catalog.home_entries("classes")
	assert(home_classes.size() == 1 and home_classes[0].id == "homebrew:regression:classes:mage")
	assert(home_classes[0].trackers[0].maximum == 4, "Homebrew class metadata must survive catalog loading")
	assert(Trackers.for_creature({"classes": [{"name": "Mage", "id": home_classes[0].id, "level": 2}]}).is_empty(),
		"Retired legacy tracker metadata must not generate structured counters")
	var features := Player.entries("class_features")
	var described := false
	for feature: Dictionary in features:
		if feature.get("class_name") == "Fighter" and feature.get("class_source") == "PHB" and feature.get("name") == "Second Wind":
			described = "entries" in feature and not feature.entries.is_empty()
	assert(described, "2014 source-qualified reference descriptions required")
	var token := Token.instantiate()
	root.add_child(token)
	token.set_conditions(["poisoned", custom.id, "5etools:diseases:dmg:sewer%20plague"])
	assert(token.get_conditions().size() == 3)
	var presentation: Array = token.get_condition_presentations()
	Catalog.reload_homebrew([]) # Receiver without the sender's package.
	token.set_condition_presentations(presentation)
	token.set_conditions(token.get_conditions())
	assert(token.get_conditions().size() == 3, "Missing homebrew must never clear saved conditions")
	assert("Mark" in " ".join(token.get_active_condition_display_parts()), "Remote icon/name survives missing package")
	token.queue_free()
	for filename: String in ["a.json", "b.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	Catalog.reload_homebrew()
	print("PASS: unified catalogs, homebrew conflicts, descriptions, stable icons and unknown-effect preservation")
	quit()
