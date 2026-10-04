extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for script_path: String in [
		"res://vtt/menu/main_menu.gd",
		"res://vtt/menu/menu_backdrop.gd"
	]:
		var menu: Control = load(script_path).new()
		root.add_child(menu)
		var paths: Array = menu.get("_background_paths")
		if paths.is_empty():
			push_error("Menu backgrounds missing: " + script_path)
			quit(1)
			return
		for texture_path: String in paths:
			if not (load(texture_path) is Texture2D):
				push_error("Menu background cannot load: " + texture_path)
				quit(1)
				return
		var layers: Array = menu.get("_background_layers")
		if layers.size() != 2 or layers[0].texture == null:
			push_error("Menu background layers not initialized: " + script_path)
			quit(1)
			return
		print("Menu backgrounds loaded: %d (%s)" % [paths.size(), script_path])
		menu.queue_free()
		await process_frame
	print("PASS: menu backgrounds and textures load in source and exported packs")
	quit()
