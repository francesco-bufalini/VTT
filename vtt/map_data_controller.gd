extends Node
## Shared tactical boundary: UDP public reads and explicit framed TCP actions.
## Desktop owns the board; mobile keeps sheets and cached map images only.
signal data_changed(data: Dictionary)
signal status_changed(message: String)
signal action_completed(request_id: String, action: String, result: Dictionary)

const PORT := 45457
const MAGIC := "VTT_TACTICAL_READ_V1"
const MAX_BYTES := 60000
const POLL_MS := 1500
const TIMEOUT_MS := 5000

var port := PORT
const ACTIONS := ["place_token", "snapshot", "move_token", "set_condition", "begin_spell", "target_spell", "cancel_spell", "finish_spell", "target_attack", "preview_spell", "set_appearance", "chat_send", "chat_poll"]
const ACTION_MAX_BYTES := 2 * 1024 * 1024
const ACTION_TIMEOUT_MS := 15000
var _action_provider: Callable
var _action_server := TCPServer.new()
var _actions: Array[Dictionary] = []
var _action_sequence := 0
var _provider: Callable
var _udp := PacketPeerUDP.new()
var _session := ""
var _host := ""
var _serving := false
var _last_poll := -POLL_MS
var _last_received := 0
var _request_id := 0
var _pending_id := ""
var _data: Dictionary = {}

func source_name() -> String:
	return "board" if _provider.is_valid() else ("tailscale" if not _host.is_empty() else "offline")

func use_board(provider: Callable) -> void:
	disconnect_remote()
	_provider = provider

func serve(enabled: bool, session: String) -> Error:
	_udp.close()
	_serving = false
	_close_actions()
	_session = session.strip_edges()
	if not enabled:
		return OK
	if not _provider.is_valid() or _session.is_empty():
		return ERR_INVALID_PARAMETER
	var error := _udp.bind(port)
	_serving = error == OK
	if _serving and _action_provider.is_valid():
		var action_error := _action_server.listen(action_port())
		if action_error != OK:
			status_changed.emit("Comandi mobile non disponibili: " + error_string(action_error))
	return error

func connect_remote(host: String, session: String) -> Error:
	disconnect_remote()
	_provider = Callable()
	if not host.is_valid_ip_address() or session.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	var error := _udp.bind(0)
	if error != OK:
		return error
	_host = host
	_session = session.strip_edges()
	_last_poll = -POLL_MS
	_last_received = Time.get_ticks_msec()
	status_changed.emit("Connessione alla partita…")
	return OK

func disconnect_remote() -> void:
	_close_actions()
	_udp.close()
	_host = ""
	_session = ""
	_serving = false
	_pending_id = ""
	_data.clear()
	data_changed.emit({})

func get_map_data() -> Dictionary:
	if _provider.is_valid():
		var value: Variant = _provider.call()
		return value.duplicate(true) if value is Dictionary else {}
	return _data.duplicate(true)

func _process(_delta: float) -> void:
	_process_actions()
	if not _serving and _host.is_empty():
		return
	for _i in range(mini(16, _udp.get_available_packet_count())):
		var bytes := _udp.get_packet()
		var sender := _udp.get_packet_ip()
		var sender_port := _udp.get_packet_port()
		if bytes.size() > MAX_BYTES:
			continue
		var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if not value is Dictionary:
			continue
		_accept(value, sender, sender_port)
	if not _host.is_empty():
		var now := Time.get_ticks_msec()
		if now - _last_received > TIMEOUT_MS:
			if not _data.is_empty():
				_data.clear()
				data_changed.emit({})
			status_changed.emit("Partita non raggiungibile")
			_last_received = now
		if now - _last_poll >= POLL_MS:
			_last_poll = now
			_request_id += 1
			_pending_id = str(_request_id)
			_send(_host, port, {"kind": "request", "request_id": _pending_id})

func _send(host: String, destination_port: int, message: Dictionary) -> void:
	message["magic"] = MAGIC
	message["session"] = _session
	var bytes := JSON.stringify(message).to_utf8_buffer()
	if bytes.size() > MAX_BYTES:
		return
	_udp.set_dest_address(host, destination_port)
	_udp.put_packet(bytes)

