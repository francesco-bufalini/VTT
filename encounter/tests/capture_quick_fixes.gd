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
	await create_timer(.6).timeout
	assert(scene.tokens_root.get_child_count()==5)
	await shot("water-overview")
	scene.get_node("UI").hide()
	var center := Vector3.ZERO
	for token in scene.tokens_root.get_children():
		center += token.global_position/5
		assert(token.has_meta("party_skin"))
	scene.camera.global_position = center+Vector3(2,3,-11)
	scene.camera.look_at(center)
	scene._replace_selection(scene.tokens_root.get_child(2))
	await shot("five-tokens")
	await create_timer(.8).timeout
	await shot("water-animation")
	var u: float = scene.measurement_tool.meters_to_world(1)
	var origin: Vector3 = scene.get_node("KaosRoot/KaosVisual").global_position
	scene.camera.global_position = origin+Vector3(-40,132,-34)*u
	scene.camera.look_at(origin+Vector3(-26,123,-6)*u)
	await shot("kaos-wrist")
	origin = scene.get_node("KlothisRoot/KlothisVisual").global_position
	scene.camera.global_position = origin+Vector3(23,119,40)*u
	scene.camera.look_at(origin+Vector3(0,134,8)*u)
	await shot("blindfold-below")
	scene.camera.global_position = origin+Vector3(-27,139,35)*u
	scene.camera.look_at(origin+Vector3(0,134,8)*u)
	await shot("blindfold-side")
	print("Five skins, water and close-up corrections rendered")
	quit()
