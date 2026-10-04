extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var pck_path := _arg_value(args, "--pck", "").strip_edges()
	var scene_path := _arg_value(args, "--scene", "").strip_edges()
	var expected_id := _arg_value(args, "--token-id", "").strip_edges()

	if pck_path.is_empty() or scene_path.is_empty():
		push_error("Usage: --pck <path> --scene <res://...>")
		quit(2)
		return

	var absolute_pck := (
		ProjectSettings.globalize_path(pck_path)
		if pck_path.begins_with("res://") or pck_path.begins_with("user://")
		else pck_path
	)
	if not FileAccess.file_exists(absolute_pck):
		push_error("PCK not found: %s" % absolute_pck)
		quit(3)
		return

	if not ProjectSettings.load_resource_pack(absolute_pck, false):
		push_error("Could not mount PCK: %s" % absolute_pck)
		quit(4)
		return

	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		push_error("PackedScene not loadable after mount: %s" % scene_path)
		quit(5)
		return

	var instance := packed.instantiate()
	if not instance is Node3D:
		push_error("PackedScene did not instantiate a Node3D")
		if instance != null:
			instance.queue_free()
		quit(6)
		return

	root.add_child(instance)
	await process_frame

	var token := instance as Node3D
	if not token.is_in_group("dnd_token"):
		push_error("Remote scene is not behaving as token.tscn: missing dnd_token group")
		token.queue_free()
		quit(7)
		return
	for method_name: StringName in [
		&"configure",
		&"set_visual_asset",
		&"set_selected",
		&"set_conditions",
		&"get_visual_asset_path",
	]:
		if not token.has_method(method_name):
			push_error("Remote token misses base method: %s" % method_name)
			token.queue_free()
			quit(8)
			return

	var loaded_visual := String(token.call("get_visual_asset_path"))
	if loaded_visual.is_empty() or not loaded_visual.begins_with("res://remote_tokens/"):
		push_error("Remote token did not load its packed visual: %s" % loaded_visual)
		token.queue_free()
		quit(9)
		return

	print("TOKEN_PACK_VERIFY_OK id=%s scene=%s visual=%s" % [
		expected_id,
		scene_path,
		loaded_visual
	])
	token.queue_free()
	await process_frame
	quit(0)


func _arg_value(args: PackedStringArray, key: String, fallback: String) -> String:
	var index := args.find(key)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return fallback
