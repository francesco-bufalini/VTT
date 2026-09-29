extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)

func run() -> void:
	var scene: Node3D = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame
	var progress: Node = scene.encounter
	var seals: Node = progress.seals
	var broken: Array[int] = []
	seals.seal_broken.connect(func(index: int): broken.append(index))
	progress.register_seal_damage(0,99)
	check(broken.is_empty(),"seal intact below threshold")
	progress.register_seal_damage(0,1)
	progress.register_seal_damage(0,1000)
	check(broken == [0] and seals.damage[0] == 100,"seal breaks exactly once")
	progress.register_seal_damage(1,25)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(progress.get_save_state()))
	progress.reset_encounter(42)
	check(seals.damage == [0.0,0.0,0.0],"reset seals")
	check(progress.load_state(saved),"reload seals accepted")
	check(seals.damage == [100.0,25.0,0.0],"reload exact seal state")
	check(not seals._visuals[0].visible,"broken seal stays hidden on reload")
	var invalid := saved.duplicate(true)
	invalid.threatened_cells = 9
	check(not progress.load_state(invalid),"malformed cell collection rejected")
	saved.erase("seal_damage")
	check(progress.load_state(saved),"old save compatibility")
	var token: CharacterBody3D = scene.tokens_root.get_child(0)
	token.set_flying(true)
	token.global_position = Vector3(10.5,10,30.5)
	scene._replace_selection(token)
	scene.token_drag.begin(scene._selected_tokens,token)
	check(scene.token_drag.preview_at(Vector3(15.8,10,35.2)),"valid flight drag preview")
	check(token.position == Vector3(10.5,10,30.5),"preview does not mutate position")
	scene.token_drag.finish(true)
	check(token.position == Vector3(15.5,10,35.5),"drag commits snapped position and altitude")
	scene.token_drag.begin(scene._selected_tokens,token)
	scene.token_drag.preview_at(Vector3(20.5,10,40.5))
	scene.token_drag.finish(false)
	check(token.position == Vector3(15.5,10,35.5),"cancel preserves position")
	token.set_flying(false)
	token.position = Vector3(10.5,1.001,30.5)
	progress.hazards._collapsed[Vector2i(15,35)] = true
	scene.token_drag.begin(scene._selected_tokens,token)
	check(not scene.token_drag.preview_at(Vector3(15.5,1.001,35.5)),"collapsed target rejected")
	scene.token_drag.finish(true)
	check(token.position == Vector3(10.5,1.001,30.5),"invalid drop is atomic")
	var units: float = scene.measurement_tool.meters_to_world(1)
	check(is_equal_approx(scene.get_node("KlothisRoot/SphereVisual").global_position.y/units,385),"sphere lifted another 150m")
	var visual: Node3D = scene.get_node("KlothisRoot/KlothisVisual")
	check(is_equal_approx(visual.get_node("LeftWristSealAnchor").position.y,visual.get_node("RightWristSealAnchor").position.y),"wrists at equal T-pose height")
	scene.free()
	var base: Node3D = load("res://dnd_base.tscn").instantiate()
	root.add_child(base)
	var mouse_token: CharacterBody3D = base.token_scene.instantiate()
	base.tokens_root.add_child(mouse_token)
	mouse_token.configure(Color.WHITE,base.cell_size,"Medium",1.0)
	mouse_token.position = Vector3(2.5,1.001,2.5)
	base.camera.position = Vector3(0,20,25)
	base.camera.look_at(mouse_token.position)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await physics_frame
	await physics_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = base.camera.unproject_position(mouse_token.position)
	base._unhandled_input(press)
	check(base.token_drag.active,"mouse press starts drag in dnd_base")
	var motion := InputEventMouseMotion.new()
	motion.position = base.camera.unproject_position(Vector3(7.5,0,6.5))
	base._input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	base._input(release)
	check(not base.token_drag.active,"mouse release ends drag")
	check(absf(mouse_token.position.x-7.5)<0.01 and absf(mouse_token.position.z-6.5)<0.01,"mouse ray drag commits destination")
	base.free()
	print("Drag/seal checks: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
