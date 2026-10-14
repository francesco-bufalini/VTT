extends SceneTree
const Presence = preload("res://network/creature_presence.gd")
const Owner = preload("res://vtt/creature_owner.gd")

# Exercise real queue/ACK handling without sending packets or binding ports.
class LocalPresence extends Presence:
	func _send_document_packet(_delivery_id: String) -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var presence := LocalPresence.new()
	root.add_child(presence)
	presence.set_process(false)
	presence.set_session_key("ack-regression")
	var recipient := "regression-recipient-0123456789"
	var other := "regression-other-peer-0123456789"
	var heartbeat := {"magic": Presence.MAGIC, "session": presence._session, "kind": "here"}
	for peer: String in [recipient, other]:
		heartbeat.owner = peer
		presence._accept_heartbeat(heartbeat, "127.0.0.1")
	presence._listening = true
	var completed: Array[String] = []
	presence.document_delivered.connect(func(id: String) -> void: completed.append(id))
	var delivery := presence.send_document(recipient, {"title": "Test document"})
	assert(not delivery.is_empty() and presence._pending_documents[delivery].recipient == recipient)
	var ack := {"magic": Presence.MAGIC, "session": presence._session, "kind": "document_ack",
		"owner": other, "recipient": Owner.local_id(), "delivery_id": delivery}
	presence._accept_heartbeat(ack, "127.0.0.1")
	assert(completed.is_empty() and presence._pending_documents.has(delivery),
		"Another online peer must not complete a delivery even when it shares the recipient IP")
	ack.owner = recipient
	presence._accept_heartbeat(ack, "127.0.0.2")
	assert(completed.is_empty(), "ACK source address must match verified presence")
	presence._accept_heartbeat(ack, "127.0.0.1")
	assert(completed == [delivery] and not presence._pending_documents.has(delivery))
	presence._accept_heartbeat(ack, "127.0.0.1")
	ack.delivery_id = "unknown-delivery"
	presence._accept_heartbeat(ack, "127.0.0.1")
	assert(completed.size() == 1, "Duplicate and unknown ACKs must not emit delivery notifications")
	var expired := presence.send_document(recipient, {"title": "Expired peer"})
	presence._online[recipient].last_seen = Time.get_ticks_msec() - Presence.EXPIRE_MS
	ack.delivery_id = expired
	presence._accept_heartbeat(ack, "127.0.0.1")
	assert(presence._pending_documents.has(expired) and completed.size() == 1,
		"A stale peer must not complete delivery before the next presence cleanup")
	heartbeat.owner = recipient
	presence._accept_heartbeat(heartbeat, "127.0.0.1")
	presence._accept_heartbeat(ack, "127.0.0.1")
	assert(completed == [delivery, expired], "Fresh verified presence restores valid ACK handling")
	var pending := presence.send_document(recipient, {"title": "Old session"})
	presence.set_session_key("another-session")
	ack.delivery_id = pending
	presence._accept_heartbeat(ack, "127.0.0.1")
	assert(presence._pending_documents.is_empty() and completed.size() == 2)
	presence.queue_free()
	await process_frame
	print("PASS: document ACK recipient, expiry, duplicate suppression and session isolation without network traffic")
	quit()