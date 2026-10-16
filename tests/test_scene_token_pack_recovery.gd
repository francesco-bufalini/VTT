extends SceneTree

class SceneToken extends Node3D:
	var pack_id := ""
	var visual := ""
	func _ready() -> void:
		add_to_group("dnd_token")
	func get_token_pack_id() -> String:
		return pack_id
	func get_visual_asset_path() -> String:
		return visual
	func set_visual_asset(path: String, _footprint: float) -> bool:
		visual = path
		return true

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if "--live-download" in OS.get_cmdline_user_args():
		await _verify_live_download()
		return
	var old_token: Node = load("res://token.tscn").instantiate()
	old_token.visual_asset_path = "res://remote_tokens/gilliam/gilliam_visual.res"
	assert(old_token.get_token_pack_id() == "gilliam", "Missing packs must not hide the ID of a legacy scene token")
	old_token.free()
	var board := Node3D.new()
	var tokens := Node3D.new()
	board.add_child(tokens)
	var existing := SceneToken.new()
	existing.pack_id = "gilliam"
	tokens.add_child(existing)
	var legacy := SceneToken.new()
	legacy.visual = "res://remote_tokens/kryss/kryss_visual.res"
	tokens.add_child(legacy)
	# Another board must not contribute downloads or receive visual updates.
	var other := SceneToken.new()
	other.pack_id = "kaos"
	root.add_child(other)
	root.add_child(board)
	var manager := root.get_node("TokenPackManager")
	var original_entries: Dictionary = manager.get("_entries_by_id")
	manager.set("_entries_by_id", {})
	var sync: Node = load("res://tests/fixtures/scene_pack_sync_probe.gd").new()
	board.add_child(sync)
	sync.set_process(false)
	sync.setup(board, null, tokens, null)
	await process_frame
	assert(sync._pending_token_pack_ids.has("gilliam"), "Entering a scene must request authored miniature IDs")
	assert(sync._pending_token_pack_ids.has("kryss"), "Legacy visual paths must resolve to pack IDs")
	assert(not sync._pending_token_pack_ids.has("kaos"), "Only this scene's tokens may be requested")
	var added := SceneToken.new()
	added.pack_id = "wyrda"
	tokens.add_child(added)
	await process_frame
	assert(sync._pending_token_pack_ids.has("wyrda"), "Tokens added after setup must recover automatically")
	sync._pending_token_pack_ids.clear()
	var refreshed: Array[Dictionary] = []
	sync._on_token_pack_catalog_updated(refreshed)
	assert(sync._pending_token_pack_ids.has("gilliam"), "A catalog refresh must retry previously failed scene packs")
	sync._apply_mounted_pack_to_tokens("gilliam")
	assert(existing.visual == "res://remote_tokens/gilliam/gilliam_visual.res")
	assert(other.visual.is_empty(), "A mounted pack must not change another board")
	board.free()
	manager.set("_entries_by_id", original_entries)
	other.free()
	print("PASS: scene entry, added tokens and catalog refresh recover required miniature packs")
	quit(0)


func _verify_live_download() -> void:
	var manager := root.get_node("TokenPackManager")
	var board := Node3D.new()
	var tokens := Node3D.new()
	board.add_child(tokens)
	var token := SceneToken.new()
	var pack_id := "gilliam"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--pack-id="):
			pack_id = argument.trim_prefix("--pack-id=")
	token.pack_id = pack_id
	var was_cached: bool = manager.call("is_downloaded", pack_id)
	tokens.add_child(token)
	root.add_child(board)
	var sync: Node = load("res://tests/fixtures/scene_pack_sync_probe.gd").new()
	board.add_child(sync)
	sync.set_process(false)
	sync.setup(board, null, tokens, null)
	var deadline := Time.get_ticks_msec() + 120000
	while token.visual.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	var success := not token.visual.is_empty() and bool(manager.call("is_mounted", pack_id))
	board.free()
	if not success:
		push_error("Scene entry did not recover %s within 120 seconds" % pack_id)
		quit(1)
		return
	print("PASS: real scene entry recovered %s (already cached: %s), SHA-verified, mounted and applied" % [pack_id, was_cached])
	quit(0)
