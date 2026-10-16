extends SceneTree
const Controller = preload("res://vtt/map_data_controller.gd")

func _initialize() -> void:
	call_deferred("run")

func wait_until(predicate: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 7000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(predicate.call(), "Callback transport regression timed out")

func run() -> void:
	var server := Controller.new()
	root.add_child(server)
	server.use_board(func() -> Dictionary: return {"version": 1, "tokens": [], "combat": {}})
	server.set_action_provider(func(_action: String, _payload: Dictionary) -> Dictionary: return {"ok": true})
	server.port = 0
	for attempt: int in range(10):
		assert(server.serve(true, "callbacks") == OK)
		if server._action_server.is_listening():
			break
	assert(server._action_server.is_listening())
	var client := Controller.new()
	root.add_child(client)
	client.port = server._udp.get_local_port()
	assert(client.connect_remote("127.0.0.1", "callbacks") == OK)
	var completed: Dictionary = {}
	client.action_completed.connect(func(id: String, _action: String, result: Dictionary) -> void:
		assert(not completed.has(id), "A callback must complete each request only once")
		completed[id] = result
		if completed.size() == 1 and bool(result.get("ok", false)):
			client.disconnect_remote())
	var first := client.request_action("snapshot", {})
	var second := client.request_action("snapshot", {})
	assert(not first.is_empty() and not second.is_empty())
	await wait_until(func() -> bool: return completed.size() == 2)
	assert(completed.has(first) and completed.has(second) and client._actions.is_empty())
	# A fresh request must remain usable after closing from a result callback.
	assert(client.connect_remote("127.0.0.1", "callbacks") == OK)
	var next := client.request_action("snapshot", {})
	await wait_until(func() -> bool: return completed.has(next))
	assert(completed[next].ok)

	var closing := Controller.new()
	root.add_child(closing)
	closing.set_process(false)
	closing._host = "127.0.0.1"
	closing._session = "callbacks"
	closing._actions.append({"peer": StreamPeerTCP.new(), "client": true, "id": "closing", "action": "snapshot"})
	var cancellations: Array[String] = []
	closing.action_completed.connect(func(id: String, _action: String, _result: Dictionary) -> void:
		cancellations.append(id)
		if cancellations.size() == 1:
			assert(closing.request_action("snapshot", {}).is_empty(), "Close callbacks must already see an offline connection")
			closing.disconnect_remote())
	closing.disconnect_remote()
	assert(cancellations == ["closing"] and closing._actions.is_empty(),
		"Recursive disconnect must not notify or process the same request twice")
	client.disconnect_remote()
	server.serve(false, "callbacks")
	client.queue_free()
	closing.queue_free()
	server.queue_free()
	await process_frame
	print("PASS: disconnect from TCP completion, reconnection, single cancellation and reentrant close")
	quit()