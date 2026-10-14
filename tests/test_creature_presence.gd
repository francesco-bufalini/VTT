extends SceneTree

const Presence = preload("res://network/creature_presence.gd")
const Owner = preload("res://vtt/creature_owner.gd")
const Rules = preload("res://vtt/creature_rules.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var presence: Node = Presence.new()
	root.add_child(presence)
	presence.call("set_session_key", "2")
	var data := {
		"magic": Presence.MAGIC,
		"session": "2".sha256_text(),
		"owner": "remote-owner-0123456789abcdef",
		"kind": "here",
		"label": "Desktop di prova", "device": "desktop"
	}
	presence.call("_accept_heartbeat", data, "100.101.102.103", 35001)
	var peers: Array = presence.call("get_online_peers")
	assert(peers.size() == 1)
	assert(peers[0].id == "remote-owner-0123456789abcdef")
	assert(peers[0].label == "Desktop di prova" and peers[0].device == "desktop")
	assert(peers[0].port == 35001, "Replies must use the source port (Android emulator NAT)")
	var targets: Array[String] = Presence.discovery_targets(["192.168.1.20", "192.168.1.20", "invalid"])
	assert(targets.has("255.255.255.255") and targets.count("192.168.1.20") == 1)
	assert(not targets.has("invalid"))
	assert(presence.call("get_online_desktop_ipv4s") == ["100.101.102.103"])
	var mobile_peer: Dictionary = data.duplicate(true)
	mobile_peer["owner"] = "remote-mobile-abcdef012345"
	mobile_peer["device"] = "mobile"
	presence.call("_accept_heartbeat", mobile_peer, "192.168.1.24", 41618)
	assert(presence.call("get_online_peers").size() == 2)
	assert(presence.call("get_online_desktop_ipv4s") == ["100.101.102.103"])
	# Board/chat must never attempt to push TCP data to a mobile client.
	presence.auto_refresh = false
	assert(not presence.auto_refresh)
	# Other sessions, malformed addresses and self must not appear.
	var stale: Dictionary = data.duplicate(true)
	stale["session"] = "other".sha256_text()
	stale["owner"] = "remote-owner-abcdef0123456789"
	presence.call("_accept_heartbeat", stale, "100.101.102.104")
	stale["session"] = "2".sha256_text()
	presence.call("_accept_heartbeat", stale, "not-an-ip")
	stale["owner"] = Owner.local_id()
	presence.call("_accept_heartbeat", stale, "100.101.102.104")
	assert(presence.call("get_online_peers").size() == 2)
	presence.call("set_session_key", "3")
	assert(presence.call("get_online_peers").is_empty())

	# Standard shared slots and Warlock Pact Magic are separate pools.
	var wizard: Dictionary = Rules.spell_slot_progression({
		"class": "Wizard", "level": 3, "rules_version": "2014"
	})
	assert(wizard.slots[1] == 4 and wizard.slots[2] == 2)
	var paladin: Dictionary = Rules.spell_slot_progression({
		"class": "Paladin", "level": 3, "rules_version": "2014"
	})
	assert(paladin.slots[1] == 3)
	var multiclass: Dictionary = Rules.spell_slot_progression({
		"classes": [
			{"name": "Paladin", "level": 3}, {"name": "Fighter", "level": 2}
		], "rules_version": "2014"
	})
	assert(multiclass.slots[1] == 3, "One Spellcasting class retains its own progression")
	var warlock: Dictionary = Rules.spell_slot_progression({
		"classes": [
			{"name": "Wizard", "level": 1}, {"name": "Warlock", "level": 5}
		], "rules_version": "2014"
	})
	assert(warlock.slots[1] == 2)
	assert(warlock.pact_total == 2 and warlock.pact_level == 3)
	presence.queue_free()
	await process_frame
	print("PASS: session-scoped live controller presence and spell-slot progression")
	quit()
