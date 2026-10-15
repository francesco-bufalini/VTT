extends SceneTree
const Controller = preload("res://vtt/map_data_controller.gd")

func _initialize() -> void:
	call_deferred("run")

func wait_until(predicate: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(predicate.call(), "Transport result must arrive without waiting for the 15-second action timeout")

func run() -> void:
	var huge := "x".repeat(Controller.ACTION_MAX_BYTES)
	assert(Controller._action_frame({"data": huge}).is_empty())
	assert(not Controller._action_frame({"data": "x".repeat(Controller.ACTION_MAX_BYTES - 1024)}).is_empty())
	var server := Controller.new()
	root.add_child(server)
	server.use_board(func() -> Dictionary: return {"version": 1, "tokens": [], "combat": {}})
	server.set_action_provider(func(action: String, _payload: Dictionary) -> Dictionary:
		return {"ok": true, "data": huge} if action == "snapshot" else {"ok": true, "small": true})
	server.port = 0
	for attempt: int in range(10):
		assert(server.serve(true, "size-regression") == OK)
		if server._action_server.is_listening():
			break
	assert(server._action_server.is_listening())
	var client := Controller.new()
	root.add_child(client)
	client.port = server._udp.get_local_port()
	assert(client.connect_remote("127.0.0.1", "size-regression") == OK)
	var statuses: Array[String] = []
	client.status_changed.connect(func(message: String) -> void: statuses.append(message))
	for attempt: int in range(5):
		assert(client.request_action("chat_send", {"event": huge}).is_empty())
	assert(client._actions.is_empty(), "Oversized requests must not consume queue slots or open connections")
	assert(statuses.size() == 5 and "troppo grande" in statuses[0])
	var results: Dictionary = {}
	client.action_completed.connect(func(id: String, _action: String, result: Dictionary) -> void:
		results[id] = result)
	var oversized := client.request_action("snapshot", {})
	assert(not oversized.is_empty())
	await wait_until(func() -> bool: return results.has(oversized))
	assert(not bool(results[oversized].get("ok", true)) and "troppo grande" in String(results[oversized].get("error", "")),
		"Oversized provider output must return a valid framed error")
	var normal := client.request_action("move_token", {})
	assert(not normal.is_empty())
	await wait_until(func() -> bool: return results.has(normal))
	assert(results[normal].ok and results[normal].small, "The next normal request must still succeed")
	client.disconnect_remote()
	server.serve(false, "size-regression")
	client.queue_free()
	server.queue_free()
	await process_frame
	print("PASS: bounded outgoing requests, explicit oversized TCP response errors and recovery on the next action")
	quit()