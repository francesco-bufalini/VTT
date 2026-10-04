extends Node

signal event_received(event: Dictionary)
signal status_changed(message: String)

const PORT := 45455
const MAGIC := "DND_DICE_CHAT_V1"
const MAX_BYTES := 32 * 1024
const SEND_TIMEOUT_MS := 2200
const MAX_CONNECTIONS := 24

var server := TCPServer.new()
var connections: Array[Dictionary] = []
var receiving := false
var session_key := ""
var peer_provider: Callable = Callable()


func setup(tailscale_peer_provider: Callable) -> void:
	peer_provider = tailscale_peer_provider


func listen(enabled: bool, key: String) -> Error:
	server.stop()
	receiving = false
	for item: Dictionary in connections:
		var peer: StreamPeerTCP = item.get("peer") as StreamPeerTCP
		if peer != null:
			peer.disconnect_from_host()
	connections.clear()

	session_key = key.strip_edges()
	if not enabled:
		status_changed.emit("Chat/dadi: ricezione disattivata")
		return OK
	if session_key.is_empty():
		status_changed.emit("Chat/dadi: partita non valida")
		return ERR_INVALID_PARAMETER

	var error := server.listen(PORT)
	receiving = error == OK
	status_changed.emit(
		"Chat/dadi online · Partita %s" % session_key
		if receiving
		else "Chat/dadi non in ascolto: %s" % error_string(error)
	)
	return error


func broadcast_event(event: Dictionary, key: String) -> Error:
	var clean_key := key.strip_edges()
	if clean_key.is_empty():
		return ERR_INVALID_PARAMETER
	if event.is_empty():
		return ERR_INVALID_DATA

	var payload := JSON.stringify({
		"magic": MAGIC,
		"key": clean_key,
		"kind": "event",
		"event": event
	}).to_utf8_buffer()
	if payload.size() <= 0 or payload.size() > MAX_BYTES:
		return ERR_OUT_OF_MEMORY

	var hosts: Array[String] = _peer_ipv4s()
	if hosts.is_empty():
		# This is still a valid local roll/chat event. No peer is not an error
		# for the UI, it only means there is nobody to notify right now.
		status_changed.emit("Chat/dadi locale · nessun peer Tailscale")
		return OK

	var started := 0
	for host: String in hosts:
		var error := _queue_payload(host, payload)
		if error == OK:
			started += 1

	if started == 0:
		status_changed.emit("Chat/dadi: peer non raggiungibili")
		return ERR_CANT_CONNECT

	status_changed.emit(
		"Chat/dadi sincronizzazione automatica · %d peer" % started
	)
	return OK


func _peer_ipv4s() -> Array[String]:
	if not peer_provider.is_valid():
		return []
	var value: Variant = peer_provider.call()
	if not value is Array:
		return []

	var out: Array[String] = []
	var seen: Dictionary = {}
	for raw: Variant in (value as Array):
		var host := String(raw).strip_edges()
		if (
			host.is_empty()
			or host.contains(":")
			or not host.is_valid_ip_address()
			or seen.has(host)
		):
			continue
		seen[host] = true
		out.append(host)
	return out


func _queue_payload(host: String, payload: PackedByteArray) -> Error:
	var peer := StreamPeerTCP.new()
	var error := peer.connect_to_host(host, PORT)
	if error != OK:
		return error

	var frame := StreamPeerBuffer.new()
	frame.put_u32(payload.size())
	frame.put_data(payload)
	connections.append({
		"peer": peer,
		"out": frame.data_array,
		"sent": 0,
		"buffer": PackedByteArray(),
		"size": -1,
		"sender": true,
		"deadline": Time.get_ticks_msec() + SEND_TIMEOUT_MS
	})
	return OK


