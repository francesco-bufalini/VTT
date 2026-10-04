extends SceneTree

const InitiativeTracker = preload("res://vtt/initiative_tracker.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var tracker: Node = InitiativeTracker.new()
	root.add_child(tracker)

	var state := {
		"version": 1,
		"active": true,
		"entries": [
			{
				"id": "initiative_1",
				"name": "Sariel",
				"token_id": "path:Tokens/Sariel"
			},
			{
				"id": "initiative_2",
				"name": "Kaos",
				"token_id": ""
			},
			{
				"id": "initiative_3",
				"name": "Kryss",
				"token_id": "path:Tokens/Kryss"
			}
		],
		"active_index": 0,
		"round": 1,
		"turn_count": 0,
		"next_entry_id": 4
	}

	assert(bool(tracker.call("valid_state", state)))
	assert(bool(tracker.call("load_state", state)))

	var loaded: Dictionary = tracker.call("get_save_state")
	assert(bool(loaded.get("active", false)))
	assert(int(loaded.get("active_index", -1)) == 0)
	assert(int(loaded.get("round", 0)) == 1)
	assert(int(loaded.get("turn_count", -1)) == 0)
	var entries: Array = loaded.get("entries", [])
	assert(entries.size() == 3)
	assert(
		String((entries[0] as Dictionary).get("token_id", ""))
		== "path:Tokens/Sariel"
	)

	tracker.call("next_turn")
	var after_next: Dictionary = tracker.call("get_save_state")
	assert(int(after_next.get("active_index", -1)) == 1)
	assert(int(after_next.get("round", 0)) == 1)
	assert(int(after_next.get("turn_count", -1)) == 1)

	tracker.call("next_turn")
	tracker.call("next_turn")
	var wrapped: Dictionary = tracker.call("get_save_state")
	assert(int(wrapped.get("active_index", -1)) == 0)
	assert(int(wrapped.get("round", 0)) == 2)
	assert(int(wrapped.get("turn_count", -1)) == 3)

	tracker.call("previous_turn")
	var after_previous: Dictionary = tracker.call("get_save_state")
	assert(int(after_previous.get("active_index", -1)) == 2)
	assert(int(after_previous.get("round", 0)) == 1)
	assert(int(after_previous.get("turn_count", -1)) == 2)

	var duplicate_state: Dictionary = state.duplicate(true)
	var duplicate_entries: Array = duplicate_state.get("entries", [])
	(duplicate_entries[1] as Dictionary)["id"] = "initiative_1"
	assert(not bool(tracker.call("valid_state", duplicate_state)))

	print(
		"PASS: initiative order, linked token IDs, rounds and turn navigation"
	)
	tracker.queue_free()
	quit()
