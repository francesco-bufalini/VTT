extends SceneTree
const Roller = preload("res://vtt/dice_roller_chat.gd")
const Controller = preload("res://vtt/map_data_controller.gd")
class MemoryRoller:
	extends "res://vtt/dice_roller_chat.gd"
	func _save_history() -> void:
		pass
	func _load_history() -> void:
		history.clear()
		seen_ids.clear()
func _initialize() -> void:
	call_deferred("run")
func wait_for(predicate: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(predicate.call(), "Mobile chat round trip timed out")
func run() -> void:
	var host := Node.new()
	root.add_child(host)
	var ui := CanvasLayer.new()
	host.add_child(ui)
	var desktop := MemoryRoller.new()
	desktop.name = "DiceRollerChat"
	host.add_child(desktop)
	desktop.setup(host, "test-chat-mobile", Callable(), ui, false)
	var sync: Node = load("res://network/board_sync.gd").new()
	host.add_child(sync)
	sync.board_root = host
	var server := Controller.new()
	host.add_child(server)
	server.use_board(func() -> Dictionary: return {"version": 1, "mobile_protocol": 3, "tokens": [], "combat": {"active": false, "round": 1, "active_index": -1, "entries": []}})
	server.set_action_provider(Callable(sync, "_handle_mobile_action"))
	server.port = 0
	for attempt in range(10):
		assert(server.serve(true, "test-chat-mobile") == OK)
		if server._action_server.is_listening():
			break
	assert(server._action_server.is_listening())
	var client := Controller.new()
	host.add_child(client)
	client.port = server._udp.get_local_port()
	assert(client.connect_remote("127.0.0.1", "test-chat-mobile") == OK)
	await wait_for(func() -> bool: return not client.get_map_data().is_empty())
	var mobile := MemoryRoller.new()
	host.add_child(mobile)
	mobile.setup(host, "test-chat-mobile", Callable(), ui, false)
	mobile.configure_mobile_connection(client, func() -> Array: return [{"id": "owner:hero", "name": "Eroe"}], func() -> Dictionary: return {"id": "hero", "owner_id": "owner", "name": "Eroe"})
	mobile.set_session_key("test-chat-mobile")
	mobile.actor_picker.select(1)
	mobile._roll("d6")
	assert(mobile.history.back().author == "Eroe" and mobile.history.back().actor_id == "owner:hero")
	mobile._process(1.6)
	await wait_for(func() -> bool: return desktop.history.size() == 1)
	assert(desktop.history.back().id == mobile.history.back().id)
	desktop.chat_input.text = "Dal desktop al telefono"
	desktop._send_chat()
	mobile._process(1.6)
	await wait_for(func() -> bool: return mobile.history.size() == 2)
	assert(mobile.history.back().text == "Dal desktop al telefono")
	mobile.actor_picker.select(0)
	mobile._roll("d20")
	assert(not mobile.history.back().has("actor_id") and not mobile.history.back().has("actor"), "Explicit None must bypass selected creature")
	mobile._process(1.6)
	await wait_for(func() -> bool: return desktop.history.size() == 3)
	assert(desktop.accept_shared_event(mobile.history.back()))
	assert(desktop.history.size() == 3, "Retries must not duplicate events")
	print("PASS: real mobile TCP chat in both directions, creature dice attribution, explicit None and retry deduplication")
	client.disconnect_remote()
	server.serve(false, "test-chat-mobile")
	host.queue_free()
	await process_frame
	quit()