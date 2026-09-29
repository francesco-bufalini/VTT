extends SceneTree
var scene
var output: String
func _initialize() -> void:
	call_deferred("run")
func shot(label: String) -> void:
	for i in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func run() -> void:
	root.size = Vector2i(1400,900)
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	await create_timer(1.0).timeout
	assert(scene.tokens_root.get_child_count()==9)
	scene.get_node("UI").hide()
	var chariot = scene.tokens_root.get_child(6)
	var rider = scene.tokens_root.get_child(0)
	rider.global_position = chariot.deck.to_global(Vector3(-.5,1.15,-.5)*scene.cell_size)
	await create_timer(.8).timeout
	assert(rider.grid_support == chariot.deck, "Passenger must land on chariot")
	var local_before: Vector3 = chariot.deck.to_local(rider.global_position)
	chariot.nudge_grid(Vector2i(1,0))
	await create_timer(.2).timeout
	assert(chariot.deck.to_local(rider.global_position).distance_to(local_before)<.08, "Passenger follows translation")
	chariot.rotate_grid(1)
	await create_timer(.2).timeout
	assert(chariot.deck.to_local(rider.global_position).distance_to(local_before)<.08, "Passenger follows rotation")
	chariot.set_flying(true)
	chariot.nudge_vertical(2)
	await create_timer(.3).timeout
	assert(rider.grid_support == chariot.deck, "Passenger follows flight")
	var selected: Array[CharacterBody3D] = [chariot]
	scene.token_drag.begin(selected,chariot)
	assert(not scene.token_drag.preview_at(chariot.global_position,chariot.deck), "Cannot land on own deck")
	assert(scene.token_drag.preview_at(chariot.global_position+Vector3(0,0,5)), "Vehicle drag destination")
	scene.token_drag.finish(true)
	await create_timer(.3).timeout
	assert(chariot.deck.to_local(rider.global_position).distance_to(local_before)<.08, "Passenger follows drag")
	scene.camera.global_position = chariot.global_position+Vector3(6,4,-7)
	scene.camera.look_at(chariot.global_position+Vector3(0,.4,0))
	await shot("pegasus-chariot-passenger")
	var feathered = scene.tokens_root.get_child(5)
	scene.camera.global_position = feathered.global_position+Vector3(2,1,-4)
	scene.camera.look_at(feathered.global_position)
	await shot("feathered-woman")
	var u: float = scene.measurement_tool.meters_to_world(1)
	var origin: Vector3 = scene.get_node("KaosRoot/KaosVisual").global_position
	scene.camera.global_position = origin+Vector3(105,95,-180)*u
	scene.camera.look_at(origin+Vector3(0,75,0)*u)
	await shot("kaos-walking")
	chariot.set_flying(false)
	await create_timer(1.2).timeout
	assert(chariot.is_on_floor(), "Vehicle falls after removing flight")
	assert(rider.grid_support == chariot.deck, "Passenger remains on landed chariot")
	print("PASS: nine tokens; passenger landing, translation, rotation, flight; captures saved")
	quit()
