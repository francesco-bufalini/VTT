extends SceneTree
var scene
var output: String
var stages: Array[String] = []
var charge_start: int
var charge_elapsed: float
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool,label: String) -> void:
	if not ok:
		push_error(label)
		quit(1)
		assert(ok,label)
func shot(label: String) -> void:
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func key(code: int, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	event.shift_pressed = shift
	scene._unhandled_input(event)
func stage(value: String) -> void:
	stages.append(value)
	if value == "charge":
		charge_start = Time.get_ticks_msec()
	if value == "launch":
		charge_elapsed = (Time.get_ticks_msec()-charge_start)/1000.0
		print("Charge seconds: ",charge_elapsed)
func run() -> void:
	root.size = Vector2i(1400,900)
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	await create_timer(.5).timeout
	scene.get_node("UI").hide()
	for vehicle_index in range(3):
		var vehicle = scene.tokens_root.get_child(6+vehicle_index)
		scene._replace_selection(vehicle)
		var locals: Array[Vector3] = []
		for seat in range(2):
			locals.append(vehicle.deck.to_local(scene.tokens_root.get_child(vehicle_index*2+seat).global_position))
		for step in range(20):
			key(KEY_UP if step%2==0 else KEY_DOWN,true)
			await physics_frame
			for seat in range(2):
				var rider = scene.tokens_root.get_child(vehicle_index*2+seat)
				check(rider.grid_support==vehicle.deck,"Shift vertical preserves passenger support")
				check(vehicle.deck.to_local(rider.global_position).distance_to(locals[seat])<.03,"Shift vertical preserves local position")
		for code in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN]:
			key(code)
			await physics_frame
		key(KEY_RIGHT,true)
		await create_timer(.1).timeout
		for seat in range(2):
			check(vehicle.deck.to_local(scene.tokens_root.get_child(vehicle_index*2+seat).global_position).distance_to(locals[seat])<.03,"Horizontal/rotation carry")
	var rider = scene.tokens_root.get_child(0)
	var vehicle = scene.tokens_root.get_child(6)
	rider.nudge_grid(Vector2i(1,0))
	rider.nudge_grid(Vector2i(1,0))
	rider.nudge_grid(Vector2i(1,0))
	await create_timer(.2).timeout
	check(rider.grid_support!=vehicle.deck,"Walking off deck detaches")
	var c = scene.encounter
	c.config.advance_duration=.05
	for i in range(4):
		await c.advance_encounter()
	c.kaos.climb.stage_changed.connect(stage)
	var u: float = scene.measurement_tool.meters_to_world(1)
	var face: Node3D = scene.get_node("KlothisRoot/KlothisVisual/FaceAnchor")
	scene.camera.global_position = face.global_position+Vector3(145,25,115)*u
	scene.camera.look_at(face.global_position-Vector3(0,30,0)*u)
	c.advance_encounter()
	while c.is_advancing:
		await process_frame
	check(stages==["charge","launch","airborne","two_hands","settling","one_hand"],"Continuous stage order")
	check(charge_elapsed>=.95,"One second charge")
	var kface: Node3D = c.kaos.get_node("ClimbingVisual/FaceAnchor")
	check(absf(kface.global_position.y-face.global_position.y)<.01,"Same face height")
	check(kface.global_position.z-face.global_position.z>12*u,"Clear face gap")
	check(c.kaos.climb._pose_meshes[0].get_blend_shape_value(1)>.99,"Final one-hand pose")
	await shot("one-hand-side")
	scene.camera.global_position = face.global_position+Vector3(-115,25,170)*u
	scene.camera.look_at(face.global_position-Vector3(0,30,0)*u)
	await shot("one-hand-front")
	var saved: Dictionary = c.get_save_state()
	check(c.load_state(saved),"Load final pose")
	check(c.kaos.climb._pose_meshes[0].get_blend_shape_value(1)>.99,"Reload one-hand pose")
	print("PASS: all six passengers, repeated Shift up/down, horizontal/rotation, dismount, sequence, charge timing, face clearance, final pose reload")
	quit()
