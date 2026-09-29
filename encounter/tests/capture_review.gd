extends SceneTree
var scene: Node3D
var output: String

func _initialize() -> void:
	call_deferred("run")

func shot(label: String) -> void:
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output.path_join(label+".png"))
	assert(error == OK)

func run() -> void:
	root.size = Vector2i(1600,1000)
	output = OS.get_cmdline_user_args()[0]
	scene = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await shot("overview")
	var units: float = scene.measurement_tool.meters_to_world(1)
	scene.get_node("UI").visible = false
	var visual: Node3D = scene.get_node("KaosRoot/KaosVisual")
	scene.camera.position = visual.global_position + Vector3(35,117,-90)*units
	scene.camera.look_at(visual.global_position+Vector3(0,112,0)*units)
	await shot("kaos-close")
	visual = scene.get_node("KlothisRoot/KlothisVisual")
	scene.camera.position = visual.global_position + Vector3(20,130,105)*units
	scene.camera.look_at(visual.global_position+Vector3(0,110,-14)*units)
	await shot("klothis-close")
	scene.get_node("UI").visible = true
	scene._on_context_menu_id_pressed(102)
	var token: CharacterBody3D = scene.tokens_root.get_child(0)
	scene._replace_selection(token)
	scene.token_drag.begin(scene._selected_tokens,token)
	scene.token_drag.preview_at(token.global_position+Vector3(4,0,3))
	await shot("grid-selection")
	scene.token_drag.finish(false)
	scene.encounter.advance_encounter()
	while scene.encounter.is_advancing:
		await process_frame
	await shot("round-one")
	scene._on_context_menu_id_pressed(101)
	await shot("shoulder-grid")
	scene.get_node("UI").visible = false
	visual = scene.get_node("KlothisRoot/KlothisVisual")
	scene.camera.position = visual.global_position + Vector3(20,130,105)*units
	scene.camera.look_at(visual.global_position+Vector3(0,110,-14)*units)
	scene.encounter.register_seal_damage(0,100)
	await create_timer(0.18).timeout
	await shot("seal-break")
	await scene.get_node("UI/EncounterUI")._export_view(output.path_join("render-2560.png"),false)
	var rendered := Image.load_from_file(output.path_join("render-2560.png"))
	assert(rendered != null and rendered.get_size() == Vector2i(2560,1440))
	print("Rendered overview, both characters, selection, round, shoulder grid and seal break")
	quit()
