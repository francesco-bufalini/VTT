extends Node
## Loopback-only HTTP bridge. HTTPS termination is provided by Tailscale Serve
## or another trusted reverse proxy. No second application/server is required.
## An explicit random pairing secret protects the session-scoped game endpoints.

const MapDataController = preload("res://vtt/map_data_controller.gd")
const PORT := 8765
const HEADER_LIMIT := 16384
const BODY_LIMIT := 2 * 1024 * 1024
const TIMEOUT_MS := 15000
const TOKEN_PATH := "user://pwa_pairing_token.txt"
const FILES := {
	"/": ["res://pwa/index.html", "text/html; charset=utf-8"],
	"/index.html": ["res://pwa/index.html", "text/html; charset=utf-8"],
	"/client.js": ["res://pwa/client.js", "text/javascript; charset=utf-8"],
	"/main.js": ["res://pwa/main.js", "text/javascript; charset=utf-8"],
	"/storage.js": ["res://pwa/storage.js", "text/javascript; charset=utf-8"],
	"/sw.js": ["res://pwa/sw.js", "text/javascript; charset=utf-8"],
	"/manifest.webmanifest": ["res://pwa/manifest.webmanifest", "application/manifest+json"],
	"/icon.svg": ["res://pwa/icon.svg", "image/svg+xml"],
	"/icon-192.png": ["res://pwa/icon-192.png", "image/png"],
	"/icon-512.png": ["res://pwa/icon-512.png", "image/png"]
}

var _server := TCPServer.new()
var _clients: Array[Dictionary] = []
var _token := ""

func _ready() -> void:
	if OS.has_feature("mobile") or OS.has_feature("web") or OS.has_feature("vtt_mobile"):
		set_process(false)
		return
	_token = _pairing_token()
	if _token.is_empty():
		push_error("PWA: impossibile creare la credenziale di associazione")
		set_process(false)
		return
	var error := _server.listen(PORT, "127.0.0.1")
	if error != OK:
		push_warning("PWA: server localhost non disponibile: " + error_string(error))
		set_process(false)


