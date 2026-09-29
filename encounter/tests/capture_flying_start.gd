extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1400,900)
	var scene = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	await create_timer(.8).timeout
	var u: float = scene.measurement_tool.meters_to_world(1)
	for i in range(3):
		var vehicle = scene.tokens_root.get_child(6+i)
		assert(vehicle.flying)
		assert(absf(vehicle.deck.global_position.y-150*u)<.001)
		assert(vehicle.global_position.z>scene.get_node("KaosRoot").global_position.z)
		for seat in range(2):
			assert(scene.tokens_root.get_child(i*2+seat).grid_support==vehicle.deck)
	scene.get_node("UI").hide()
	var center: Vector3 = scene.tokens_root.get_child(7).global_position
	scene.camera.global_position = center+Vector3(12,7,13)
	scene.camera.look_at(center)
	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	print("PASS: three flying vehicles at 150 m behind Kaos, two supported passengers each")
	quit()
