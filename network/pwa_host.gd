extends Node
## Loopback-only HTTP bridge. HTTPS termination is provided by Tailscale Serve
## or another trusted reverse proxy. No second application/server is required.
## An explicit random pairing secret protects the session-scoped game endpoints.

const MapDataController = preload("res://vtt/map_data_controller.gd")
const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")
const PORT := 8765
const HEADER_LIMIT := 16384
const BODY_LIMIT := 2 * 1024 * 1024
const TIMEOUT_MS := 15000
const TOKEN_PATH := "user://pwa_pairing_token.txt"
const SHORT_CODE_LIFETIME_MS := 300000
const MAX_PAIRING_ATTEMPTS := 8
const QrEncoder = preload("res://vtt/qr/qr_code.gd")
const FILES := {
	"/": ["res://pwa/index.html", "text/html; charset=utf-8"],
	"/index.html": ["res://pwa/index.html", "text/html; charset=utf-8"],
	"/client.js": ["res://pwa/client.js", "text/javascript; charset=utf-8"],
	"/main.js": ["res://pwa/main.js", "text/javascript; charset=utf-8"],
	"/native_sheet.js": ["res://pwa/native_sheet.js", "text/javascript; charset=utf-8"],
  "/item_controls.js": ["res://pwa/item_controls.js", "text/javascript; charset=utf-8"],
  "/documents.js": ["res://pwa/documents.js", "text/javascript; charset=utf-8"],
  "/spell_selection.js": ["res://pwa/spell_selection.js", "text/javascript; charset=utf-8"],
	"/ui.js": ["res://pwa/ui.js", "text/javascript; charset=utf-8"],
	"/demo.js": ["res://pwa/demo.js", "text/javascript; charset=utf-8"],
	"/tactical_view.js": ["res://pwa/tactical_view.js", "text/javascript; charset=utf-8"],
	"/catalog_data.js": ["res://pwa/catalog_data.js", "text/javascript; charset=utf-8"],
	"/catalog/classes.json": ["res://pwa/catalog/classes.json", "application/json; charset=utf-8"],
	"/catalog/player.json": ["res://vtt/data/player_5etools_catalog.json", "application/json; charset=utf-8"],
	"/catalog/backgrounds.json": ["res://vtt/data/compendium_backgrounds_5etools.json", "application/json; charset=utf-8"],
	"/catalog/features.json": ["res://vtt/data/compendium_features_5etools.json", "application/json; charset=utf-8"],
	"/catalog/items.json": ["res://vtt/data/compendium_items_5etools.json", "application/json; charset=utf-8"],
	"/styles.css": ["res://pwa/styles.css", "text/css; charset=utf-8"],
	"/storage.js": ["res://pwa/storage.js", "text/javascript; charset=utf-8"],
	"/creatures.js": ["res://pwa/creatures.js", "text/javascript; charset=utf-8"],
	"/creature_format.js": ["res://pwa/creature_format.js", "text/javascript; charset=utf-8"],
	"/sw.js": ["res://pwa/sw.js", "text/javascript; charset=utf-8"],
	"/manifest.webmanifest": ["res://pwa/manifest.webmanifest", "application/manifest+json"],
	"/icon.svg": ["res://pwa/icon.svg", "image/svg+xml"],
	"/icon-192.png": ["res://pwa/icon-192.png", "image/png"],
	"/icon-512.png": ["res://pwa/icon-512.png", "image/png"]
}

# Keep fixtures independent from a running desktop session.
var _listen_port: int = PORT
var _server := TCPServer.new()
var _clients: Array[Dictionary] = []
var _token := ""
var _short_code := ""
var _short_code_expiry := 0
var _short_code_attempts := 0
var _public_spells_payload := PackedByteArray()

# PWA HTTP runs only while the native 3D board is open. A permanently
# installed autoload tracks the scene, but does not keep a listening socket
# outside the board. Godot F5/F6 launches include autoloads too.
func _ready() -> void:
	set_process(false)
	if OS.has_feature("mobile") or OS.has_feature("web") or OS.has_feature("vtt_mobile"):
		return
	_token = _pairing_token()
	if _token.is_empty():
		push_error("PWA: impossibile creare la credenziale di associazione")
		return
	get_tree().scene_changed.connect(_on_scene_changed)
	call_deferred("_refresh_scene_server")


func _is_board_scene(scene: Node) -> bool:
	if scene == null or not is_instance_valid(scene):
		return false
	if scene.scene_file_path == "res://dnd_base.tscn":
		return true
	# Campaigns such as Scontro contro Kaos inherit from the tactical
	# board script but have their own .tscn path. Accept all legitimate
	# board-script descendants, not just the original scene filename.
	var board_script: Script = scene.get_script() as Script
	while board_script != null:
		if board_script.resource_path == "res://dnd_base.gd":
			return true
		board_script = board_script.get_base_script()
	return false


