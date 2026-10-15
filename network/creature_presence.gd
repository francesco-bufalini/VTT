extends Node

signal peers_changed

signal document_received(document: Dictionary, sender_id: String)
signal document_delivered(delivery_id: String)
signal item_received(transfer: Dictionary, sender_id: String)
signal item_delivered(delivery_id: String)
signal item_failed(delivery_id: String)

# App-level presence, separate from the TCP map snapshots.
# A LAN broadcast or a Tailscale peer IP alone does not prove a VTT user is online.
# Only VTT instances responding to a session-scoped UDP heartbeat appear.
const Owner = preload("res://vtt/creature_owner.gd")
const DocumentInbox = preload("res://vtt/document_inbox.gd")
const ItemInbox = preload("res://vtt/item_inbox.gd")
const PORT := 45456
const MAGIC := "KRUPHIX_CREATURE_PRESENCE_V1"
const HEARTBEAT_MS := 4500
const EXPIRE_MS := 16000
const MAX_DOCUMENT_PACKET := 7500
const DOCUMENT_RETRY_MS := 1100
const DOCUMENT_RETRIES := 6
const MAX_ITEM_BYTES := 192 * 1024
const ITEM_CHUNK_BYTES := 3200
const MAX_ITEM_CHUNKS := 64
const INCOMING_ITEM_TIMEOUT_MS := 30000

var auto_refresh := true
var _udp := PacketPeerUDP.new()
var _provider: Callable
var _session := ""
var _online: Dictionary = {}
var _last_hello_ms := -HEARTBEAT_MS
var _listening := false
var _pending_documents: Dictionary = {}
var _seen_delivery_ids: Dictionary = {}
var _incoming_items: Dictionary = {}


# Discover instances on the local subnet as well as via optional Tailscale.
# Android Emulator reaches its host PC through 10.0.2.2 (not localhost).
static func discovery_targets(extra_hosts: Array[String] = []) -> Array[String]:
	var hosts: Array[String] = ["255.255.255.255"]
	if OS.has_feature("mobile"):
		hosts.append("10.0.2.2")
	for address: String in IP.get_local_addresses():
		if not address.is_valid_ip_address() or address.contains(":"):
			continue
		var parts := address.split(".")
		if parts.size() != 4:
			continue
		var second := int(parts[1])
		if not (
			address.begins_with("10.")
			or address.begins_with("192.168.")
			or (address.begins_with("172.") and second >= 16 and second <= 31)
		):
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
		_incoming_items.clear()


func _process(_delta: float) -> void:
	if not _listening:
		return
	for _i: int in range(mini(_udp.get_available_packet_count(), 80)):
		var bytes: PackedByteArray = _udp.get_packet()
		if bytes.size() > MAX_DOCUMENT_PACKET or bytes.is_empty():
			continue
		var sender: String = _udp.get_packet_ip()
		var sender_port: int = _udp.get_packet_port()
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if parsed is Dictionary:
			_accept_heartbeat(parsed as Dictionary, sender, sender_port)
	var count_before := _online.size()
	get_online_peers()
	if _online.size() != count_before:
		peers_changed.emit()
	var now: int = Time.get_ticks_msec()
	if auto_refresh and now - _last_hello_ms >= HEARTBEAT_MS:
		request_refresh()
	for incoming_id: String in _incoming_items.keys():
		if now - int(_incoming_items[incoming_id].get("updated", 0)) > INCOMING_ITEM_TIMEOUT_MS:
			_incoming_items.erase(incoming_id)
	for delivery_id: String in _pending_documents.keys():
		var pending: Dictionary = _pending_documents[delivery_id]
		if now - int(pending.get("last_sent", 0)) < DOCUMENT_RETRY_MS:
			continue
		if int(pending.get("tries", 0)) >= DOCUMENT_RETRIES:
			_pending_documents.erase(delivery_id)
			if String(pending.get("type", "")) == "item":
				item_failed.emit(delivery_id)
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
		"ip": String(peer.get("ip", "")), "port": int(peer.get("port", PORT)),
		"recipient": recipient_id, "bytes": encoded,
		"tries": 0, "last_sent": -DOCUMENT_RETRY_MS
	}
	_send_document_packet(delivery_id)
	return delivery_id


