extends Node
## LAN discovery for running desktop boards. PWA devices use the HTTP session
## relay; no native creature, document or inventory transport exists here.
signal peers_changed

const Owner = preload("res://vtt/creature_owner.gd")
const PORT := 45456
const MAGIC := "KRUPHIX_BOARD_PRESENCE_V1"
const HEARTBEAT_MS := 4500
const EXPIRE_MS := 16000
const MAX_HEARTBEAT_BYTES := 7500

var auto_refresh := true
var _udp := PacketPeerUDP.new()
var _provider: Callable
var _session := ""
var _online: Dictionary = {}
var _last_hello_ms := -HEARTBEAT_MS
var _listening := false

static func discovery_targets(extra_hosts: Array[String] = []) -> Array[String]:
	var hosts: Array[String] = ["255.255.255.255"]
	for address: String in IP.get_local_addresses():
		if not address.is_valid_ip_address() or address.contains(":"):
			continue
		var parts := address.split(".")
		if parts.size() != 4:
			continue
		var second := int(parts[1])
		if not (address.begins_with("10.") or address.begins_with("192.168.") or
			(address.begins_with("172.") and second >= 16 and second <= 31)):
			continue
		var directed := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not hosts.has(directed):
			hosts.append(directed)
	for host: String in extra_hosts:
		if host.is_valid_ip_address() and not host.contains(":") and not hosts.has(host):
			hosts.append(host)
	return hosts

func setup(session_key: String, peer_provider: Callable) -> void:
	_provider = peer_provider
	set_session_key(session_key)
	if DisplayServer.get_name() != "headless":
		_listening = _udp.bind(PORT, "*") == OK
	_udp.set_broadcast_enabled(true)
	set_process(_listening)

func set_session_key(session_key: String) -> void:
	var digest: String = session_key.strip_edges().sha256_text()
	if digest != _session:
		_session = digest
		_online.clear()
		_last_hello_ms = -HEARTBEAT_MS
		peers_changed.emit()

func _process(_delta: float) -> void:
	if not _listening:
		return
	for _i: int in range(mini(_udp.get_available_packet_count(), 80)):
		var bytes: PackedByteArray = _udp.get_packet()
		if bytes.is_empty() or bytes.size() > MAX_HEARTBEAT_BYTES:
			continue
		var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if value is Dictionary:
			_accept_heartbeat(value, _udp.get_packet_ip(), _udp.get_packet_port())
	var before := _online.size()
	get_online_peers()
	if _online.size() != before:
		peers_changed.emit()
	if auto_refresh and Time.get_ticks_msec() - _last_hello_ms >= HEARTBEAT_MS:
		request_refresh()

func request_refresh() -> void:
	_last_hello_ms = Time.get_ticks_msec()
	if not _listening or not _provider.is_valid():
		return
	var hosts: Variant = _provider.call()
	if not hosts is Array:
		return
	for raw: Variant in hosts as Array:
		var ip := String(raw).strip_edges()
		if ip.is_valid_ip_address() and not ip.contains(":"):
			_send_heartbeat(ip, "hello")

func _send_heartbeat(ip: String, kind: String, destination_port: int = PORT) -> void:
	var label := OS.get_environment("COMPUTERNAME")
	if label.is_empty():
		label = OS.get_environment("HOSTNAME")
	if label.is_empty():
		label = OS.get_name() + " · " + Owner.local_id().substr(0, 8)
	_udp.set_dest_address(ip, destination_port)
	_udp.put_packet(JSON.stringify({
		"magic": MAGIC, "session": _session, "owner": Owner.local_id(),
		"label": label, "device": "desktop", "kind": kind
	}).to_utf8_buffer())

func _accept_heartbeat(value: Dictionary, ip: String, sender_port: int = PORT) -> void:
	if (
		String(value.get("magic", "")) != MAGIC
		or String(value.get("session", "")) != _session
	):
		return
	if not ip.is_valid_ip_address() or ip.contains(":"):
		return
	var owner := String(value.get("owner", "")).strip_edges()
	if owner.length() < 16 or owner == Owner.local_id():
		return
	var kind := String(value.get("kind", ""))
	if kind not in ["hello", "here"]:
		return
	_online[owner] = {
		"id": owner, "ip": ip, "port": sender_port,
		"last_seen": Time.get_ticks_msec(),
		"label": String(value.get("label", "Desktop " + owner.substr(0, 8))).substr(0, 80),
		"device": "desktop"
	}
	peers_changed.emit()
	if kind == "hello" and _listening:
		_send_heartbeat(ip, "here", sender_port)

func get_online_peers() -> Array[Dictionary]:
	var now := Time.get_ticks_msec()
	var result: Array[Dictionary] = []
	for id_value: Variant in _online.keys():
		var candidate: Dictionary = _online[id_value]
		if now - int(candidate.get("last_seen", 0)) >= EXPIRE_MS:
			_online.erase(id_value)
		else:
			result.append(candidate.duplicate())
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("label", "")).naturalnocasecmp_to(String(b.get("label", ""))) < 0)
	return result

func get_online_desktop_ipv4s() -> Array[String]:
	var hosts: Array[String] = []
	for peer: Dictionary in get_online_peers():
		var host := String(peer.get("ip", ""))
		if host.is_valid_ip_address() and not host.contains(":") and not hosts.has(host):
			hosts.append(host)
	return hosts

func _exit_tree() -> void:
	_udp.close()
