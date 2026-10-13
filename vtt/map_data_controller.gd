extends Node
## Shared read-only tactical data boundary. Desktop reads the local board;
## mobile polls an explicit peer address over the OS Tailscale connection.
signal data_changed(data: Dictionary)
signal status_changed(message: String)

const PORT := 45457
const MAGIC := "VTT_TACTICAL_READ_V1"
const MAX_BYTES := 60000
const POLL_MS := 1500
const TIMEOUT_MS := 5000

var port := PORT
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
	_session = session.strip_edges()
	if not enabled:
		return OK
	if not _provider.is_valid() or _session.is_empty():
		return ERR_INVALID_PARAMETER
	var error := _udp.bind(port)
	_serving = error == OK
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
	_udp.close()