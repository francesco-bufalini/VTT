extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: Node = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var sync: Node = scene.board_sync
	var initiative: Node = scene.initiative_tracker
	assert(sync != null)
	assert(initiative != null)

	var tokens: Array[Node] = get_nodes_in_group("dnd_token")
	var token: Node = null
	for candidate: Node in tokens:
		if scene.is_ancestor_of(candidate):
			token = candidate
			break
	assert(token != null)
	assert(token.has_method("set_display_name"))
	assert(token.has_method("set_conditions"))

	token.call("set_display_name", "Sync Hero")
	token.call("set_conditions", ["poisoned", "concentrating"])
	var token_id: String = String(sync.call("_sync_id", token))

	var initiative_state := {
		"version": 1,
		"active": true,
		"entries": [
			{
				"id": "initiative_1",
				"name": "Sync Hero",
				"token_id": token_id
			}
		],
		"active_index": 0,
		"round": 3,
		"turn_count": 7,
		"next_entry_id": 2
	}
	assert(initiative.call("load_state", initiative_state))

	# Force the same JSON round-trip used by BoardSync over TCP.
	var data: Dictionary = JSON.parse_string(JSON.stringify(sync.create_snapshot()))
	assert(int(data.get("version", -1)) == preload("res://network/board_sync.gd").SNAPSHOT_VERSION)
	assert(sync.valid_snapshot(data))
	assert(not data.encounter.is_empty())
	assert(data.initiative.active)
	assert(data.initiative.entries.size() == 1)

	var serialized_token: Dictionary = {}
	for item: Variant in data.objects:
		if item is Dictionary and String(item.get("id", "")) == token_id:
			serialized_token = item as Dictionary
			break
	assert(not serialized_token.is_empty())
	assert(serialized_token.display_name == "Sync Hero")
	assert(serialized_token.conditions == ["poisoned", "concentrating"])

	# Destroy the logical state locally, then verify snapshot restoration.
	token.call("set_display_name", "")
	token.call("set_conditions", [])
	initiative.call("clear_state")
	scene.encounter.round_number += 1

	assert(sync.apply_snapshot(data))
	assert(scene.encounter.round_number == int(data.encounter.round_number))
	assert(String(token.call("get_display_name")) == "Sync Hero")
	assert(token.call("get_conditions") == ["poisoned", "concentrating"])

	var restored_initiative: Dictionary = initiative.call("get_save_state")
	assert(restored_initiative.active)
	assert(restored_initiative.entries.size() == 1)
	assert(restored_initiative.entries[0].name == "Sync Hero")
	assert(restored_initiative.entries[0].token_id == token_id)
	assert(restored_initiative.active_index == 0)
	assert(restored_initiative.round == 3)
	assert(restored_initiative.turn_count == 7)

	var again: Dictionary = sync.create_snapshot()
	assert(again.objects.size() == data.objects.size())
	assert(again.initiative.active)
	assert(again.initiative.entries.size() == 1)

	scene.encounter.is_advancing = true
	assert(sync.create_snapshot().is_empty())
	assert(not sync.apply_snapshot(data))
	scene.encounter.is_advancing = false

	scene.queue_free()
	await process_frame
	print("PASS: encounter + token metadata + initiative snapshot round-trip")
	quit()
