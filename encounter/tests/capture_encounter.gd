extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1440, 900)
	var scene: Node = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		if args[1] == "portrait":
			var scale_units: float = scene.measurement_tool.meters_to_world(1)
			var target: Vector3 = scene.get_node("KlothisRoot").global_position
			scene.camera.position = target + Vector3(17, 140, 53) * scale_units
			scene.camera.look_at(target + Vector3(0, 130, 0) * scale_units)
		else:
			scene._on_context_menu_id_pressed(int(args[1]))
	var klothis: Node3D = scene.get_node("KlothisRoot")
	print("Klothis group elevation: %.3f m" % scene.measurement_tool.world_to_meters(klothis.position.y))
	for visual: Node in [scene.get_node("KaosRoot/KaosVisual"), klothis.get_node("KlothisVisual")]:
		var triangles: int = 0
		for node in visual.get_children():
			if node is MeshInstance3D:
				for surface in range(node.mesh.get_surface_count()):
					var arrays: Array = node.mesh.surface_get_arrays(surface)
					triangles += arrays[Mesh.ARRAY_INDEX].size() / 3 if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size() / 3
		print("%s: %d triangles" % [visual.name, triangles])
	if args.size() > 2 and args[2] == "collapse":
		var controller: Node = scene.get_node("EncounterProgressController")
		controller.advance_encounter()
		while controller.is_advancing:
			await process_frame
	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0] if not args.is_empty() else "user://encounter.png")
	quit()
