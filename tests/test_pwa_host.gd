extends SceneTree

var _test_port := 0

func _initialize() -> void:
	call_deferred("run")


func http(method: String, path: String, body: String = "", extra: String = "") -> String:
	var peer := StreamPeerTCP.new()
	assert(peer.connect_to_host("127.0.0.1", _test_port) == OK)
	var end := Time.get_ticks_msec() + 5000
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < end:
		peer.poll()
		await process_frame
	assert(peer.get_status() == StreamPeerTCP.STATUS_CONNECTED, "PWA localhost bridge not listening")
	var request := "%s %s HTTP/1.1\r\nHost: 127.0.0.1:8765\r\nConnection: close\r\n" % [method, path]
	if method == "POST":
		request += "Content-Type: application/json\r\nContent-Length: %d\r\n" % body.to_utf8_buffer().size()
	request += extra + "\r\n" + body
	assert(peer.put_data(request.to_utf8_buffer()) == OK)
	var result := PackedByteArray()
	while Time.get_ticks_msec() < end:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var size := peer.get_available_bytes()
		if size > 0:
			var read := peer.get_data(size)
			assert(read[0] == OK)
			result.append_array(read[1])
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		await process_frame
	peer.disconnect_from_host()
	assert(not result.is_empty(), "No HTTP response from PWA localhost bridge")
	return result.get_string_from_utf8()


