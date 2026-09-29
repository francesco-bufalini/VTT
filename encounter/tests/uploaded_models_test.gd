extends SceneTree
var scene
var output := "C:/Users/fedeb/Documents/Codex/outputs/imports"
func _initialize() -> void:
	call_deferred("run")
func shot(label: String) -> void:
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func run() -> void:
	root.size = Vector2i(1400,900)
	scene = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	await create_timer(.5).timeout
	scene.get_node("UI").hide()
	assert(scene.tokens_root.get_child_count()==11,"Seven passengers and four vehicles")
	var phenax = scene.tokens_root.get_node("Phenax")
	var vehicle = scene.tokens_root.get_node("PhenaxChariot")
	assert(phenax.get_footprint_extent()==Vector2(2,2)*scene.cell_size)
	assert(vehicle.flying and phenax.grid_support==vehicle.deck)
	var local: Vector3 = vehicle.deck.to_local(phenax.global_position)
	for i in range(6):
		vehicle.nudge_vertical(1 if i%2==0 else -1)
		await physics_frame
		assert(vehicle.deck.to_local(phenax.global_position).distance_to(local)<.04)
	scene._replace_selection(phenax)
	scene.camera.global_position = phenax.global_position+Vector3(4,2,-6)
	scene.camera.look_at(phenax.global_position)
	await shot("phenax-and-hanoverian")
	scene.camera.global_position = phenax.global_position+Vector3(.9,1.2,-2.5)
	scene.camera.look_at(phenax.global_position+Vector3(0,.75,0))
	await shot("phenax-close")
	var first = scene.tokens_root.get_child(6)
	scene.camera.global_position = first.global_position+Vector3(4,2,-5)
	scene.camera.look_at(first.global_position+Vector3(0,.2,0))
	await shot("party-new-horse")
	var u: float = scene.measurement_tool.meters_to_world(1)
	var actor = scene.get_node("KaosRoot")
	scene.camera.global_position = actor.global_position+Vector3(110,100,-180)*u
	scene.camera.look_at(actor.global_position+Vector3(0,95,0)*u)
	await shot("kaos-greek-physique")
	actor.climb.prepare()
	actor.get_node("KaosVisual").hide()
	actor.get_node("ClimbingVisual").show()
	actor.climb._air_pose(1)
	actor.climb._one_hand_pose(0)
	await shot("kaos-airborne-pose")
	actor.climb.reset_pose()
	scene.encounter.register_kaos_damage(202)
	assert(scene.encounter.giant_petrified and scene.encounter.avatar_hp==200)
	assert(not scene.encounter.encounter_finished)
	var avatar = scene.tokens_root.get_node("KaosPhaseTwo")
	scene.camera.global_position = avatar.global_position+Vector3(4,2,-5)
	scene.camera.look_at(avatar.global_position)
	await shot("kaos-large-greek-physique")
	print("PASS: 11 tokens, Phenax Large, four flying chariots, carried passenger; asset captures")
	quit()