func _process(_delta: float) -> void:
	if server.is_connection_available():
		var peer := server.take_connection()
		if connections.size() >= MAX_CONNECTIONS:
			peer.disconnect_from_host()
		else:
			connections.append({
				"peer": peer,
				"buffer": PackedByteArray(),
				"size": -1,
				"sender": false,
				"deadline": Time.get_ticks_msec() + SEND_TIMEOUT_MS
			})

	for index: int in range(connections.size() - 1, -1, -1):
		var item: Dictionary = connections[index]
		var peer: StreamPeerTCP = item.get("peer") as StreamPeerTCP
		if peer == null:
			connections.remove_at(index)
			continue

		peer.poll()
		if (
			Time.get_ticks_msec() > int(item.get("deadline", 0))
			or peer.get_status() in [
				StreamPeerTCP.STATUS_ERROR,
				StreamPeerTCP.STATUS_NONE
			]
		):
			peer.disconnect_from_host()
			connections.remove_at(index)
			continue

		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue

		if bool(item.get("sender", false)):
			var out: PackedByteArray = item.get("out", PackedByteArray())
			var sent := int(item.get("sent", 0))
			if sent < out.size():
				var chunk := out.slice(sent, mini(sent + 8192, out.size()))
				var result := peer.put_partial_data(chunk)
				if result[0] != OK:
					item["deadline"] = 0
				else:
					item["sent"] = sent + int(result[1])

		var available := peer.get_available_bytes()
		if available > 0:
			var result := peer.get_data(mini(available, 8192))
			if result[0] != OK:
				item["deadline"] = 0
				continue
			var received_buffer: PackedByteArray = item.get(
				"buffer",
				PackedByteArray()
			)
			received_buffer.append_array(result[1])
			item["buffer"] = received_buffer

		if bool(item.get("sender", false)):
			# Receiver replies with one byte. The local event is already saved
			# and displayed, so a missing ACK never blocks the roller.
			var ack: PackedByteArray = item.get("buffer", PackedByteArray())
			if ack.size() > 0:
				peer.disconnect_from_host()
				connections.remove_at(index)
			continue

		var buffer: PackedByteArray = item.get(
			"buffer",
			PackedByteArray()
		)
		if int(item.get("size", -1)) == -1 and buffer.size() >= 4:
			item["size"] = buffer.decode_u32(0)
			item["buffer"] = buffer.slice(4)
			buffer = item["buffer"]
			if (
				int(item["size"]) <= 0
				or int(item["size"]) > MAX_BYTES
			):
				item["deadline"] = 0
				continue

		var wanted := int(item.get("size", -1))
		buffer = item.get("buffer", PackedByteArray())
		if wanted > 0 and buffer.size() >= wanted:
			var accepted := _accept_message(
				buffer.slice(0, wanted)
			)
			peer.put_data(PackedByteArray([1 if accepted else 0]))
			peer.disconnect_from_host()
			connections.remove_at(index)


func _accept_message(payload: PackedByteArray) -> bool:
	var parsed: Variant = JSON.parse_string(
		payload.get_string_from_utf8()
	)
	if not parsed is Dictionary:
		return false
	var message: Dictionary = parsed as Dictionary
	if String(message.get("magic", "")) != MAGIC:
		return false
	if String(message.get("key", "")) != session_key:
		return false
	if String(message.get("kind", "")) != "event":
		return false

	var event_value: Variant = message.get("event", {})
	if not event_value is Dictionary:
		return false
	var event: Dictionary = event_value as Dictionary
	if not valid_event(event):
		return false

	event_received.emit(event.duplicate(true))
	return true


