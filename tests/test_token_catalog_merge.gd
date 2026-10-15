extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_token_catalog_merge.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager: Node = load("res://vtt/token_pack_manager.gd").new()
	var bundled := JSON.stringify({
		"version": 1,
		"tokens": [
			{"id": "dragon", "pck": "dragon.pck", "sha256": "abc", "release_tag": "MM-Dragons"},
			{"id": "knight", "pck": "knight.pck", "sha256": "def", "release_tag": "MM"},
		],
	})
	var subset := JSON.stringify({
		"version": 1,
		"tokens": [
			{"id": "dragon", "pck": "dragon-v2.pck", "sha256": "xyz", "release_tag": "  MM-Dragons  "},
			{"id": "pegasus", "pck": "pegasus.pck", "sha256": "ghi", "release_tag": "token-packs-test-001"},
		],
	})
	if not manager.call("_accept_catalog_text", bundled, false):
		_fail("Bundled catalog rejected")
		return
	if not manager.call("_accept_catalog_text", subset, false):
		_fail("Partial remote catalog rejected")
		return
	if not manager.call("has_token", "knight") or not manager.call("has_token", "pegasus"):
		_fail("Partial refresh discarded a bundled miniature")
		return
	var dragon: Dictionary = manager.call("get_entry", "dragon")
	if String(dragon.get("sha256", "")) != "xyz" or String(dragon.get("release_tag", "")) != "MM-Dragons":
		_fail("Updated remote miniature metadata is not retained or normalized")
		return
	var merged: Dictionary = manager.call("get_catalog")
	var token_array: Array = merged.get("tokens", [])
	if token_array.size() != 3:
		_fail("Merged catalog must contain 3 unique entries")
		return
	if manager.call("_accept_catalog_text", "{malformed JSON", false):
		_fail("Invalid remote JSON was erroneously accepted")
		return
	if not manager.call("has_token", "knight"):
		_fail("Invalid remote JSON erased working catalog")
		return
	var restored: Node = load("res://vtt/token_pack_manager.gd").new()
	if not restored.call("_accept_catalog_text", JSON.stringify(merged), false):
		_fail("Merged catalog cannot be read after restart")
		return
	if (restored.call("get_entries") as Array).size() != 3:
		_fail("Persisted merged catalog lost entries")
		return
	restored.free()
	manager.free()
	print("PASS: online subset merges with bundled catalog without losing miniatures")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
