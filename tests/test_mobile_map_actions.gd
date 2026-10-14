extends SceneTree
const Controller = preload("res://vtt/map_data_controller.gd")
const Mobile = preload("res://vtt/mobile/creatures_mobile.tscn")

class Board:
	extends Node3D
	var cell_size := 1.0
	var undo_count := 0
	func _identity_profile_by_id(id: String) -> Dictionary:
		return {"id": id} if id == "mobile_test_miniature" else {}
	func apply_creature_sheet_appearance(_token: CharacterBody3D, _creature: Dictionary) -> void:
		pass
	func push_undo_state() -> void:
		undo_count += 1
	func is_2d_view_enabled() -> bool:
		return false
	func _sync_explicit_token_change(_token: CharacterBody3D) -> void:
		pass

class RequestSpy:
	extends Node
	var captured: Dictionary = {}
	func get_map_data() -> Dictionary:
		return {"tokens": [{"id": "attacker-stable-id", "name": "Hero"}]}
	func request_action(action: String, payload: Dictionary) -> String:
		captured = {"action": action, "payload": payload.duplicate(true)}
		return "attack-request"

func _initialize() -> void:
	call_deferred("run")

func wait_until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 6000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(predicate.call())

func run() -> void:
	var board := Board.new()
	root.add_child(board)
	var sync: Node = load("res://network/board_sync.gd").new()
	board.add_child(sync)
	sync.board_root = board
	sync.tokens_root = board
	sync.token_scene = load("res://token.tscn")
	sync.auto_sync_enabled = false
	var support: CharacterBody3D = sync.token_scene.instantiate()
	board.add_child(support)
	support.global_position = Vector3(4.5, 3, 6.5)
	support.call("set_display_name", "Support token")
	var support_id: String = sync.get_sync_id_for_node(support)
	var creature := {"id": "mobile_creature", "owner_id": "mobile_owner_1234567890",
		"name": "Mobile hero", "current_miniature_id": "mobile_test_miniature",
		"default_miniature_id": "mobile_test_miniature", "footprint": 1.0, "size_name": "Medium", "reach_feet": 10, "conditions": ["poisoned"]}
	var placed: Dictionary = await sync._handle_mobile_action("place_token", {"token_id": support_id, "creature": creature})
	assert(placed.ok, "Mobile public creature must be placed")
	var hero: CharacterBody3D = sync._visible_mobile_token(placed.token_id)
	assert(hero != null and hero != support)
	assert(is_equal_approx(hero.global_position.y - hero.token_height_cells * hero.cell_size * 0.5, support.global_position.y + support.token_height_cells * support.cell_size * 0.5), "Creature base must rest on selected hitbox top")
	assert(hero.get_meta("creature_owner_id") == creature.owner_id)
	assert(hero.get_reach_feet() == 10 and hero.get_conditions() == ["poisoned"])
	var repeated: Dictionary = await sync._handle_mobile_action("place_token", {"token_id": support_id, "creature": creature})
	assert(repeated.token_id == placed.token_id, "Repeated placement must retain the stable ID")
	assert(get_nodes_in_group("dnd_token").size() == 2, "Repeated placement must not duplicate tokens")
	var invalid: Dictionary = await sync._handle_mobile_action("snapshot", {"token_id": "absent"})
	assert(not invalid.ok)
	print("PASS: remote placement on hitbox top, owner identity and idempotent token reuse")
	if DisplayServer.get_name() != "headless":
		var floor_mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(100, 100)
		floor_mesh.mesh = plane
		board.add_child(floor_mesh)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color("304a68")
		floor_mesh.material_override = material
		var old_camera := Camera3D.new()
		board.add_child(old_camera)
		old_camera.position = Vector3(40, 50, 60)
		var before := old_camera.transform
		var captured: Dictionary = await sync._handle_mobile_action("snapshot", {"token_id": placed.token_id,
			"field_feet": 120, "attack": {"range_feet": 20, "long_range_feet": 60, "melee": false}})
		assert(captured.ok and captured.contours.size() == 2)
		assert(old_camera.transform == before, "Mobile capture must not move the desktop camera")
		var found_center := false
		for marker: Dictionary in captured.markers:
			if marker.selected:
				found_center = absf(marker.x - 512) < 1 and absf(marker.y - 384) < 1
		assert(found_center, "Selected token must be centered in the snapshot")
		var image := Image.new()
		assert(image.load_webp_from_buffer(Marshalls.base64_to_raw(captured.image)) == OK)
		image.save_png("res://build/mobile-map-capture-test.png")
		print("PASS: real WebP board capture, centered token, two range contours and unchanged desktop camera")
	var desktop := Controller.new()
	board.add_child(desktop)
	desktop.use_board(sync.get_tactical_map_data)
	var payload_size := 220000
	desktop.set_action_provider(func(action: String, payload: Dictionary) -> Dictionary:
		return {"ok": true, "action": action, "token_id": payload.get("token_id", ""), "blob": "x".repeat(payload_size)})
	desktop.port = 0
	assert(desktop.serve(true, "mobile-actions-test") == OK)
	assert(desktop._action_server.is_listening())
	var client := Controller.new()
	board.add_child(client)
	client.port = desktop._udp.get_local_port()
	assert(client.connect_remote("127.0.0.1", "mobile-actions-test") == OK)
	assert(await wait_until(func() -> bool: return not client.get_map_data().is_empty()))
	var responses: Array[Dictionary] = []
	client.action_completed.connect(func(_id: String, _action: String, result: Dictionary) -> void: responses.append(result))
	assert(not client.request_action("snapshot", {"token_id": support_id}).is_empty())
	assert(await wait_until(func() -> bool: return responses.size() == 1))
	assert(responses[0].ok and responses[0].blob.length() == payload_size, "TCP must deliver a multi-packet compressed-image-sized payload")
	client._session = "wrong-session"
	client.request_action("snapshot", {"token_id": support_id})
	assert(await wait_until(func() -> bool: return responses.size() == 2))
	assert(not responses[1].ok, "Wrong session must not receive data")
	client.disconnect_remote()
	print("PASS: real TCP framing, large image payload, UDP polling and session rejection")
	board.queue_free()
	await process_frame
	var mobile := Mobile.instantiate()
	root.size = Vector2i(480, 960)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.add_child(mobile)
	for i: int in range(8):
		await process_frame
	assert(absf(mobile._page_menu_button.position.y - (mobile.get_viewport_rect().size.y * 0.5 - 50)) < 2)
	var actions: Node = mobile._session_actions
	assert(actions.reopen_button.position.y > mobile._page_menu_button.position.y)
	actions._choose_token(func(_id: String) -> void: pass, "Token")
	assert(actions.picker.visible)
	mobile._go_back()
	assert(not actions.picker.visible)
	var spy := RequestSpy.new()
	root.add_child(spy)
	actions.controller = spy
	actions.request_attack_snapshot({"id": "hero", "linked_token_sync_id": "attacker-stable-id"},
		{"range_feet": 80, "long_range_feet": 320, "melee": false})
	assert(spy.captured.action == "snapshot" and spy.captured.payload.token_id == "attacker-stable-id")
	assert(spy.captured.payload.attack.range_feet == 80 and spy.captured.payload.attack.long_range_feet == 320)
	print("PASS: mobile attack range requests its linked creature viewpoint and both calculated ranges")
	spy.queue_free()
	var image := Image.create(64, 48, false, Image.FORMAT_RGB8)
	image.fill(Color.DARK_GREEN)
	var image_data := {"ok": true, "format": "webp", "image": Marshalls.raw_to_base64(image.save_webp_to_buffer()), "title": "Hero", "field_feet": 120}
	actions._pending_snapshot = "test"
	actions._on_action_completed("test", "snapshot", image_data)
	assert(not actions.reopen_button.disabled and actions.canvas.texture != null)
	actions.reopen_button.pressed.emit()
	assert(actions.viewer.visible)
	mobile._go_back()
	assert(not actions.viewer.visible and actions.canvas.texture != null, "Closing preserves cached snapshot")
	print("PASS: centered floating icons, Back, cached WebP snapshot and reopen")
	mobile.queue_free()
	await process_frame
	quit()
