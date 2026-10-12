extends SceneTree
const TokenScene = preload("res://token.tscn")
const Measure = preload("res://measurement_tool.gd")
const Catalog = preload("res://vtt/content_catalog.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var arena: Node3D = load("res://tests/scenes/agent_test_arena.tscn").instantiate()
	root.add_child(arena)
	var tokens: Node3D = arena.get_node("Tokens")
	var measure := Measure.new()
	arena.add_child(measure)
	var initiative: Node = load("res://vtt/initiative_tracker.gd").new()
	initiative.name = "InitiativeTracker"
	arena.add_child(initiative)
	var sync: Node = load("res://network/board_sync.gd").new()
	arena.add_child(sync)
	sync.setup(arena, TokenScene, tokens, measure)
	var token := TokenScene.instantiate()
	tokens.add_child(token)
	token.set_meta("creature_id", "private-creature")
	token.set_meta("creature_owner_id", "controller-0123456789")
	token.set_meta("stat_block", {"secret": "PRIVATE_SENTINEL"})
	token.set_meta("trackers", [{"current": 3}])
	var id := "homebrew:sync:conditions:marked"
	token.set_conditions(["poisoned", id])
	token.set_condition_presentations([{ "id": id, "name": "Marked", "icon": "✨" }])
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sync.create_snapshot()))
	assert(sync.valid_snapshot(snapshot))
	assert("PRIVATE_SENTINEL" not in JSON.stringify(snapshot))
	var row: Dictionary = snapshot.objects[0]
	assert(not row.has("stat_block") and not row.has("trackers") and not row.has("current_hp"))
	assert(row.creature_id == "private-creature")
	assert(row.condition_presentations.size() == 2)
	var malformed := snapshot.duplicate(true)
	malformed.objects[0].condition_presentations[0]["entries"] = ["private text"]
	assert(not sync.valid_snapshot(malformed), "Descriptions/private payloads cannot travel as presentation metadata")
	malformed = snapshot.duplicate(true)
	malformed.objects[0].conditions = ["unknown-condition"]
	assert(not sync.valid_snapshot(malformed))
	token.set_conditions([])
	assert(sync.apply_snapshot(snapshot))
	assert(token.get_conditions() == ["poisoned", id])
	assert("Marked" in " ".join(token.get_active_condition_display_parts()))
	token.push_transformation_state()
	token.set_size_category("Large", 2.0)
	assert(token.restore_previous_transformation())
	assert(token.get_meta("creature_id") == "private-creature")
	assert(token.get_conditions() == ["poisoned", id])
	# Spell effects must survive exactly the same public board snapshot
	# lifecycle as conditions, including on tokens we do not own.
	token.set_active_spell_ids(["bless", "shield_of_faith"])
	token.set_concentrating_spell_id("bless")
	var visible_effects: String = " ".join(token.get_active_condition_display_parts())
	assert(visible_effects.contains("✨") and visible_effects.contains("bless") == false,
		"The tactical strip must show icons and spell names, not raw IDs")
	var spell_snapshot: Dictionary = JSON.parse_string(JSON.stringify(sync.create_snapshot()))
	assert(sync.valid_snapshot(spell_snapshot))
	var spell_row: Dictionary = spell_snapshot.objects[0]
	assert(spell_row.active_spell_ids == ["bless", "shield_of_faith"])
	assert(spell_row.concentrating_spell_id == "bless")
	assert("concentrating" in spell_row.conditions)
	var invalid_spells: Dictionary = spell_snapshot.duplicate(true)
	invalid_spells.objects[0].active_spell_ids = ["bless", "bless"]
	assert(not sync.valid_snapshot(invalid_spells), "Duplicated network spell ids are invalid")
	invalid_spells = spell_snapshot.duplicate(true)
	invalid_spells.objects[0].concentrating_spell_id = 123
	assert(not sync.valid_snapshot(invalid_spells), "Concentration id must be a string")
	token.set_active_spell_ids([])
	token.set_concentrating_spell_id("")
	assert(sync.apply_snapshot(spell_snapshot))
	assert(token.get_active_spell_ids() == ["bless", "shield_of_faith"])
	assert(token.get_concentrating_spell_id() == "bless")
	assert(token.has_condition("concentrating"))
	token.set_condition("concentrating", false)
	assert(token.get_concentrating_spell_id().is_empty())
	arena.queue_free()
	await process_frame
	print("PASS: private sheet boundary, public condition icons, snapshot round-trip and polymorph identity")
	quit()
