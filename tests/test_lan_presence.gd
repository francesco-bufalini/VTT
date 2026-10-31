extends SceneTree
const Presence = preload("res://network/lan_presence.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var p := Presence.new()
	root.add_child(p)
	p.auto_refresh = false
	p.set_session_key("one game")
	var packet := {
		"magic": Presence.MAGIC, "session": "one game".sha256_text(),
		"owner": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
		"kind": "here", "label": "Remote board", "device": "desktop"
	}
	p._accept_heartbeat(packet, "127.0.0.1", Presence.PORT)
	assert(p.get_online_peers().size() == 1)
	assert(p.get_online_desktop_ipv4s() == ["127.0.0.1"])
	var invalid: Dictionary = packet.duplicate(true)
	invalid.kind = "document"
	p._accept_heartbeat(invalid, "10.0.0.2", Presence.PORT)
	assert(p.get_online_peers().size() == 1, "Obsolete document packets are ignored")
	p.set_session_key("another game")
	assert(p.get_online_peers().is_empty(), "Session changes forget discovered boards")
	assert(Presence.discovery_targets(["192.168.1.42"]).has("192.168.1.42"))
	p.queue_free()
	await process_frame
	print("PASS: desktop LAN discovery without native creature transfers")
	quit()
