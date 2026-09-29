extends SceneTree
var scene
var output := "C:/Users/fedeb/Documents/Codex/outputs/kaos-collar-fists"
func _initialize() -> void:
	call_deferred("run")
func shot(label: String) -> void:
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func run() -> void:
	root.size = Vector2i(1400,900)
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	await create_timer(.5).timeout
	var fields = scene.find_children("*", "SpinBox", true, false)
	assert(not fields.is_empty())
	var field: SpinBox = fields.back()
	field.get_line_edit().grab_focus()
	var old_value := field.value
	var vehicle = scene.tokens_root.get_child(6)
	scene._replace_selection(vehicle)
	var old_position: Vector3 = vehicle.global_position
	var event := InputEventKey.new()
	event.keycode = KEY_UP
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await physics_frame
	assert(vehicle.global_position.distance_to(old_position)>.1,"Arrow moves selected token while GUI focused")
	assert(field.value==old_value,"Arrow does not edit GUI value")
	event.pressed = false
	Input.parse_input_event(event)
	scene._replace_selection(null)
	var actor = scene.get_node("KaosRoot")
	var u: float = scene.measurement_tool.meters_to_world(1)
	for mesh in actor.get_node("KaosVisual").get_children():
		if mesh is MeshInstance3D and String(mesh.name).begins_with("Anatomy"):
			for y in [90,100,110]:
				var lo := 1000.0
				var hi := -1000.0
				for raw in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					var p: Vector3 = mesh.transform*raw/u
					if absf(p.y-y)<1 and absf(p.x)<4:
						lo=minf(lo,p.z)
						hi=maxf(hi,p.z)
				print("TORSO ",y," ",lo," ",hi)
	scene.camera.global_position = actor.global_position+Vector3(60,108,-170)*u
	scene.camera.look_at(actor.global_position+Vector3(0,82,0)*u)
	await shot("kaos-veil-front")
	scene.get_node("UI").hide()
	scene.camera.global_position = actor.global_position+Vector3(28,138,-53)*u
	scene.camera.look_at(actor.global_position+Vector3(0,134,0)*u)
	await shot("kaos-hair-close")
	scene.camera.global_position = actor.global_position+Vector3(42,134,-7)*u
	scene.camera.look_at(actor.global_position+Vector3(0,133,-4)*u)
	await shot("kaos-profile")
	scene.camera.global_position = actor.global_position+Vector3(30,106,-42)*u
	scene.camera.look_at(actor.global_position+Vector3(0,90,0)*u)
	await shot("kaos-belt")
	scene.camera.global_position = actor.global_position+Vector3(48,80,-42)*u
	scene.camera.look_at(actor.global_position+Vector3(20,71,-17)*u)
	await shot("kaos-fist")
	scene.camera.global_position = actor.global_position+Vector3(62,104,25)*u
	scene.camera.look_at(actor.global_position+Vector3(0,103,0)*u)
	await shot("kaos-side")
	var c = scene.encounter
	c.config.advance_duration = .05
	for i in range(5):
		await c.advance_encounter()
	var face = scene.get_node("KlothisRoot/KlothisVisual/FaceAnchor")
	scene.camera.global_position = face.global_position+Vector3(150,0,115)*u
	scene.camera.look_at(face.global_position-Vector3(0,38,0)*u)
	await shot("kaos-climb")
	scene.camera.global_position = face.global_position+Vector3(90,-6,92)*u
	scene.camera.look_at(face.global_position+Vector3(22,-25,14)*u)
	await shot("kaos-arm-close")
	c.register_kaos_damage(202)
	assert(c.giant_petrified and c.avatar_hp==200 and not c.encounter_finished)
	print("PASS: updated visuals rendered, climb completed, phase two retains 200 HP")
	quit()
