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
	var stylesheet := await http("GET", "/styles.css")
	assert(stylesheet.begins_with("HTTP/1.1 200") and stylesheet.contains(".bottom-nav"))
	var reference := await http("GET", "/catalog/backgrounds.json")
	assert(reference.begins_with("HTTP/1.1 200"))
	assert(reference.contains("backgrounds"), "Native background catalog must be served to the PWA")
	assert((await http("GET", "/catalog/secrets.json")).begins_with("HTTP/1.1 404"))
	var spells := await http("GET", "/catalog/spells.json")
	assert(spells.begins_with("HTTP/1.1 200"))
	assert(spells.contains("spells"), "Built-in spell catalog must be available offline")
	var status := await http("GET", "/api/status")
	assert(status.begins_with("HTTP/1.1 200"))
	assert(status.contains("\"pairing_required\":true"))
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
