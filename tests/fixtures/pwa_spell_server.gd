extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	await process_frame
	var host := root.get_node("PwaHost")
	host._listen_port = 0
	var board: Node3D = load("res://dnd_base.tscn").instantiate()
	board.set_script(load("res://tests/fixtures/pwa_spell_board.gd"))
	root.add_child(board)
	current_scene = board
	assert(host._start_listener() == OK)
	var path := OS.get_environment("VTT_PWA_FIXTURE_INFO")
	assert(not path.is_empty())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"port": host._server.get_local_port(), "token": host._token}))
	file.close()
	print("READY: isolated PWA spell fixture")
	await create_timer(180).timeout
	quit()
