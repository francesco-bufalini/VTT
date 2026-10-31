extends SceneTree

const InitiativeTracker = preload("res://vtt/initiative_tracker.gd")
const TokenScene = preload("res://token.tscn")


func _initialize() -> void:
	call_deferred("run")


func _make_token(parent: Node3D, name: String, creature_id: String) -> CharacterBody3D:
	var token: CharacterBody3D = TokenScene.instantiate()
	parent.add_child(token)
	token.call("set_display_name", name)
	token.set_physics_process(false)
	if not creature_id.is_empty():
		token.set_meta("creature_id", creature_id)
		token.set_meta("creature_owner_id", "test-owner")
	return token


func run() -> void:
	var board := Node3D.new()
	root.add_child(board)
	var tokens := Node3D.new()
	tokens.name = "Tokens"
	board.add_child(tokens)

	var tracker: Node = InitiativeTracker.new()
	board.add_child(tracker)
	tracker.set("board_root", board)
	tracker.set("tokens_root", tokens)
	var linked := _make_token(tokens, "Aria", "creature-aria")
	var unlinked := _make_token(tokens, "Token libero", "")
	_make_token(tokens, "Borin", "creature-borin")
	var candidates: Array = tracker.call("_creature_candidates")
	assert(candidates.size() == 2, "Only creatures with live linked tokens can join")
	assert(String(candidates[0].get("name", "")) == "Aria")
	assert(String(candidates[0].get("token_id", "")) == String(linked.call("get_token_id")))
	assert(String(candidates[0].get("creature_id", "")) == "creature-aria")
	assert(String(candidates[1].get("name", "")) == "Borin")

	# The same creature cannot appear twice, even with multiple scene tokens.
	_make_token(tokens, "Borin extra", "creature-borin")
	assert((tracker.call("_creature_candidates") as Array).size() == 2)

	# Already enrolled creatures disappear from the chooser.
	var enrolled: Array = tracker.get("entries")
	enrolled.append({
		"id": "initiative_1",
		"name": "Aria",
		"token_id": String(linked.call("get_token_id")),
		"creature_id": "creature-aria",
		"creature_owner_id": "test-owner"
	})
	candidates = tracker.call("_creature_candidates")
	assert(candidates.size() == 1)
	assert(String(candidates[0].get("creature_id", "")) == "creature-borin")

	# Modern combat snapshots preserve both logical creature and scene token.
	var state: Dictionary = {
		"version": 1,
		"active": true,
		"entries": (tracker.get("entries") as Array).duplicate(true),
		"active_index": 0,
		"round": 1,
		"turn_count": 0,
		"next_entry_id": 2
	}
	assert(bool(tracker.call("valid_state", state)))
	assert(bool(tracker.call("load_state", state)))
	var restored: Dictionary = tracker.call("get_save_state")
	var restored_entries: Array = restored.get("entries", [])
	assert(
		String((restored_entries[1] as Dictionary).get("creature_id", ""))
		== "creature-aria"
	)

	# Initiative snapshots derive names from live tokens, not obsolete archives.
	linked.call("set_display_name", "Aria rinominata")
	var updated_snapshot: Dictionary = tracker.call("get_save_state")
	assert(String(updated_snapshot.entries[1].name) == "Aria rinominata")

	var invalid: Dictionary = state.duplicate(true)
	invalid.entries[0]["token_id"] = ""
	assert(not bool(tracker.call("valid_state", invalid)))

	# Legacy snapshots without creature IDs are still accepted.
	var legacy: Dictionary = state.duplicate(true)
	legacy.entries[0].erase("creature_id")
	legacy.entries[0].erase("creature_owner_id")
	assert(bool(tracker.call("valid_state", legacy)))

	# A legacy state can omit or carry a stale ID counter. Adding a real
	# selected creature must still produce a valid, unique snapshot.
	var stale_counter: Dictionary = state.duplicate(true)
	stale_counter.erase("next_entry_id")
	assert(bool(tracker.call("load_state", stale_counter)))
	var ui := CanvasLayer.new()
	board.add_child(ui)
	tracker.set("ui_root", ui)
	tracker.call("_build_add_dialog")
	tracker.call("_refresh_creature_selector")
	var chooser: ItemList = tracker.get("participant_creatures") as ItemList
	chooser.select(0)
	tracker.call("_on_add_confirmed")
	var after_add: Dictionary = tracker.call("get_save_state")
	assert(after_add.entries.size() == 3)
	assert(after_add.entries[1].id == "initiative_1" and after_add.entries[2].id == "initiative_2")
	assert(bool(tracker.call("valid_state", after_add)), "Restored combat must not allocate duplicate entry IDs")

	var capacity_state: Dictionary = state.duplicate(true)
	capacity_state["entries"] = []
	for index: int in range(257):
		capacity_state.entries.append({"id": "capacity_%d" % index, "name": "Creature %d" % index, "token_id": ""})
	assert(not bool(tracker.call("load_state", capacity_state)), "Environment migration must respect snapshot capacity")
	assert((tracker.call("get_save_state") as Dictionary).entries.size() == 3, "Rejected state must not change current combat")
	capacity_state.entries.pop_back()
	assert(bool(tracker.call("load_state", capacity_state)))
	assert(bool(tracker.call("valid_state", tracker.call("get_save_state"))), "Largest migrated combat must serialize validly")

	assert(unlinked != null)
	board.free()
	print("PASS: initiative picks only on-board creatures, de-duplicates and saves identity")
	quit()
