extends Node

# App-level presence, separate from the TCP/Tailscale map snapshots.
# A Tailscale peer IP alone is NOT proof that a VTT user is online.
# Only VTT instances responding to a session-scoped UDP heartbeat appear.
const Owner = preload("res://vtt/creature_owner.gd")
const PORT := 45456
const MAGIC := "KRUPHIX_CREATURE_PRESENCE_V1"
const HEARTBEAT_MS := 4500
const EXPIRE_MS := 16000

var _udp := PacketPeerUDP.new()
var _provider: Callable
var _session := ""
var _online: Dictionary = {}
var _last_hello_ms := -HEARTBEAT_MS
var _listening := false


func setup(session_key: String, peer_provider: Callable) -> void:
	_provider = peer_provider
	set_session_key(session_key)
	# In CI or when a second VTT already owns the port, the UI simply
	# shows no verified-online recipients instead of guessing from IPs.
	if DisplayServer.get_name() != "headless":
		_listening = _udp.bind(PORT, "*") == OK
	set_process(_listening)


func set_session_key(session_key: String) -> void:
	var digest: String = session_key.strip_edges().sha256_text()
	if digest != _session:
		_session = digest
		_online.clear()
		_last_hello_ms = -HEARTBEAT_MS


func _process(_delta: float) -> void:
	if not _listening:
		return
	for _i: int in range(mini(_udp.get_available_packet_count(), 80)):
		var bytes: PackedByteArray = _udp.get_packet()
		if bytes.size() > 512 or bytes.is_empty():
			continue
		var sender: String = _udp.get_packet_ip()
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if parsed is Dictionary:
			_accept_heartbeat(parsed as Dictionary, sender)
	var now: int = Time.get_ticks_msec()
	if now - _last_hello_ms >= HEARTBEAT_MS:
		request_refresh()


func request_refresh() -> void:
	_last_hello_ms = Time.get_ticks_msec()
	if not _listening or not _provider.is_valid():
		return
	var hosts_value: Variant = _provider.call()
	if not hosts_value is Array:
		return
	for raw: Variant in hosts_value as Array:
		var ip: String = String(raw).strip_edges()
		if ip.is_valid_ip_address() and not ip.contains(":"):
			_send_heartbeat(ip, "hello")


func _send_heartbeat(ip: String, kind: String) -> void:
	_udp.set_dest_address(ip, PORT)
	_udp.put_packet(JSON.stringify({
		"magic": MAGIC,
		"session": _session,
		"owner": Owner.local_id(),
		"kind": kind
	}).to_utf8_buffer())


func _accept_heartbeat(value: Dictionary, ip: String) -> void:
	if String(value.get("magic", "")) != MAGIC:
		return
	if String(value.get("session", "")) != _session:
		return
	if not ip.is_valid_ip_address() or ip.contains(":"):
		return
	var owner: String = String(value.get("owner", "")).strip_edges()
	if owner.length() < 16 or owner == Owner.local_id():
		return
	var kind: String = String(value.get("kind", ""))
	if kind not in ["hello", "here"]:
		return
	_online[owner] = {
		"id": owner, "ip": ip, "last_seen": Time.get_ticks_msec(),
		"label": "Giocatore " + owner.substr(0, 8)
	}
	if kind == "hello" and _listening:
		_send_heartbeat(ip, "here")


func get_online_peers() -> Array[Dictionary]:
	var now: int = Time.get_ticks_msec()
	var result: Array[Dictionary] = []
	for id_value: Variant in _online.keys():
		var candidate: Dictionary = _online[id_value]
		if now - int(candidate.get("last_seen", 0)) >= EXPIRE_MS:
			_online.erase(id_value)
		else:
			result.append(candidate.duplicate())
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("label", "")).naturalnocasecmp_to(String(b.get("label", ""))) < 0
	)
	return result


func _exit_tree() -> void:
	_udp.close()
