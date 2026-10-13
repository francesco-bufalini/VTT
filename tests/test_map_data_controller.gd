extends SceneTree
const Controller = preload("res://vtt/map_data_controller.gd")
const Mobile = preload("res://vtt/mobile/creatures_mobile.tscn")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var data := {"version": 1, "tokens": [{"id": "stable-id", "name": "Hero", "conditions": ["poisoned"]}], "combat": {"active": true, "round": 2, "active_index": -1, "entries": []}}
	var desktop := Controller.new()
	root.add_child(desktop)
	desktop.use_board(func() -> Dictionary: return data)
	assert(desktop.source_name() == "board")
	var copy := desktop.get_map_data()
	copy.tokens.clear()
	assert(desktop.get_map_data().tokens.size() == 1)
	desktop.port = 0
	assert(desktop.serve(true, "test-session") == OK)
	var client := Controller.new()
	root.add_child(client)
	client.port = desktop._udp.get_local_port()
	assert(client.connect_remote("127.0.0.1", "test-session") == OK)
	assert(client.source_name() == "tailscale")
	var deadline := Time.get_ticks_msec() + 3000
	while client.get_map_data().is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	var expected: Dictionary = JSON.parse_string(JSON.stringify(data))
	assert(client.get_map_data() == expected, "Real UDP request/response must match the local board data")
	client._accept({"magic": Controller.MAGIC, "session": "wrong", "kind": "response", "request_id": client._pending_id, "data": {}}, "127.0.0.1", client.port)
	assert(client.get_map_data() == expected, "Wrong session must not change data")
	client._last_received = Time.get_ticks_msec() - Controller.TIMEOUT_MS - 1
	client._process(0.0)
	assert(client.get_map_data().is_empty(), "Timed-out data must not remain current")
	client.disconnect_remote()
	assert(client.get_map_data().is_empty() and client.source_name() == "offline")
	assert(client.connect_remote("invalid", "test") == ERR_INVALID_PARAMETER)
	assert(not Controller.valid_data({"version": 1, "tokens": ["invalid"], "combat": {}}))
	var mobile := Mobile.instantiate()
	root.add_child(mobile)
	await process_frame
	assert(mobile.map_data_controller.source_name() == "offline")
	assert(root.find_children("*", "Node3D", true, false).is_empty())
	var sheet: Node = mobile.get_node("CreatureArea")
	sheet.set_map_data_controller(desktop)
	assert(sheet.get_linked_map_status({"linked_token_sync_id": "stable-id"}).name == "Hero")
	assert(sheet.get_linked_map_status({"linked_token_sync_id": "absent"}).is_empty())
	mobile.queue_free()
	client.queue_free()
	desktop.queue_free()
	await process_frame
	print("PASS: local/remote map data, UDP session isolation, detached data, mobile shell and stable sheet links")
	quit()