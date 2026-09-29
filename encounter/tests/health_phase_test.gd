extends SceneTree
var scene
var output: String
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool,label: String) -> void:
	if not ok:
		push_error(label)
		quit(1)
		assert(ok,label)
func shot(label: String) -> void:
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func run() -> void:
	root.size = Vector2i(1400,900)
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	await create_timer(.4).timeout
	var c = scene.encounter
	c.config.advance_duration = .05
	c.kaos.climb.duration = .1
	var motion = c.kaos.motion
	scene.get_node("UI").hide()
	var scale_u: float = scene.measurement_tool.meters_to_world(1)
	var origin: Vector3 = c.kaos.global_position
	scene.camera.global_position = origin+Vector3(100,85,-130)*scale_u
	scene.camera.look_at(origin+Vector3(0,65,0)*scale_u)
	motion.set_stride(.5)
	await shot("stride-left")
	check(motion._meshes[0].get_blend_shape_value(0)>.9,"First leg stride")
	motion.set_stride(1.5)
	await shot("stride-right")
	check(motion._meshes[0].get_blend_shape_value(1)>.9,"Opposite leg stride")
	motion.crouch(1)
	await shot("jump-crouch")
	check(motion._meshes[0].get_blend_shape_value(2)>.9,"Jump crouch")
	motion.reset()
	var rider = scene.tokens_root.get_child(0)
	var hands: Node3D = scene.get_node("HandPlatforms")
	check(hands.get_child_count()==2,"Two hand platforms")
	for platform in hands.get_children():
		rider.grid_support = null
		rider.global_position = platform.global_position+Vector3(.5,1.08,.5)
		await create_timer(.3).timeout
		check(rider.grid_support==platform,"Hand grid supports tokens")
	c.register_kaos_damage(100)
	check(c.giant_hp==102 and not c.kaos_slowed,"Regeneration must reduce slowing damage")
	await c.advance_encounter()
	check(c.giant_hp==112 and c.kaos_step==8,"Heal ten then move two steps")
	c.reset_encounter(123)
	c.register_kaos_damage(110)
	check(c.kaos_slowed,"110 less 10 must slow")
	await c.advance_encounter()
	check(c.kaos_step==9 and c.giant_hp==102,"Slowed step and HP")
	c.register_kaos_damage(1000)
	check(c.giant_petrified and c.avatar_hp==200 and c.kaos_step==9,"Immediate early petrification; no damage overflow")
	await create_timer(.2).timeout
	check(c.petrification.avatar.grid_support==c.kaos.get_node("ShoulderPlatform"),"Avatar lands on expanded head space")
	var saved: Dictionary = c.get_save_state()
	check(c.load_state(saved),"Petrified save reload")
	check(scene.tokens_root.get_child_count()==10,"No duplicate avatars")
	c.register_kaos_damage(200)
	check(c.encounter_finished,"Avatar defeat ends encounter")
	check(not c.petrification.avatar.is_physics_processing(),"End freezes tokens")
	c.reset_encounter(123)
	for i in range(5):
		await c.advance_encounter()
	check(c.kaos_step==0 and not c.encounter_finished,"Arrival does not end battle")
	var kface: Node3D = c.kaos.get_node("ClimbingVisual/FaceAnchor")
	var face: Node3D = scene.get_node("KlothisRoot/KlothisVisual/FaceAnchor")
	check(absf(kface.global_position.x-face.global_position.x)<.01 and absf(kface.global_position.y-face.global_position.y)<.01,"Faces at matching height")
	scene.get_node("UI").hide()
	var u: float = scene.measurement_tool.meters_to_world(1)
	scene.camera.global_position = face.global_position+Vector3(125,40,210)*u
	scene.camera.look_at(face.global_position-Vector3(0,40,0)*u)
	await shot("aligned-on-sphere")
	var ui = scene.get_node("UI/EncounterUI")
	ui._damage.value = 202
	ui._apply_damage()
	ui._apply_damage()
	check(c.giant_petrified and c.avatar_hp==200 and not c.encounter_finished,"Double UI click must not kill new avatar")
	check(ui._damage.value==0,"Consumed damage is cleared")
	await create_timer(1.5).timeout
	await shot("stone-body")
	var platform: Node3D = c.kaos.get_node("ShoulderPlatform")
	scene.camera.global_position = platform.global_position+Vector3(16,13,18)
	scene.camera.look_at(platform.global_position)
	await shot("phase-two-token")
	for mesh in c.kaos.get_node("ClimbingVisual").get_children():
		var role := String(mesh.get_meta("visual_role",""))
		if "Hair" in role or "Lock" in role or "Crown" in role:
			check(not mesh.visible,"All head/hair geometry hidden")
	saved = c.get_save_state()
	check(c.load_state(saved),"Sphere petrification reload")
	for i in range(3):
		c.register_seal_damage(i,100)
	check(c.encounter_finished,"All seals end encounter")
	check(c.load_state(c.get_save_state()),"Finished reload")
	print("PASS: HP, regeneration, slowing, early/sphere petrification, avatar, both endings, reload, alignment")
	quit()
