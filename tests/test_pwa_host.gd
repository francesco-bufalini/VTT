extends SceneTree

func _initialize() -> void:
	call_deferred("run")


func http(method: String, path: String, body: String = "", extra: String = "") -> String:
	var peer := StreamPeerTCP.new()
	assert(peer.connect_to_host("127.0.0.1", 8765) == OK)
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
	var host := root.get_node_or_null("/root/PwaHost")
	assert(host != null and (host.get("_server") as TCPServer).is_listening(), "Desktop PWA autoload inactive")
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
	var status := await http("GET", "/api/status")
	assert(status.begins_with("HTTP/1.1 200"))
	assert(status.contains("\"pairing_required\":true"))
	assert((await http("GET", "/api/map")).begins_with("HTTP/1.1 401"))
	assert((await http("POST", "/api/action", "{\"action\":\"chat_poll\",\"payload\":{}}")).begins_with("HTTP/1.1 401"))
	assert((await http("GET", "/../project.godot")).begins_with("HTTP/1.1 404"))
	assert((await http("GET", "/api/missing")).begins_with("HTTP/1.1 404"))
	assert(FileAccess.file_exists("res://pwa/icon-192.png"))
	assert(FileAccess.file_exists("res://pwa/icon-512.png"))
	print("PASS: desktop PWA static assets, status, API authorization and fixed-path routing")
	quit()