func _on_scene_changed(_scene: Node) -> void:
	_refresh_scene_server()


func _refresh_scene_server() -> void:
	if _is_board_scene(get_tree().current_scene):
		_start_listener()
	else:
		_stop_listener()


func _on_board_exiting() -> void:
	# Called on tree_exiting even if the board is freed without a scene change.
	_stop_listener()


func _start_listener() -> Error:
	if _server.is_listening():
		return OK
	if _token.is_empty():
		return ERR_UNAUTHORIZED
	var err := _server.listen(_listen_port, "127.0.0.1")
	if err != OK:
		push_warning("PWA: localhost:%d non disponibile: %s" % [_listen_port, error_string(err)])
		return err
	set_process(true)
	var board := get_tree().current_scene
	if _is_board_scene(board) and not board.tree_exiting.is_connected(_on_board_exiting):
		board.tree_exiting.connect(_on_board_exiting)
	return OK


func _stop_listener() -> void:
	_short_code = ""
	_short_code_expiry = 0
	_short_code_attempts = 0
	set_process(false)
	_server.stop()
	for item: Dictionary in _clients:
		var peer: StreamPeerTCP = item.get("peer") as StreamPeerTCP
		if peer != null:
			peer.disconnect_from_host()
	_clients.clear()


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



# New phones exchange a short-lived 16-character desktop code for the
# existing strong 256-bit bearer. The old bearer stays compatible with
# previously installed clients. Never transmit it in a QR or URL.
func _new_short_code() -> String:
	_short_code = Crypto.new().generate_random_bytes(8).hex_encode().to_upper()
	_short_code_expiry = Time.get_ticks_msec() + SHORT_CODE_LIFETIME_MS
	_short_code_attempts = 0
	return _short_code


func _consume_short_code(value: String) -> bool:
	if _short_code.is_empty() or Time.get_ticks_msec() > _short_code_expiry:
		_short_code = ""
		return false
	_short_code_attempts += 1
	if _short_code_attempts > MAX_PAIRING_ATTEMPTS:
		_short_code = ""
		return false
	if value == _short_code:
		_short_code = ""
		_short_code_expiry = 0
		return true
	return false


func _tailscale_url() -> String:
	var result: Dictionary = await preload("res://network/tailscale_serve.gd")._command(PackedStringArray(["status", "--json"]))
	if result.ok:
		var data: Variant = JSON.parse_string(String(result.message))
		if not data is Dictionary:
			return ""
		var me: Variant = (data as Dictionary).get("Self", {})
		if not me is Dictionary:
			return ""
		var domain := String((me as Dictionary).get("DNSName", "")).trim_suffix(".")
		if domain.ends_with(".ts.net") and not domain.contains("/") and not domain.contains(":"):
			return "https://" + domain
	return ""


func _pair_url(origin: String, code: String) -> String:
	var normalized := origin.strip_edges().trim_suffix("/")
	if normalized.begins_with("https://") and not normalized.contains("#") and not normalized.contains("?"):
		return normalized + "/#pair=" + code
	if normalized.begins_with("http://127.0.0.1:") and not normalized.contains("#") and not normalized.contains("?"):
		return normalized + "/#pair=" + code
	return ""


# Ctrl+Shift+P is intentionally handled only on the desktop game viewport.
func _input(event: InputEvent) -> void:
	if not _server.is_listening() or _token.is_empty() or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or not key.ctrl_pressed or not key.shift_pressed or key.keycode != KEY_P:
		return
	get_viewport().set_input_as_handled()
	_show_pairing_dialog()