func _pairing_token() -> String:
	if FileAccess.file_exists(TOKEN_PATH):
		var existing := FileAccess.get_file_as_string(TOKEN_PATH).strip_edges()
		if existing.length() == 64 and existing.is_valid_hex_number():
			return existing
		return ""
	var secret := Crypto.new().generate_random_bytes(32).hex_encode()
	var file := FileAccess.open(TOKEN_PATH, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(secret + "\n")
	file.close()
	return secret


func _board_sync() -> Node:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != "res://dnd_base.tscn":
		return null
	var value: Variant = scene.get("board_sync")
	if value is Node and is_instance_valid(value):
		return value as Node
	return null


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if _clients.size() >= 12:
			peer.disconnect_from_host()
		else:
			_clients.append({"peer": peer, "buffer": PackedByteArray(),
				"out": PackedByteArray(), "sent": 0, "processing": false,
				"deadline": Time.get_ticks_msec() + TIMEOUT_MS})
	for i in range(_clients.size() - 1, -1, -1):
		var client: Dictionary = _clients[i]
		var peer: StreamPeerTCP = client.peer
		peer.poll()
		if Time.get_ticks_msec() > int(client.deadline) or peer.get_status() in [
			StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE
		]:
			_drop(i)
			continue
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		if not client.out.is_empty():
			var sent := int(client.sent)
			if sent >= (client.out as PackedByteArray).size():
				_drop(i)
				continue
			var partial := peer.put_partial_data(client.out.slice(sent, mini(sent + 65536, client.out.size())))
			if partial[0] != OK:
				_drop(i)
			else:
				client.sent = sent + int(partial[1])
			continue
		if bool(client.processing):
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var received := peer.get_data(mini(available, 65536))
			if received[0] != OK:
				_drop(i)
				continue
			var incoming: PackedByteArray = client.buffer
			incoming.append_array(received[1])
			client.buffer = incoming
		if (client.buffer as PackedByteArray).size() > BODY_LIMIT + HEADER_LIMIT:
			_answer(client, 413, {"error": "request_too_large"})
			continue
		_inspect_request(client)


func _inspect_request(client: Dictionary) -> void:
	var bytes: PackedByteArray = client.buffer
	var header_end := bytes.get_string_from_utf8().find("\r\n\r\n")
	if header_end < 0:
		if bytes.size() >= HEADER_LIMIT:
			_answer(client, 431, {"error": "headers_too_large"})
		return
	if header_end > HEADER_LIMIT:
		_answer(client, 431, {"error": "headers_too_large"})
		return
	var lines := bytes.slice(0, header_end).get_string_from_utf8().split("\r\n")
	var request := lines[0].split(" ")
	if request.size() != 3 or request[2] != "HTTP/1.1":
		_answer(client, 400, {"error": "bad_request"})
		return
	var headers := {}
	for i in range(1, lines.size()):
		var row: String = lines[i]
		var pos := row.find(":")
		if pos <= 0:
			_answer(client, 400, {"error": "bad_headers"})
			return
		var key := row.substr(0, pos).to_lower()
		if headers.has(key):
			_answer(client, 400, {"error": "duplicate_header"})
			return
		headers[key] = row.substr(pos + 1).strip_edges()
	if headers.has("transfer-encoding"):
		_answer(client, 400, {"error": "unsupported_transfer_encoding"})
		return
	var raw_length := String(headers.get("content-length", "0"))
	if not raw_length.is_valid_int():
		_answer(client, 400, {"error": "bad_content_length"})
		return
	var content_length := int(raw_length)
	if content_length < 0 or content_length > BODY_LIMIT:
		_answer(client, 413, {"error": "request_too_large"})
		return
	if bytes.size() < header_end + 4 + content_length:
		return
	client.processing = true
	_handle_http.call_deferred(client, request[0], request[1], headers,
		bytes.slice(header_end + 4, header_end + 4 + content_length))


func _handle_http(client: Dictionary, method: String, path: String,
		headers: Dictionary, body: PackedByteArray) -> void:
	if method == "GET" and FILES.has(path):
		var asset: Array = FILES[path]
		if not FileAccess.file_exists(asset[0]):
			_answer(client, 500, {"error": "missing_pwa_asset"})
			return
		_respond(client, 200, String(asset[1]), FileAccess.get_file_as_bytes(asset[0]))
		return
	if path == "/api/status" and method == "GET":
		var board := _board_sync()
		_answer(client, 200, {"protocol": 1, "desktop_online": board != null
			and bool(board.get("receiving")), "pairing_required": true})
		return
	if path not in ["/api/session", "/api/map", "/api/action"]:
		_answer(client, 404, {"error": "not_found"})
		return
	if (path == "/api/action" and method != "POST") or (
		path != "/api/action" and method != "GET"
	):
		_answer(client, 405, {"error": "method_not_allowed"})
		return
	if String(headers.get("authorization", "")) != "Bearer " + _token:
		_answer(client, 401, {"error": "pairing_required"})
		return
	var board := _board_sync()
	if board == null or not bool(board.get("receiving")) or board.get("map_data_controller") == null:
		_answer(client, 503, {"error": "no_active_desktop_session"})
		return
	var controller: MapDataController = board.get("map_data_controller") as MapDataController
	if path == "/api/session":
		_answer(client, 200, {"protocol": 1, "session": board.get("session_key"),
			"mobile_protocol": 3})
	elif path == "/api/map":
		_answer(client, 200, controller.get_map_data())
	else:
		if String(headers.get("content-type", "")).split(";")[0].strip_edges() != "application/json":
			_answer(client, 415, {"error": "expected_json"})
			return
		var request: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not request is Dictionary or not request.get("action") is String or not request.get("payload") is Dictionary:
			_answer(client, 400, {"error": "invalid_action_envelope"})
			return
		var result: Dictionary = await controller.execute_local_action(
			String(request.action), request.payload)
		_answer(client, 200, result)


func _answer(client: Dictionary, status: int, value: Dictionary) -> void:
	_respond(client, status, "application/json; charset=utf-8",
		JSON.stringify(value).to_utf8_buffer())


func _respond(client: Dictionary, status: int, mime: String,
		payload: PackedByteArray) -> void:
	if not _clients.has(client):
		return
	var reasons := {200: "OK", 400: "Bad Request", 401: "Unauthorized",
		404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large",
		415: "Unsupported Media Type", 431: "Request Header Fields Too Large",
		500: "Internal Server Error", 503: "Service Unavailable"}
	var head := "HTTP/1.1 %d %s\r\n" % [status, reasons.get(status, "Error")]
	head += "Content-Type: %s\r\nContent-Length: %d\r\n" % [mime, payload.size()]
	head += "Connection: close\r\nCache-Control: no-store\r\n"
	head += "X-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n"
	head += "Content-Security-Policy: default-src 'self'; script-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'\r\n\r\n"
	var response := head.to_utf8_buffer()
	response.append_array(payload)
	client.out = response
	client.sent = 0


func _drop(index: int) -> void:
	(_clients[index].peer as StreamPeerTCP).disconnect_from_host()
	_clients.remove_at(index)


func _exit_tree() -> void:
	_server.stop()
	for item in _clients:
		(item.peer as StreamPeerTCP).disconnect_from_host()
	_clients.clear()
