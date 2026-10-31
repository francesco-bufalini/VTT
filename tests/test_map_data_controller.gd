extends SceneTree
const Controller = preload("res://vtt/map_data_controller.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var data := {"version": 1, "tokens": [{"id": "stable-id", "name": "Hero", "conditions": ["poisoned"]}], "combat": {"active": true, "round": 2, "active_index": -1, "entries": []}}
	data["revision"] = 7
	assert(Controller.valid_data(JSON.parse_string(JSON.stringify(data))), "Tactical revisions must survive JSON transport")
	for invalid: Variant in [-1, 0.5, "1", INF, NAN, true]:
		var candidate := data.duplicate(true)
		candidate["revision"] = invalid
		assert(not Controller.valid_data(candidate))
	assert(not Controller.valid_data({"version": 1, "tokens": ["invalid"], "combat": {}}))
	var controller := Controller.new()
	root.add_child(controller)
	assert(controller.source_name() == "offline")
	assert(controller.get_map_data().is_empty())
	assert(controller.serve(true, "session") == ERR_INVALID_PARAMETER)
	controller.use_board(func() -> Dictionary: return data)
	assert(controller.source_name() == "board")
	var copy := controller.get_map_data()
	copy.tokens.clear()
	assert(controller.get_map_data().tokens.size() == 1)
	assert(controller.serve(true, "test-session") == OK)
	controller.set_action_provider(func(action: String, payload: Dictionary) -> Dictionary:
		return {"ok": true, "action": action, "payload": payload})
	var success: Dictionary = await controller.execute_web_action("move_token", {"delta": 5})
	assert(success.ok and success.action == "move_token" and success.payload.delta == 5)
	var unknown: Dictionary = await controller.execute_web_action("unregistered", {})
	assert(not unknown.ok)
	assert(controller.serve(false, "") == OK)
	controller.queue_free()
	await process_frame
	print("PASS: tactical JSON validation, local PWA actions, no native UDP/TCP listener")
	quit()