# Items are transported as one serialized inventory snapshot plus the
# homebrew definitions it actually depends on, split into bounded UDP chunks.
# An ACK is issued only after *all* chunks are stored in the durable inbox.
func send_item(recipient_id: String, item: Dictionary, definitions: Array[Dictionary]) -> String:
	if not _listening or not _online.has(recipient_id):
		return ""
	var peer: Dictionary = _online[recipient_id]
	if Time.get_ticks_msec() - int(peer.get("last_seen", 0)) >= EXPIRE_MS:
		return ""
	if String(item.get("id", "")).is_empty() or String(item.get("name", "")).is_empty():
		return ""
	var data: PackedByteArray = JSON.stringify({
		"item": item, "definitions": definitions
	}).to_utf8_buffer()
	if data.is_empty() or data.size() > MAX_ITEM_BYTES:
		return ""
	var count: int = ceili(float(data.size()) / ITEM_CHUNK_BYTES)
	if count <= 0 or count > MAX_ITEM_CHUNKS:
		return ""
	var delivery_id := "%s_%d" % [Owner.local_id(), Time.get_ticks_usec()]
	var packets: Array[PackedByteArray] = []
	for index: int in range(count):
		var fragment: PackedByteArray = data.slice(index * ITEM_CHUNK_BYTES,
			mini(data.size(), (index + 1) * ITEM_CHUNK_BYTES))
		var packet: PackedByteArray = JSON.stringify({
			"magic": MAGIC, "session": _session, "kind": "item_chunk",
			"owner": Owner.local_id(), "recipient": recipient_id,
			"delivery_id": delivery_id, "index": index, "total": count,
			"data": Marshalls.raw_to_base64(fragment)
		}).to_utf8_buffer()
		if packet.size() > MAX_DOCUMENT_PACKET:
			return ""
		packets.append(packet)
	_pending_documents[delivery_id] = {
		"ip": String(peer.get("ip", "")), "port": int(peer.get("port", PORT)),
		"recipient": recipient_id, "packets": packets, "type": "item",
		"tries": 0, "last_sent": -DOCUMENT_RETRY_MS
	}
	_send_document_packet(delivery_id)
	return delivery_id


func _send_item_ack(ip: String, sender_port: int, recipient: String, delivery_id: String) -> void:
	_udp.set_dest_address(ip, sender_port)
	_udp.put_packet(JSON.stringify({
		"magic": MAGIC, "session": _session, "kind": "item_ack",
		"owner": Owner.local_id(), "recipient": recipient, "delivery_id": delivery_id
	}).to_utf8_buffer())


func _accept_item_chunk(value: Dictionary, owner: String, ip: String, sender_port: int,
		delivery_id: String) -> void:
	if _seen_delivery_ids.has(delivery_id):
		_send_item_ack(ip, sender_port, owner, delivery_id)
		return
	var index: int = int(value.get("index", -1))
	var total: int = int(value.get("total", 0))
	var encoded: String = String(value.get("data", ""))
	if total < 1 or total > MAX_ITEM_CHUNKS or index < 0 or index >= total or encoded.length() > 4400:
		return
	var chunk: PackedByteArray = Marshalls.base64_to_raw(encoded)
	if chunk.is_empty() or chunk.size() > ITEM_CHUNK_BYTES:
		return
	var packet_key: String = owner + ":" + delivery_id
	if _incoming_items.size() >= 12 and not _incoming_items.has(packet_key):
		return
	var state: Dictionary = _incoming_items.get(packet_key, {
		"owner": owner, "total": total, "chunks": {}, "updated": Time.get_ticks_msec()
	})
	if int(state.get("total", 0)) != total or String(state.get("owner", "")) != owner:
		return
	var chunks: Dictionary = state["chunks"]
	chunks[index] = chunk
	state["updated"] = Time.get_ticks_msec()
	_incoming_items[packet_key] = state
	if chunks.size() < total:
		return
	var assembled := PackedByteArray()
	for part: int in range(total):
		if not chunks.has(part):
			return
		assembled.append_array(chunks[part])
		if assembled.size() > MAX_ITEM_BYTES:
			_incoming_items.erase(packet_key)
			return
	_incoming_items.erase(packet_key)
	var decoded: Variant = JSON.parse_string(assembled.get_string_from_utf8())
	if not decoded is Dictionary:
		return
	var payload: Dictionary = decoded
	if not payload.get("item") is Dictionary or not payload.get("definitions") is Array:
		return
	var saved_item: Dictionary = payload["item"]
	if String(saved_item.get("id", "")).is_empty() or String(saved_item.get("name", "")).is_empty():
		return
	var transfer: Dictionary = {
		"id": delivery_id, "sender_id": owner,
		"item": saved_item, "definitions": payload["definitions"]
	}
	if not ItemInbox.receive(transfer):
		return
	_seen_delivery_ids[delivery_id] = Time.get_ticks_msec()
	if _seen_delivery_ids.size() > 500:
		_seen_delivery_ids.clear()
		_seen_delivery_ids[delivery_id] = Time.get_ticks_msec()
	item_received.emit(transfer, owner)
	_send_item_ack(ip, sender_port, owner, delivery_id)