func _accept(message: Dictionary, sender: String, sender_port: int) -> void:
	if message.get("magic") != MAGIC or message.get("session") != _session:
		return
	var kind := String(message.get("kind", ""))
	var request_id := String(message.get("request_id", ""))
	if request_id.is_empty() or request_id.length() > 32:
		return
	if _serving and kind == "request":
		_send(sender, sender_port, {"kind": "response", "request_id": request_id, "data": get_map_data()})
	elif kind == "response" and sender == _host and sender_port == port and request_id == _pending_id:
		var value: Variant = message.get("data")
		if not valid_data(value):
			return
		_data = value.duplicate(true)
		_last_received = Time.get_ticks_msec()
		data_changed.emit(get_map_data())
		status_changed.emit("Partita connessa")

static func valid_data(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1:
		return false
	if not value.get("tokens") is Array or not value.get("combat") is Dictionary:
		return false
	if value.tokens.size() > 512:
		return false
	var ids: Dictionary = {}
	for row: Variant in value.tokens:
		if not row is Dictionary or not row.get("id") is String or not row.get("name") is String or not row.get("conditions") is Array:
			return false
		if row.id.is_empty() or row.id.length() > 120 or ids.has(row.id) or row.name.length() > 256 or row.conditions.size() > 64:
			return false
		if row.has("free") and not row.free is bool:
			return false
		if row.has("active_spell_ids"):
			if not row.active_spell_ids is Array or row.active_spell_ids.size() > 128:
				return false
			for spell_id: Variant in row.active_spell_ids:
				if not spell_id is String or spell_id.length() > 256:
					return false
		for field: String in ["current_miniature_id", "default_miniature_id"]:
			if row.has(field) and (not row[field] is String or row[field].length() > 256):
				return false
		ids[row.id] = true
		for condition: Variant in row.conditions:
			if not condition is String or condition.length() > 256:
				return false
	var combat: Dictionary = value.combat
	if not combat.get("active") is bool or not combat.get("entries") is Array:
		return false
	for key: String in ["round", "active_index"]:
		var number: Variant = combat.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or float(number) != floorf(float(number)):
			return false
	if combat.entries.size() > 512 or combat.round < 1 or combat.active_index < -1 or combat.active_index >= combat.entries.size():
		return false
	for row: Variant in combat.entries:
		if not row is Dictionary or not row.get("name") is String or not row.get("token_id") is String:
			return false
		if row.name.length() > 256 or row.token_id.length() > 120:
			return false
		var initiative: Variant = row.get("initiative")
		if not (initiative is int or initiative is float) or not is_finite(float(initiative)):
			return false
	return true


func _exit_tree() -> void:
	_close_actions()
	_udp.close()

# Small framed TCP requests share the tactical session. Images never go over UDP.
func set_action_provider(provider: Callable) -> void:
	_action_provider = provider

func action_port() -> int:
	return (_udp.get_local_port() if port == 0 else port) + 1

func request_action(action: String, payload: Dictionary) -> String:
	if _host.is_empty() or action not in ACTIONS or _actions.size() >= 4:
		status_changed.emit("Collega prima un desktop nella sezione Partita.")
		return ""
	_action_sequence += 1
	var id := str(Time.get_ticks_usec()) + "_" + str(_action_sequence)
	var frame := _action_frame({"magic": MAGIC, "session": _session, "request_id": id,
		"action": action, "payload": payload})
	if frame.is_empty():
		status_changed.emit("Richiesta troppo grande per la connessione mobile.")
		return ""
	var peer := StreamPeerTCP.new()
	var error := peer.connect_to_host(_host, port + 1)
	if error != OK:
		status_changed.emit("Richiesta non avviata: " + error_string(error))
		return ""
	_actions.append({"peer": peer, "client": true, "id": id, "action": action,
		"buffer": PackedByteArray(), "size": -1, "sent": 0,
		"deadline": Time.get_ticks_msec() + ACTION_TIMEOUT_MS,
		"out": frame})
	return id

static func _action_frame(message: Dictionary) -> PackedByteArray:
	var payload := JSON.stringify(message).to_utf8_buffer()
	if payload.size() > ACTION_MAX_BYTES:
		return PackedByteArray()
	var frame := PackedByteArray()
	frame.resize(4)
	frame.encode_u32(0, payload.size())
	frame.append_array(payload)
	return frame

func _close_actions() -> void:
	_action_server.stop()
	for item: Dictionary in _actions:
		if bool(item.client) and not bool(item.get("done", false)):
			action_completed.emit(item.id, item.action, {"ok": false, "error": "Connessione alla partita chiusa."})
		item.peer.disconnect_from_host()
	_actions.clear()

func _process_actions() -> void:
	while _action_server.is_connection_available():
		var peer := _action_server.take_connection()
		if _actions.size() >= 8:
			peer.disconnect_from_host()
			continue
		_actions.append({"peer": peer, "client": false, "buffer": PackedByteArray(),
			"size": -1, "sent": 0, "out": PackedByteArray(),
			"deadline": Time.get_ticks_msec() + ACTION_TIMEOUT_MS})
	for index: int in range(_actions.size() - 1, -1, -1):
		var item: Dictionary = _actions[index]
		var peer: StreamPeerTCP = item.peer
		peer.poll()
		if Time.get_ticks_msec() > int(item.deadline) or peer.get_status() in [StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE]:
			if bool(item.client) and not bool(item.get("done", false)):
				action_completed.emit(item.id, item.action, {"ok": false, "error": "Il desktop non ha risposto. Aggiorna anche VTT sul PC."})
			peer.disconnect_from_host()
			_actions.remove_at(index)
			continue
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var output: PackedByteArray = item.out
		if int(item.sent) < output.size():
			var written := peer.put_partial_data(output.slice(item.sent, mini(int(item.sent) + 65536, output.size())))
			if written[0] != OK:
				item.deadline = 0
				continue
			item.sent = int(item.sent) + int(written[1])
		if bool(item.get("replied", false)) and int(item.sent) == output.size():
			# Client ACK keeps the socket alive until its whole image was read.
			if peer.get_available_bytes() > 0:
				peer.get_data(1)
				item.deadline = 0
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var read := peer.get_data(mini(available, 131072))
			if read[0] != OK:
				item.deadline = 0
				continue
			var buffer: PackedByteArray = item.buffer
			buffer.append_array(read[1])
			item.buffer = buffer
		var buffer: PackedByteArray = item.buffer
		if int(item.size) == -1 and buffer.size() >= 4:
			item.size = buffer.decode_u32(0)
			buffer = buffer.slice(4)
			item.buffer = buffer
			if int(item.size) <= 0 or int(item.size) > ACTION_MAX_BYTES:
				item.deadline = 0
				continue
		if int(item.size) > 0 and buffer.size() >= int(item.size) and not bool(item.get("busy", false)):
			item.busy = true
			var message: Variant = JSON.parse_string(buffer.slice(0, item.size).get_string_from_utf8())
			if not message is Dictionary or message.get("magic") != MAGIC or message.get("session") != _session:
				item.deadline = 0
				continue
			if bool(item.client):
				if message.get("request_id") == item.id and message.get("result") is Dictionary:
					item.done = true
					peer.put_data(PackedByteArray([1]))
					action_completed.emit(item.id, item.action, message.result)
				item.deadline = 0
			else:
				_dispatch_action.call_deferred(item, message)

func _dispatch_action(item: Dictionary, message: Dictionary) -> void:
	var result := {"ok": false, "error": "Il desktop non supporta questo comando. Aggiorna e riavvia anche il VTT sul computer."}
	if _action_provider.is_valid() and message.get("action") in ACTIONS and message.get("payload") is Dictionary:
		var value: Variant = await _action_provider.call(String(message.action), message.payload)
		if value is Dictionary:
			result = value
	if not _actions.has(item):
		return
	item.out = _action_frame({"magic": MAGIC, "session": _session,
		"request_id": String(message.get("request_id", "")), "result": result})
	if item.out.is_empty():
		item.out = _action_frame({"magic": MAGIC, "session": _session,
			"request_id": String(message.get("request_id", "")),
			"result": {"ok": false, "error": "Risposta troppo grande per la connessione mobile."}})
	item.sent = 0
	item.replied = true
