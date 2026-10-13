extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var menu := load("res://vtt/menu/main_menu.tscn").instantiate() as Control
	root.add_child(menu)
	for viewport_size: Vector2i in [Vector2i(360, 640), Vector2i(640, 360), Vector2i(1280, 720)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		var actions := menu.get_node("BottomControls") as Control
		var title := menu.get_node("TitleArea") as Control
		if actions.get_global_rect().end.x > menu.size.x + 1.0 or actions.get_global_rect().end.y > menu.size.y + 1.0:
			push_error("Menu actions exceed viewport at %s" % viewport_size)
			quit(1)
			return
		if title.get_global_rect().end.x > menu.size.x + 1.0:
			push_error("Menu title exceeds viewport at %s" % viewport_size)
			quit(1)
			return
	menu.queue_free()
	await process_frame
	print("PASS: menu bounds at phone portrait, landscape and desktop sizes")
	quit(0)