func _send_document_packet(delivery_id: String) -> void:
	if not _pending_documents.has(delivery_id):
		return
	var pending: Dictionary = _pending_documents[delivery_id]
	_udp.set_dest_address(String(pending["ip"]), int(pending.get("port", PORT)))
	if pending.has("packets"):
		for packet: PackedByteArray in pending["packets"]:
			_udp.put_packet(packet)
	else:
		_udp.put_packet(pending["bytes"])
	pending["tries"] = int(pending["tries"]) + 1
	pending["last_sent"] = Time.get_ticks_msec()
	_pending_documents[delivery_id] = pending


func _send_heartbeat(ip: String, kind: String, destination_port: int = PORT) -> void:
	var label := OS.get_model_name() if OS.has_feature("mobile") else OS.get_environment("COMPUTERNAME")
	if label.is_empty():
		label = OS.get_name() + " · " + Owner.local_id().substr(0, 8)
	_udp.set_dest_address(ip, destination_port)
	_udp.put_packet(JSON.stringify({
		"magic": MAGIC,
		"session": _session,
		"owner": Owner.local_id(),
		"label": label,
		"device": "mobile" if OS.has_feature("mobile") else "desktop",
		"kind": kind
	}).to_utf8_buffer())


func _accept_heartbeat(value: Dictionary, ip: String, sender_port: int = PORT) -> void:
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
	if kind in ["item_chunk", "item_ack"]:
		if not _online.has(owner) or String(_online[owner].get("ip", "")) != ip:
			return
		if Time.get_ticks_msec() - int(_online[owner].get("last_seen", 0)) >= EXPIRE_MS:
			return
		if String(value.get("recipient", "")) != Owner.local_id():
			return
		var delivery_id: String = String(value.get("delivery_id", ""))
		if delivery_id.is_empty() or delivery_id.length() > 120:
			return
		if kind == "item_ack":
			if _pending_documents.has(delivery_id):
				var pending: Dictionary = _pending_documents[delivery_id]
				if String(pending.get("type", "")) == "item" and String(pending.get("recipient", "")) == owner:
					_pending_documents.erase(delivery_id)
					item_delivered.emit(delivery_id)
			return
		_accept_item_chunk(value, owner, ip, sender_port, delivery_id)
		return
	if kind == "document" or kind == "document_ack":
		# The sender must already have proven online status from this IP.
		if not _online.has(owner) or String(_online[owner].get("ip", "")) != ip:
			return
		if Time.get_ticks_msec() - int(_online[owner].get("last_seen", 0)) >= EXPIRE_MS:
			return
		if String(value.get("recipient", "")) != Owner.local_id():
			return
		var delivery_id: String = String(value.get("delivery_id", ""))
		if delivery_id.is_empty() or delivery_id.length() > 120:
			return
		if kind == "document_ack":
			if _pending_documents.has(delivery_id) and not _pending_documents[delivery_id].has("packets") and String(_pending_documents[delivery_id].get("recipient", "")) == owner:
				_pending_documents.erase(delivery_id)
				document_delivered.emit(delivery_id)
			return
		var note: Variant = value.get("document", {})
		if not note is Dictionary:
			return
		if String(note.get("title", "")).strip_edges().is_empty():
			return
		if not _seen_delivery_ids.has(delivery_id):
			var received: Dictionary = (note as Dictionary).duplicate(true)
			received["id"] = "received_" + delivery_id
			received["sender_id"] = owner
			# Acknowledge only after the delivery has been saved locally.
			# A UI listener may be absent or may fail to open an inventory.
			if not DocumentInbox.receive(received):
				return
			_seen_delivery_ids[delivery_id] = Time.get_ticks_msec()
			if _seen_delivery_ids.size() > 500:
				_seen_delivery_ids.clear()
				_seen_delivery_ids[delivery_id] = Time.get_ticks_msec()
			document_received.emit(received, owner)
		_udp.set_dest_address(ip, sender_port)
		_udp.put_packet(JSON.stringify({
			"magic": MAGIC, "session": _session, "kind": "document_ack",
			"owner": Owner.local_id(), "recipient": owner,
			"delivery_id": delivery_id
		}).to_utf8_buffer())
		return
	if kind not in ["hello", "here"]:
		return
	_online[owner] = {
		"id": owner, "ip": ip, "port": sender_port,
		"last_seen": Time.get_ticks_msec(),
		"label": String(value.get("label", "Giocatore " + owner.substr(0, 8))).substr(0, 80),
		"device": String(value.get("device", "desktop"))
	}
	peers_changed.emit()
	if kind == "hello" and _listening:
		_send_heartbeat(ip, "here", sender_port)


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


# Only full desktop VTT instances accept board/chat TCP connections.
func get_online_desktop_ipv4s() -> Array[String]:
	var hosts: Array[String] = []
	for peer: Dictionary in get_online_peers():
		if String(peer.get("device", "desktop")) != "desktop":
			continue
		var host := String(peer.get("ip", ""))
		if host.is_valid_ip_address() and not host.contains(":") and not hosts.has(host):
			hosts.append(host)
	return hosts


func _exit_tree() -> void:
	_udp.close()
