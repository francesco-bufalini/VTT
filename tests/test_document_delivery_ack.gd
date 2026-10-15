extends SceneTree
const Presence = preload("res://network/creature_presence.gd")
const Owner = preload("res://vtt/creature_owner.gd")
const ItemInbox = preload("res://vtt/item_inbox.gd")

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
	# Multi-packet item transfers must be buffered out of order, de-duplicated
	# and acknowledged only after durable persistence.
	presence.set_session_key("item-regression")
	heartbeat.session = presence._session
	heartbeat.owner = recipient
	presence._accept_heartbeat(heartbeat, "127.0.0.1")
	var received_items: Array[Dictionary] = []
	var received_acks: Array[String] = []
	presence.item_received.connect(func(item: Dictionary, _owner: String) -> void:
		received_items.append(item))
	presence.item_delivered.connect(func(id: String) -> void: received_acks.append(id))
	var transferred := presence.send_item(recipient, {
		"id": "5etools:items:phb:test", "name": "Long item",
		"description": "A".repeat(8500), "quantity": 1
	}, [])
	assert(not transferred.is_empty())
	var packet_list: Array = presence._pending_documents[transferred]["packets"]
	assert(packet_list.size() > 1 and packet_list.size() <= Presence.MAX_ITEM_CHUNKS,
		"Long catalog entries must be split into bounded UDP packets")
	var fragment: Dictionary = JSON.parse_string((packet_list[1] as PackedByteArray).get_string_from_utf8())
	fragment.owner = recipient
	fragment.recipient = Owner.local_id()
	presence._accept_heartbeat(fragment, "127.0.0.1")
	assert(received_items.is_empty(), "Incomplete objects must not be delivered")
	for i: int in range(packet_list.size()):
		var packet: Dictionary = JSON.parse_string((packet_list[i] as PackedByteArray).get_string_from_utf8())
		packet.owner = recipient
		packet.recipient = Owner.local_id()
		presence._accept_heartbeat(packet, "127.0.0.1")
	assert(received_items.size() == 1 and ItemInbox.pending().size() == 1)
	assert(String(received_items[0].item.get("description", "")).length() == 8500)
	var item_ack := {
		"magic": Presence.MAGIC, "session": presence._session,
		"kind": "item_ack", "owner": other, "recipient": Owner.local_id(),
		"delivery_id": transferred
	}
	presence._accept_heartbeat(item_ack, "127.0.0.1")
	assert(received_acks.is_empty() and presence._pending_documents.has(transferred),
		"ACK from a third party must not complete an item transfer")
	item_ack.owner = recipient
	presence._accept_heartbeat(item_ack, "127.0.0.1")
	assert(received_acks == [transferred] and not presence._pending_documents.has(transferred))
	presence._accept_heartbeat(fragment, "127.0.0.1")
	assert(received_items.size() == 1, "Duplicate item fragment must never duplicate inventory")
	var collected: Array[Dictionary] = ItemInbox.take_all()
	assert(collected.size() == 1 and ItemInbox.pending().is_empty())
	assert(ItemInbox.requeue(collected[0]) and ItemInbox.pending().size() == 1,
		"A failed import can return its already-seen delivery to inbox")
	assert(ItemInbox.take_all().size() == 1)
	assert(presence.send_item(recipient, {
		"id": "a", "name": "Oversized", "description": "z".repeat(Presence.MAX_ITEM_BYTES)
	}, []).is_empty(), "Too-large items must be rejected cleanly")

	presence.queue_free()
	await process_frame
	print("PASS: document ACK recipient, expiry, duplicate suppression and session isolation without network traffic")
	quit()