static func valid_event(event: Dictionary) -> bool:
	var event_id := String(event.get("id", "")).strip_edges()
	if event_id.is_empty() or event_id.length() > 160:
		return false

	var kind := String(event.get("kind", ""))
	if kind not in ["roll", "chat", "action"]:
		return false

	var author := String(event.get("author", ""))
	if author.length() > 80:
		return false

	var timestamp: Variant = event.get("timestamp", 0)
	if not (timestamp is int or timestamp is float):
		return false

	if event.has("round"):
		var round_value: Variant = event.get("round", 0)
		if not (round_value is int or round_value is float):
			return false
		var round_number := int(round_value)
		if round_number < 1 or round_number > 999999:
			return false

	if event.has("actor"):
		var actor := String(event.get("actor", ""))
		if actor.length() > 120:
			return false

	if kind in ["chat", "action"]:
		var text_value := String(event.get("text", ""))
		return (
			not text_value.strip_edges().is_empty()
			and text_value.length() <= 1000
		)

	var label := String(event.get("label", ""))
	if label.length() > 160:
		return false

	var die := String(event.get("die", ""))
	if die not in [
		"d20", "d12", "d10", "d8",
		"d6", "d4", "d100", "d%", "formula"
	]:
		return false

	var total_value: Variant = event.get("total", 0)
	if not (total_value is int or total_value is float):
		return false
	var total := int(total_value)

	if die == "formula":
		var formula_count_value: Variant = event.get("count", 0)
		var formula_modifier_value: Variant = event.get("modifier", 0)
		var terms_value: Variant = event.get("terms", [])
		if not (formula_count_value is int or formula_count_value is float):
			return false
		if not (formula_modifier_value is int or formula_modifier_value is float):
			return false
		if not terms_value is Array:
			return false

		var formula_count := int(formula_count_value)
		var formula_modifier := int(formula_modifier_value)
		if formula_count < 1 or formula_count > 100:
			return false
		if formula_modifier < -9999 or formula_modifier > 9999:
			return false
		if String(event.get("notation", "")).length() > 500:
			return false
		if String(event.get("detail", "")).length() > 4000:
			return false

		var formula_expected_total := formula_modifier
		var seen_dice := 0
		for term_value: Variant in (terms_value as Array):
			if not term_value is Dictionary:
				return false
			var term: Dictionary = term_value as Dictionary
			var term_count := int(term.get("count", 0))
			var formula_sides := int(term.get("sides", 0))
			var term_sign := int(term.get("sign", 1))
			if term_count < 1 or term_count > 100:
				return false
			if formula_sides < 2 or formula_sides > 1000:
				return false
			if term_sign not in [-1, 1]:
				return false

			var formula_rolls_value: Variant = term.get("rolls", [])
			if not formula_rolls_value is Array:
				return false
			var formula_rolls: Array = formula_rolls_value as Array
			if formula_rolls.size() != term_count:
				return false

			for roll_value: Variant in formula_rolls:
				if not (roll_value is int or roll_value is float):
					return false
				var roll := int(roll_value)
				if roll < 1 or roll > formula_sides:
					return false
				formula_expected_total += term_sign * roll
				seen_dice += 1

		return seen_dice == formula_count and total == formula_expected_total

	# Backward compatibility with history generated before multi-die rolls.
	if not event.has("rolls"):
		if die in ["d%", "d100"]:
			return total >= 1 and total <= 100
		var legacy_sides := int(die.trim_prefix("d"))
		return total >= 1 and total <= legacy_sides

	var count_value: Variant = event.get("count", 1)
	var modifier_value: Variant = event.get("modifier", 0)
	if not (count_value is int or count_value is float):
		return false
	if not (modifier_value is int or modifier_value is float):
		return false

	var count := int(count_value)
	var modifier := int(modifier_value)
	if count < 1 or count > 100:
		return false
	if modifier < -9999 or modifier > 9999:
		return false

	var rolls_value: Variant = event.get("rolls", [])
	if not rolls_value is Array:
		return false
	var rolls: Array = rolls_value as Array
	if rolls.size() != count:
		return false

	var roll_mode := String(event.get("roll_mode", "normal")).strip_edges().to_lower()
	if roll_mode not in ["normal", "advantage", "disadvantage"]:
		return false
	if roll_mode != "normal":
		if die != "d20":
			return false
		var candidate_value: Variant = event.get("candidate_rolls", [])
		if not candidate_value is Array:
			return false
		var candidates: Array = candidate_value as Array
		if candidates.size() != count:
			return false
		for index: int in range(candidates.size()):
			var pair_value: Variant = candidates[index]
			if not pair_value is Array:
				return false
			var pair: Array = pair_value as Array
			if pair.size() != 2:
				return false
			var first := int(pair[0])
			var second := int(pair[1])
			if first < 1 or first > 20 or second < 1 or second > 20:
				return false
			var expected_kept := (
				maxi(first, second)
				if roll_mode == "advantage"
				else mini(first, second)
			)
			if int(rolls[index]) != expected_kept:
				return false

	var sides := 100 if die in ["d%", "d100"] else int(
		die.trim_prefix("d")
	)
	var expected_total := modifier
	for roll_value: Variant in rolls:
		if not (roll_value is int or roll_value is float):
			return false
		var roll := int(roll_value)
		if roll < 1 or roll > sides:
			return false
		expected_total += roll

	if total != expected_total:
		return false

	if event.has("detail") and String(event.get("detail", "")).length() > 4000:
		return false

	return true


func _exit_tree() -> void:
	server.stop()
	for item: Dictionary in connections:
		var peer: StreamPeerTCP = item.get("peer") as StreamPeerTCP
		if peer != null:
			peer.disconnect_from_host()
	connections.clear()
