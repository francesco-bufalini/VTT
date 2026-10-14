extends Node

signal peers_changed

signal document_received(document: Dictionary, sender_id: String)
signal document_delivered(delivery_id: String)

# App-level presence, separate from the TCP/Tailscale map snapshots.
# A Tailscale peer IP alone is NOT proof that a VTT user is online.
# Only VTT instances responding to a session-scoped UDP heartbeat appear.
const Owner = preload("res://vtt/creature_owner.gd")
const PORT := 45456
const MAGIC := "KRUPHIX_CREATURE_PRESENCE_V1"
const HEARTBEAT_MS := 4500
const EXPIRE_MS := 16000
const MAX_DOCUMENT_PACKET := 7500
const DOCUMENT_RETRY_MS := 1100
const DOCUMENT_RETRIES := 6

var auto_refresh := true
var _udp := PacketPeerUDP.new()
var _provider: Callable
var _session := ""
var _online: Dictionary = {}
var _last_hello_ms := -HEARTBEAT_MS
var _listening := false
var _pending_documents: Dictionary = {}
var _seen_delivery_ids: Dictionary = {}


func setup(session_key: String, peer_provider: Callable) -> void:
	_provider = peer_provider
	set_session_key(session_key)
	# In CI or when a second VTT already owns the port, the UI simply
	# shows no verified-online recipients instead of guessing from IPs.
	if DisplayServer.get_name() != "headless":
		_listening = _udp.bind(PORT, "*") == OK
	_udp.set_broadcast_enabled(true)
	set_process(_listening)


func set_session_key(session_key: String) -> void:
	var digest: String = session_key.strip_edges().sha256_text()
	if digest != _session:
		_session = digest
		_online.clear()
		peers_changed.emit()
		_last_hello_ms = -HEARTBEAT_MS
		_pending_documents.clear()
		_seen_delivery_ids.clear()


func _process(_delta: float) -> void:
	if not _listening:
		return
	for _i: int in range(mini(_udp.get_available_packet_count(), 80)):
		var bytes: PackedByteArray = _udp.get_packet()
		if bytes.size() > MAX_DOCUMENT_PACKET or bytes.is_empty():
			continue
		var sender: String = _udp.get_packet_ip()
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if parsed is Dictionary:
			_accept_heartbeat(parsed as Dictionary, sender)
	var count_before := _online.size()
	get_online_peers()
	if _online.size() != count_before:
		peers_changed.emit()
	var now: int = Time.get_ticks_msec()
	if auto_refresh and now - _last_hello_ms >= HEARTBEAT_MS:
		request_refresh()
	for delivery_id: String in _pending_documents.keys():
		var pending: Dictionary = _pending_documents[delivery_id]
		if now - int(pending.get("last_sent", 0)) < DOCUMENT_RETRY_MS:
			continue
		if int(pending.get("tries", 0)) >= DOCUMENT_RETRIES:
			_pending_documents.erase(delivery_id)
			continue
		_send_document_packet(delivery_id)


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


# Only peers that answered the game-session heartbeat can receive notes.
# The body is capped so private inventory data is never sent in a map snapshot.
func send_document(recipient_id: String, document: Dictionary) -> String:
	if not _listening or not _online.has(recipient_id):
		return ""
	var peer: Dictionary = _online[recipient_id]
	if Time.get_ticks_msec() - int(peer.get("last_seen", 0)) >= EXPIRE_MS:
		return ""
	var delivery_id := "%s_%d" % [Owner.local_id(), Time.get_ticks_usec()]
	var sanitized: Dictionary = {
		"id": String(document.get("id", "")).substr(0, 120),
		"title": String(document.get("title", "")).substr(0, 160),
		"text": String(document.get("text", "")).substr(0, 3500),
		"style": String(document.get("style", "pergamena"))
	}
	var payload: Dictionary = {
		"magic": MAGIC, "session": _session, "kind": "document",
		"owner": Owner.local_id(), "recipient": recipient_id,
		"delivery_id": delivery_id, "document": sanitized
	}
	var encoded: PackedByteArray = JSON.stringify(payload).to_utf8_buffer()
	if encoded.size() > MAX_DOCUMENT_PACKET:
		return ""
	_pending_documents[delivery_id] = {
		"ip": String(peer.get("ip", "")), "bytes": encoded,
		"tries": 0, "last_sent": -DOCUMENT_RETRY_MS
	}
	_send_document_packet(delivery_id)
	return delivery_id


func _send_document_packet(delivery_id: String) -> void:
	if not _pending_documents.has(delivery_id):
		return
	var pending: Dictionary = _pending_documents[delivery_id]
	_udp.set_dest_address(String(pending["ip"]), PORT)
	_udp.put_packet(pending["bytes"])
	pending["tries"] = int(pending["tries"]) + 1
	pending["last_sent"] = Time.get_ticks_msec()
	_pending_documents[delivery_id] = pending


func _send_heartbeat(ip: String, kind: String) -> void:
	var label := OS.get_model_name() if OS.has_feature("mobile") else OS.get_environment("COMPUTERNAME")
	if label.is_empty():
		label = OS.get_name() + " · " + Owner.local_id().substr(0, 8)
	_udp.set_dest_address(ip, PORT)
	_udp.put_packet(JSON.stringify({
		"magic": MAGIC,
		"session": _session,
		"owner": Owner.local_id(),
		"label": label,
		"device": "mobile" if OS.has_feature("mobile") else "desktop",
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
	if kind == "document" or kind == "document_ack":
		# The sender must already have proven online status from this IP.
		if not _online.has(owner) or String(_online[owner].get("ip", "")) != ip:
			return
		if String(value.get("recipient", "")) != Owner.local_id():
			return
		var delivery_id: String = String(value.get("delivery_id", ""))
		if delivery_id.is_empty() or delivery_id.length() > 120:
			return
		if kind == "document_ack":
			if _pending_documents.has(delivery_id):
				_pending_documents.erase(delivery_id)
				document_delivered.emit(delivery_id)
			return
		var note: Variant = value.get("document", {})
		if not note is Dictionary:
			return
		if String(note.get("title", "")).strip_edges().is_empty():
			return
		if not _seen_delivery_ids.has(delivery_id):
			_seen_delivery_ids[delivery_id] = Time.get_ticks_msec()
			if _seen_delivery_ids.size() > 500:
				_seen_delivery_ids.clear()
				_seen_delivery_ids[delivery_id] = Time.get_ticks_msec()
			var received: Dictionary = (note as Dictionary).duplicate(true)
			received["id"] = "received_" + delivery_id
			received["sender_id"] = owner
			document_received.emit(received, owner)
		_udp.set_dest_address(ip, PORT)
		_udp.put_packet(JSON.stringify({
			"magic": MAGIC, "session": _session, "kind": "document_ack",
			"owner": Owner.local_id(), "recipient": owner,
			"delivery_id": delivery_id
		}).to_utf8_buffer())
		return
	if kind not in ["hello", "here"]:
		return
	_online[owner] = {
		"id": owner, "ip": ip, "last_seen": Time.get_ticks_msec(),
		"label": String(value.get("label", "Giocatore " + owner.substr(0, 8))).substr(0, 80),
		"device": String(value.get("device", "desktop"))
	}
	peers_changed.emit()
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
