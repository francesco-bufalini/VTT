extends SceneTree
var output: String
func _initialize() -> void:
	call_deferred("run")
func shot(label: String) -> void:
	for frame in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func run() -> void:
	root.size = Vector2i(1600,1000)
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var scene = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	await shot("overview")
	scene.get_node("UI").visible = false
	var units: float = scene.measurement_tool.meters_to_world(1)
	for character in ["Kaos", "Klothis"]:
		var visual: Node3D = scene.get_node(character+"Root/"+character+"Visual")
		var front := -1.0 if character == "Kaos" else 1.0
		scene.camera.position = visual.global_position+Vector3(65,95,front*195)*units
		scene.camera.look_at(visual.global_position+Vector3(0,80,-10)*units)
		await shot(character.to_lower()+"-scene")
		scene.camera.position = visual.global_position+Vector3(20,138,front*57)*units
		scene.camera.look_at(visual.global_position+Vector3(0,129,-4)*units)
		await shot(character.to_lower()+"-close")
	print("Character captures completed")
	quit()
