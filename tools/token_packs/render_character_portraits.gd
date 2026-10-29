extends SceneTree
## Render calibrated pack visuals without changing their geometry or materials.
## Run with a rendering driver, --pack-dir PATH --output-dir PATH --spec PATH.

func _initialize() -> void:
	call_deferred("run")

func arg(key: String) -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(key)
	assert(index >= 0 and index + 1 < args.size(), key)
	return args[index + 1]

func bounds(node: Node3D, parent := Transform3D.IDENTITY) -> AABB:
	var transform_acc := parent * node.transform
	var box := AABB()
	if node is MeshInstance3D and node.mesh != null:
		box = transform_acc * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var child_box := bounds(child, transform_acc)
			if child_box.size != Vector3.ZERO:
				box = child_box if box.size == Vector3.ZERO else box.merge(child_box)
	return box

func run() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(arg("--spec")))
	var output := arg("--output-dir")
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1000, 1000)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.15, 0.19, 0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	for angle in [-35, 145]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35, angle, 0)
		light.light_energy = 1.0
		world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(camera)
	camera.current = true
	var records: Array[Dictionary] = []
	for profile: Dictionary in spec.tokens:
		var id := String(profile.id)
		var pack := arg("--pack-dir").path_join(id + ".pck")
		assert(FileAccess.get_sha256(pack) == profile.pack_sha256, id)
		assert(ProjectSettings.load_resource_pack(pack, false), pack)
		var visual := (load("res://remote_tokens/%s/%s_visual.res" % [id, id]) as PackedScene).instantiate() as Node3D
		world.add_child(visual)
		var box := bounds(visual)
		var center := box.get_center()
		camera.size = maxf(box.size.y, box.size.x) * 1.12
		var direction := Vector3(0, 0, -1 if profile.view == "back" else 1)
		camera.position = center + direction * maxf(3.0, box.size.length() * 2.0)
		camera.look_at(center)
		for frame in range(5):
			await process_frame
		await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().save_png(output.path_join(id + ".png")) == OK)
		records.append({"id": id, "camera_height": camera.size, "ground_pixel": 500.0 + center.y / camera.size * 1000.0, "pixels_per_cell": 1000.0 / camera.size})
		visual.free()
		print("PORTRAIT_RENDERED ", id)
	var file := FileAccess.open(output.path_join("render_metrics.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	print("PASS: character portrait renders complete")
	quit()