func run() -> void:
	await process_frame
	await process_frame
	var creature_area_script: Script = load("res://vtt/creature_area.gd")
	var creature_archive_script: Script = load("res://vtt/creature_archive.gd")
	var token_list_script: Script = load("res://vtt/token_list.gd")
	assert(creature_area_script != null and creature_archive_script != null and token_list_script != null,
		"Creature archive and token-list batch UI scripts must compile")
	var serve_helper: Script = load("res://network/tailscale_serve.gd")
	var empty_config: Dictionary = serve_helper.call("parse_serve_status", {})
	assert(not bool(empty_config.active))
	var ours: Dictionary = serve_helper.call("parse_serve_status", {
		"Web": {"example.ts.net:443": {"Handlers": {
			"/": {"Proxy": "http://127.0.0.1:8765/"}
		}}},
		"TCP": {"443": {"HTTPS": true}}
	})
	assert(bool(ours.active) and not bool(ours.other_rules))
	var competitor: Dictionary = serve_helper.call("parse_serve_status", {
		"TCP": {"443": {"HTTPS": true}, "9000": {"TCPForward": "127.0.0.1:9000"}}
	})
	assert(bool(competitor.other_rules), "Other TCP mappings are not managed by VTT")
	var shared: Dictionary = serve_helper.call("parse_serve_status", {
		"Web": {"example.ts.net:443": {"Handlers": {
			"/": {"Proxy": "http://127.0.0.1:8765"},
			"/another": {"Proxy": "http://127.0.0.1:9999"}
		}}}
	})
	assert(bool(shared.active) and bool(shared.other_rules))
	var foreign: Dictionary = serve_helper.call("parse_serve_status", {
		"Web": {"example.ts.net:443": {"Handlers": {
			"/": {"Proxy": "http://127.0.0.1:3000"}
		}}}
	})
	assert(not bool(foreign.active) and bool(foreign.other_rules))
	var host := root.get_node_or_null("/root/PwaHost")
	assert(host != null, "Desktop PWA autoload missing")
	# Exercise opt-in cross-PWA sharing without any live board or network.
	# _handle_share uses the same response writer as the authenticated route.
	var sender_id := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	var sender_token := "1111111111111111111111111111111111111111111111111111111111111111"
	var receiver_token := "2222222222222222222222222222222222222222222222222222222222222222"
	var receiver_id := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	var stranger_id := "cccccccccccccccccccccccccccccccc"
	var transfer_id := "dddddddddddddddddddddddddddddddd"
	var fake_client: Dictionary = {"out": PackedByteArray()}
	var fake_clients: Array = host.get("_clients")
	fake_clients.append(fake_client)
	for row: Dictionary in [
		{"device_id": sender_id, "device_token": sender_token, "device_name": "Computer A"},
		{"device_id": receiver_id, "device_token": receiver_token, "device_name": "iPhone B"}
	]:
		fake_client.out = PackedByteArray()
		host.call("_handle_share", fake_client, "/api/share/peers", JSON.stringify(row).to_utf8_buffer())
		assert((fake_client.out as PackedByteArray).get_string_from_utf8().begins_with("HTTP/1.1 200"),
			"Paired browsers must be discoverable")
	var content := "{\"format\":\"vtt_homebrew_share_v1\",\"version\":1}"
	var encoded := Marshalls.raw_to_base64(content.to_utf8_buffer())
	fake_client.out = PackedByteArray()
	host.call("_handle_share", fake_client, "/api/share/chunk", JSON.stringify({
		"device_id": sender_id, "device_token": sender_token, "recipient_id": receiver_id,
		"transfer_id": transfer_id, "kind": "homebrew", "title": "Test",
		"size": content.to_utf8_buffer().size(), "index": 0, "parts": 1, "data": encoded
	}).to_utf8_buffer())
	assert((fake_client.out as PackedByteArray).get_string_from_utf8().begins_with("HTTP/1.1 200"),
		"Bounded chunks must reach a paired recipient")
	fake_client.out = PackedByteArray()
	host.call("_handle_share", fake_client, "/api/share/peers", JSON.stringify({
		"device_id": receiver_id, "device_token": receiver_token, "device_name": "iPhone B"
	}).to_utf8_buffer())
	var inbox_reply: String = (fake_client.out as PackedByteArray).get_string_from_utf8()
	assert(inbox_reply.contains("\"inbox\"") and inbox_reply.contains(transfer_id),
		"The receiver should discover the complete incoming package")
	fake_client.out = PackedByteArray()
	host.call("_handle_share", fake_client, "/api/share/pull", JSON.stringify({
		"device_id": stranger_id, "device_token": receiver_token, "transfer_id": transfer_id, "index": 0
	}).to_utf8_buffer())
	assert(not (fake_client.out as PackedByteArray).get_string_from_utf8().begins_with("HTTP/1.1 200"),
		"Another device must not read the transfer")
	fake_client.out = PackedByteArray()
	host.call("_handle_share", fake_client, "/api/share/pull", JSON.stringify({
		"device_id": receiver_id, "device_token": receiver_token, "transfer_id": transfer_id, "index": 0
	}).to_utf8_buffer())
	assert((fake_client.out as PackedByteArray).get_string_from_utf8().contains(encoded),
		"Recipient should receive the original bytes")
	fake_client.out = PackedByteArray()
	host.call("_handle_share", fake_client, "/api/share/ack", JSON.stringify({
		"device_id": receiver_id, "device_token": receiver_token, "transfer_id": transfer_id
	}).to_utf8_buffer())
	assert((fake_client.out as PackedByteArray).get_string_from_utf8().begins_with("HTTP/1.1 200"))
	assert(not (host.get("_share_deliveries") as Dictionary).has(transfer_id),
		"Acknowledgment must remove temporary transfer data")
	fake_clients.erase(fake_client)
	(host.get("_share_peers") as Dictionary).clear()

	# The bridge is intentionally disabled without a playable board scene.
	assert(not (host.get("_server") as TCPServer).is_listening(),
		"PWA should not bind its HTTP port before opening the board")
	# Scontro contro Kaos inherits the VTT board logic through
	# final_encounter.gd; it must be recognized without matching dnd_base.tscn.
	var kaos_board := Node3D.new()
	kaos_board.set_script(load("res://tests/fixtures/pwa_board_descendant.gd"))
	assert(host.call("_is_board_scene", kaos_board),
		"Derived Scontro contro Kaos must be a playable PWA host")
	kaos_board.free()
	# Verify the named encounter really inherits the same board script.
	# Reading the .gd source avoids loading optional large models absent in CI.
	var kaos_source := FileAccess.get_file_as_string("res://encounter/scontro_contro_kaos.gd")
	var encounter_source := FileAccess.get_file_as_string("res://encounter/final_encounter.gd")
	assert(kaos_source.begins_with("extends \"res://encounter/final_encounter.gd\""))
	assert(encounter_source.begins_with("extends \"res://dnd_base.gd\""))
	var unrelated := Node3D.new()
	assert(not host.call("_is_board_scene", unrelated),
		"Unrelated scenes must not bind the PWA HTTP listener")
	unrelated.free()
	# Ask the OS for an unused loopback port; never compete with the live game.
	host.set("_listen_port", 0)
	assert(host.call("_start_listener") == OK, "Manual localhost test fixture could not bind")
	assert((host.get("_server") as TCPServer).is_listening(), "HTTP fixture not listening")
	_test_port = (host.get("_server") as TCPServer).get_local_port()
	assert(_test_port > 0, "OS must allocate a real fixture port")
	var page := await http("GET", "/")
	assert(page.begins_with("HTTP/1.1 200"))
	assert(page.contains("VTT Mobile"))
	assert(page.contains("/styles.css"))
	assert(page.contains("id=\"nav\""))
	var manifest := await http("GET", "/manifest.webmanifest")
	assert(manifest.contains("icon-512.png"))
	var script := await http("GET", "/storage.js")
	assert(script.contains("indexedDB.open"))
	var ui_script := await http("GET", "/ui.js")
	assert(ui_script.begins_with("HTTP/1.1 200") and ui_script.contains("openCreatureEditor"))
	# Read-only, unauthenticated telemetry must contain JS transfer health only.
	var module_diag := await http("GET", "/__vtt_module_diagnostics")
	assert(module_diag.begins_with("HTTP/1.1 200"))
	assert(module_diag.contains("\"module_events\"") and module_diag.contains("\"bytes_written\""))
	assert(module_diag.contains("\"/ui.js\"") and module_diag.contains("\"connections_peak\""))
	assert(not module_diag.contains("\"token\"") and not module_diag.contains("\"authorization\""))
	var condition_script := await http("GET", "/condition_catalog.js")
	assert(condition_script.begins_with("HTTP/1.1 200") and condition_script.contains("conditionOptions"))
	# The 5etools natural-attack catalog must reach the PWA over the Godot host;
	# otherwise the atomic offline shell fails to install and numeric rules vanish.
	var species_attacks := await http("GET", "/catalog/species_attacks.json")
	assert(species_attacks.begins_with("HTTP/1.1 200") and species_attacks.contains("application/json"),
		"Godot must serve species attack data as JSON")
	assert(species_attacks.contains("Aarakocra") and species_attacks.contains("Talons"),
		"5etools Aarakocra attacks must be available to mobile character sheets")
	var bundled_effects := await http("GET", "/catalog/effects_5etools.json")
	assert(bundled_effects.begins_with("HTTP/1.1 200") and bundled_effects.contains("Arcane Blight"),
		"Offline 5etools diseases must be served with the shell")
	var condition_catalog: Dictionary = host.call("_condition_public_catalog")
	var conditions_2014: Array = condition_catalog.editions["2014"]
	var conditions_2024: Array = condition_catalog.editions["2024"]
	assert(conditions_2014.any(func(row: Dictionary) -> bool: return row.id == "grappled" and row.name == "Grappled"))
	assert(conditions_2014.any(func(row: Dictionary) -> bool: return row.id == "grappled" and row.get("entries", []) is Array and not row.get("entries", []).is_empty()), "5etools descriptions must accompany statuses")
	assert(conditions_2014.any(func(row: Dictionary) -> bool: return row.get("category") == "diseases" and row.name == "Arcane Blight" and not row.get("entries", []).is_empty()), "Native magical diseases must be included in mobile catalog")
	assert(conditions_2014.any(func(row: Dictionary) -> bool: return row.id == "restrained" and row.name == "Restrained"))
	assert(conditions_2014.any(func(row: Dictionary) -> bool: return row.id == "hidden"))
	assert(conditions_2024.any(func(row: Dictionary) -> bool: return row.id == "5etools:effects:xphb:bloodied"))
	# Concurrent module fetches must not be disconnected when more than twelve
	# resources arrive in the same frame (old PWA_HOST active-client limit).
	var burst := {"done": 0, "failed": 0}
	var requests: Array[HTTPRequest] = []
	for _index in range(20):
		var request_node := HTTPRequest.new()
		root.add_child(request_node)
		request_node.request_completed.connect(
			func(result: int, status_code: int, _headers: PackedStringArray, response_body: PackedByteArray) -> void:
				burst["done"] = int(burst["done"]) + 1
				if result != HTTPRequest.RESULT_SUCCESS or status_code != 200 or not response_body.get_string_from_utf8().contains("openCreatureEditor"):
					burst["failed"] = int(burst["failed"]) + 1
		)
		requests.append(request_node)
		assert(request_node.request("http://127.0.0.1:%d/ui.js" % _test_port) == OK)
	var burst_deadline := Time.get_ticks_msec() + 12000
	while int(burst["done"]) < requests.size() and Time.get_ticks_msec() < burst_deadline:
		await process_frame
	assert(int(burst["done"]) == requests.size() and int(burst["failed"]) == 0,
		"PWA failed a burst of 20 simultaneous /ui.js module requests")
	for request_node in requests:
		request_node.queue_free()
	var stylesheet := await http("GET", "/styles.css")
	assert(stylesheet.begins_with("HTTP/1.1 200") and stylesheet.contains(".bottom-nav"))
	for asset: String in ["/mobile_metal_theme.css", "/catalog/combat_actions_5etools.json", "/icons/action_controls.svg", "/feature_mechanics.js"]:
		var response := await http("GET", asset)
		assert(response.begins_with("HTTP/1.1 200"), "Shared action asset missing: " + asset)
	var rules_module := await http("GET", "/sheet_rules.js")
	assert(rules_module.begins_with("HTTP/1.1 200"))
	assert(rules_module.contains("calculateSheet"))
	var ability_index := await http("GET", "/catalog/ability_grants.json")
	assert(ability_index.begins_with("HTTP/1.1 200"))
	assert(ability_index.contains("subrace"))
	var class_index := await http("GET", "/catalog/class_mechanics.json")
	assert(class_index.begins_with("HTTP/1.1 200"))
	assert(class_index.contains("hit_die"))
	var reference := await http("GET", "/catalog/backgrounds.json")
	assert(reference.begins_with("HTTP/1.1 200"))
	assert(reference.contains("backgrounds"), "Native background catalog must be served to the PWA")
	assert((await http("GET", "/catalog/secrets.json")).begins_with("HTTP/1.1 404"))
	var spells := await http("GET", "/catalog/spells.json")
	assert(spells.begins_with("HTTP/1.1 200"))
	assert(spells.contains("spells"), "Built-in spell catalog must be available offline")
	# Scoped queries must return only requested spells, not the whole compendium.
	var payload: Variant = JSON.parse_string(spells.split("\r\n\r\n", true, 1)[1])
	assert(payload is Dictionary and payload.get("spells", []) is Array)
	var reference_spell: Dictionary = payload["spells"][0]
	var scoped_reply := await http("POST", "/catalog/spells/selected",
		JSON.stringify({"ids": [reference_spell.id], "classes": []}))
	assert(scoped_reply.begins_with("HTTP/1.1 200"))
	var scoped: Dictionary = JSON.parse_string(scoped_reply.split("\r\n\r\n", true, 1)[1])
	assert(scoped.spells.size() == 1 and scoped.spells[0].id == reference_spell.id,
		"Selected spell must retain its structured definition without all catalog entries")
	var unknown_reply := await http("POST", "/catalog/spells/selected",
		JSON.stringify({"ids": ["missing-spell-id"], "classes": []}))
	assert(unknown_reply.begins_with("HTTP/1.1 200"))
	var missing: Dictionary = JSON.parse_string(unknown_reply.split("\r\n\r\n", true, 1)[1])
	assert(missing.spells.is_empty(), "Unknown IDs must not make the server return every spell")
	var class_spell: Dictionary = {}
	for candidate: Dictionary in payload.spells:
		if not candidate.get("classes", []).is_empty() and int(candidate.level) <= 1:
			class_spell = candidate
			break
	assert(not class_spell.is_empty(), "Need a low-level class spell for selection regression")
	var class_reply := await http("POST", "/catalog/spells/selected",
		JSON.stringify({"ids": [], "classes": [{"name": class_spell.classes[0],
			"max_level": 1}]}))
	assert(class_reply.begins_with("HTTP/1.1 200"))
	var class_payload: Dictionary = JSON.parse_string(class_reply.split("\r\n\r\n", true, 1)[1])
	assert(class_payload.spells.any(func(row: Dictionary) -> bool:
		return row.id == class_spell.id), "Preparation must receive known class spells")
	assert((await http("POST", "/catalog/spells/selected",
		JSON.stringify({"ids": [], "classes": [{"name": "Wizard", "max_level": 10}]}))).begins_with("HTTP/1.1 400"),
		"Invalid scoped requests must be rejected")
	var status := await http("GET", "/api/status")
	assert(status.begins_with("HTTP/1.1 200"))
	assert(status.contains("\"pairing_required\":true"))
	# PWA availability and authenticated actions do not depend on the legacy
	# LAN TCP/UDP listener: it can fail to bind while the Godot board is open.
	var local_sync: Node = load("res://network/board_sync.gd").new()
	var local_controller: Node = load("res://vtt/map_data_controller.gd").new()
	local_controller.call("use_board", func() -> Dictionary:
		return {"tokens": []})
	local_controller.call("set_action_provider", func(_action: String, _payload: Dictionary) -> Dictionary:
		return {"ok": true})
	local_sync.set("map_data_controller", local_controller)
	assert(not bool(local_sync.get("receiving")))
	assert(host.call("_web_board_controller", local_sync) == local_controller,
		"HTTPS PWA must see a local board even without the native TCP listener")
	var web_action: Dictionary = await local_controller.call("execute_web_action", "chat_poll", {})
	assert(bool(web_action.get("ok", false)),
		"Authenticated web actions should work without a legacy UDP listener")
	var tcp_action: Dictionary = await local_controller.call("execute_local_action", "chat_poll", {})
	assert(not bool(tcp_action.get("ok", false)),
		"Legacy TCP actions still require their own listener")
	local_controller.free()
	local_sync.free()
	# One-time codes are short, random, single-use and never replace the
	# strong desktop bearer used for authenticated game actions.
	var short_code: String = host.call("_new_short_code")
	assert(short_code.length() == 16 and short_code.is_valid_hex_number())
	assert((await http("POST", "/api/pair", "{\"code\":\"0000000000000000\"}")).begins_with("HTTP/1.1 401"))
	var reply := await http("POST", "/api/pair", JSON.stringify({"code":short_code}))
	assert(reply.begins_with("HTTP/1.1 200"))
	assert(reply.contains(String(host.get("_token"))))
	assert((await http("POST", "/api/pair", JSON.stringify({"code":short_code}))).begins_with("HTTP/1.1 401"),
		"The same code must not authorize two phones")
	short_code = host.call("_new_short_code")
	host.set("_short_code_expiry", Time.get_ticks_msec() - 1)
	assert((await http("POST", "/api/pair", JSON.stringify({"code":short_code}))).begins_with("HTTP/1.1 401"),
		"Expired code must be rejected")
	# A code is safe to place in a QR URL fragment, unlike the strong bearer.
	var link: String = host.call("_pair_url", "https://my-pc.tailnet.ts.net", "ABCDEF1234567890")
	assert(link == "https://my-pc.tailnet.ts.net/#pair=ABCDEF1234567890")
	assert(host.call("_pair_url", "http://untrusted.example", "ABCDEF1234567890") == "")
	# Eight bad submissions exhaust the displayed code.
	short_code = host.call("_new_short_code")
	for _attempt in range(8):
		assert(not host.call("_consume_short_code", "0000000000000000"))
	assert(not host.call("_consume_short_code", short_code),
		"Exhausted pairing code must never be accepted")
	var generator: Node = load("res://vtt/qr/qr_code.gd").new()
	var qr_texture: Texture2D = generator.call("get_texture", "https://example.ts.net/#pair=0123456789ABCDEF")
	assert(qr_texture != null and qr_texture.get_width() > 20, "QR texture failed")
	generator.free()
	assert((await http("GET", "/api/conditions")).begins_with("HTTP/1.1 401"), "Native condition catalog must require pairing")
	assert((await http("GET", "/api/map")).begins_with("HTTP/1.1 401"))
	assert((await http("POST", "/api/action", "{\"action\":\"chat_poll\",\"payload\":{}}")).begins_with("HTTP/1.1 401"))
	assert((await http("GET", "/../project.godot")).begins_with("HTTP/1.1 404"))
	assert((await http("GET", "/api/missing")).begins_with("HTTP/1.1 404"))
	assert(FileAccess.file_exists("res://pwa/icon-192.png"))
	assert(FileAccess.file_exists("res://pwa/icon-512.png"))
	host.call("_stop_listener")
	assert(not (host.get("_server") as TCPServer).is_listening(),
		"PWA port must be closed on board shutdown")
	# Simulate F5/F6 starting and closing the native board without the heavy
	# 3D assets. The scene-scoped autoload must bind and release automatically.
	var board := Node3D.new()
	board.name = "SceneLifecycleFixture"
	board.scene_file_path = "res://dnd_base.tscn"
	root.add_child(board)
	current_scene = board
	host.call("_refresh_scene_server")
	assert((host.get("_server") as TCPServer).is_listening(),
		"PWA must start automatically with the board scene")
	board.queue_free()
	await process_frame
	assert(not (host.get("_server") as TCPServer).is_listening(),
		"PWA must stop immediately when board scene exits")
	current_scene = null
	print("PASS: desktop PWA static assets, status, API authorization, scene-scope shutdown and fixed-path routing")
	quit()