func _show_pairing_dialog() -> void:
	for node: Node in get_tree().root.get_children():
		if node.name == "VttPwaPairing" and node is AcceptDialog:
			node.queue_free()
	var code := _new_short_code()
	var dialog := AcceptDialog.new()
	dialog.name = "VttPwaPairing"
	dialog.title = "Collega VTT Mobile"
	dialog.min_size = Vector2i(480, 560)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	dialog.add_child(layout)
	var intro := Label.new()
	intro.text = "Inquadra il QR con la fotocamera oppure inserisci il codice in Partita.\nValido 5 minuti, per un solo dispositivo."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(intro)
	var code_label := Label.new()
	code_label.text = "Codice: %s-%s-%s-%s" % [code.substr(0, 4), code.substr(4, 4), code.substr(8, 4), code.substr(12, 4)]
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.add_theme_font_size_override("font_size", 24)
	layout.add_child(code_label)
	var address_label := Label.new()
	address_label.text = "Indirizzo HTTPS Tailscale (modificabile):"
	layout.add_child(address_label)
	var url_edit := LineEdit.new()
	url_edit.placeholder_text = "https://nome-pc.nome-tailnet.ts.net"
	layout.add_child(url_edit)
	var qr := TextureRect.new()
	qr.custom_minimum_size = Vector2(240, 240)
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layout.add_child(qr)
	var feedback := Label.new()
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(feedback)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(controls)
	var copy_code := Button.new()
	copy_code.text = "Copia codice"
	controls.add_child(copy_code)
	copy_code.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(code)
	)
	var copy_url := Button.new()
	copy_url.text = "Copia link"
	controls.add_child(copy_url)
	var update_qr := func() -> void:
		var link := _pair_url(url_edit.text, code)
		if link.is_empty():
			qr.texture = null
			copy_url.disabled = true
			feedback.text = "Inserisci l'URL HTTPS di Tailscale Serve per generare il QR.\nIl codice manuale funziona comunque."
			return
		var generator: Node = QrEncoder.new()
		generator.set("error_correct_level", 1)
		qr.texture = generator.call("get_texture", link)
		generator.free()
		feedback.text = "Scansiona per aprire VTT e associare il telefono."
		copy_url.disabled = false

	copy_url.pressed.connect(func() -> void:
		var link := _pair_url(url_edit.text, code)
		if not link.is_empty():
			DisplayServer.clipboard_set(link)
	)
	url_edit.text_submitted.connect(func(_value: String) -> void: update_qr.call())
	url_edit.focus_exited.connect(func() -> void: update_qr.call())
	update_qr.call()
	get_tree().root.add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.popup_centered()
	var detected_url := await _tailscale_url()
	if is_instance_valid(url_edit) and url_edit.text.is_empty():
		url_edit.text = detected_url
		update_qr.call()


func public_spells_json() -> PackedByteArray:
	# Public built-in references only; private desktop homebrew stays local.
	if _public_spells_payload.is_empty():
		var spells: Array[Dictionary] = []
		for entry: Dictionary in SpellCatalog.all_spells():
			var spell_id: String = String(entry.get("id", ""))
			if spell_id.is_empty() or spell_id.begins_with("homebrew:") or String(entry.get("origin", "")) == "homebrew":
				continue
			spells.append({
				"id": spell_id, "name": String(entry.get("name", "")),
				"source": String(entry.get("source", "")),
				"level": int(entry.get("level", 0)),
				"school": String(entry.get("school", "")),
				"classes": entry.get("classes", []),
				"range": String(entry.get("range", "")),
				"casting_time": String(entry.get("casting_time", "")),
				"description": String(entry.get("description", ""))
			})
		_public_spells_payload = JSON.stringify({"version": 1, "spells": spells}).to_utf8_buffer()
	return _public_spells_payload


func _board_sync() -> Node:
	var scene := get_tree().current_scene
	if not _is_board_scene(scene):
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
	# This payload is also used to package the standalone offline prototype.
	if path == "/catalog/spells.json" and method == "GET":
		_respond(client, 200, "application/json; charset=utf-8", public_spells_json())
		return
	# One-time pairing endpoint. No authentication is needed for this narrow
	# exchange; wrong guesses are limited globally per displayed code.
	if path == "/api/pair":
		if method != "POST":
			_answer(client, 405, {"error": "method_not_allowed"})
			return
		if body.size() > 128 or String(headers.get("content-type", "")).split(";")[0].strip_edges() != "application/json":
			_answer(client, 415, {"error": "expected_small_json"})
			return
		var envelope: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not envelope is Dictionary:
			_answer(client, 400, {"error": "invalid_pair_code"})
			return
		var code: String = String((envelope as Dictionary).get("code", "")).replace("-", "").replace(" ", "").to_upper()
		if code.length() != 16 or not code.is_valid_hex_number() or not _consume_short_code(code):
			_answer(client, 401, {"error": "invalid_or_expired_pair_code"})
			return
		_answer(client, 200, {"token": _token})
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
	head += "Content-Security-Policy: default-src 'self'; script-src 'self'; connect-src 'self'; img-src 'self' blob:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'\r\n\r\n"
	var response := head.to_utf8_buffer()
	response.append_array(payload)
	client.out = response
	client.sent = 0


func _drop(index: int) -> void:
	(_clients[index].peer as StreamPeerTCP).disconnect_from_host()
	_clients.remove_at(index)


func _exit_tree() -> void:
	_stop_listener()
