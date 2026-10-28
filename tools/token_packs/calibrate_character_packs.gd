extends SceneTree
## Recalibrate released characters from curated head landmarks, retaining the
## original bundled visual bytes. Source hashes prevent accidental double scaling.

func _initialize() -> void:
	call_deferred("run")

func arg(key: String, fallback: String = "") -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(key)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback

func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, path)
	file.store_string(text)
	file.close()

func y_bounds(node: Node3D, parent_transform := Transform3D.IDENTITY) -> Vector2:
	var transform_acc := parent_transform * node.transform
	var bounds := Vector2(INF, -INF)
	if node is MeshInstance3D and node.mesh != null:
		var box: AABB = node.get_aabb()
		for index in range(8):
			var point: Vector3 = transform_acc * box.get_endpoint(index)
			bounds.x = minf(bounds.x, point.y)
			bounds.y = maxf(bounds.y, point.y)
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := y_bounds(child, transform_acc)
			bounds.x = minf(bounds.x, child_bounds.x)
			bounds.y = maxf(bounds.y, child_bounds.y)
	return bounds

func run() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(arg("--spec", "res://scripts/data/character_miniature_heights.json")))
	var source_dir := arg("--source-dir")
	var output_dir := arg("--output-dir")
	var verifying := OS.get_cmdline_user_args().has("--verify")
	assert(not source_dir.is_empty() and not output_dir.is_empty())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	for profile: Dictionary in spec["characters"]:
		var id := String(profile["id"])
		var pack := source_dir.path_join(id + ".pck")
		if not verifying:
			assert(FileAccess.get_sha256(pack) == profile["source_sha256"], "Unexpected source pack: " + id)
		assert(ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(pack), false), pack)
		var remote := "res://remote_tokens/%s/%s" % [id, id]
		var original_visual := remote + "_visual.res"
		var raw_visual := remote + "_source_visual.res"
		var scene_path := remote + "_token.tscn"
		var source_resource := load(raw_visual if verifying else original_visual) as PackedScene
		var source := source_resource.instantiate() as Node3D
		var bounds := y_bounds(source)
		assert(is_equal_approx(bounds.x, float(profile["source_min_y"])), "Source ground changed: " + id)
		assert(is_equal_approx(bounds.y - bounds.x, float(profile["source_total_height_cells"])), "Source bounds changed: " + id)
		var target_head := float(profile["height_m"]) / float(spec["meters_per_cell"])
		var factor := target_head / float(profile["source_head_height_cells"])
		var total_height := (bounds.y - bounds.x) * factor
		var original_transform := source.transform
		var scaled_transform := Transform3D(original_transform.basis * factor, original_transform.origin * factor)
		if verifying:
			assert(FileAccess.get_sha256(raw_visual) == profile["source_visual_sha256"], "Original visual bytes changed: " + id)
			var token := (load(scene_path) as PackedScene).instantiate() as CharacterBody3D
			root.add_child(token)
			token.flying = true
			token.global_position.y = token.token_height_cells * token.cell_size * 0.5
			assert(token.get_visual_asset_path() == original_visual, "Saved visual path changed: " + id)
			assert(token.set_visual_asset(original_visual, 1.0), "Cannot restore a saved visual: " + id)
			var visual := token.get_node("Visuals/ImportedVisual") as Node3D
			assert(visual.basis.is_equal_approx(scaled_transform.basis), "Visual transform changed: " + id)
			assert(is_equal_approx(token.token_height_cells, total_height), "Runtime clamped height: " + id)
			assert(token.get_node("Visuals").scale.is_equal_approx(Vector3.ONE * token.cell_size), "Runtime clamped scale: " + id)
			var current_bounds: Vector2 = token._imported_visual_y_bounds()
			var ground_y: float = token.global_position.y + token.cell_size * (visual.position.y + current_bounds.x)
			assert(absf(ground_y) < 0.00001, "Grounding changed: " + id)
			assert(is_equal_approx(ground_y + float(profile["source_head_height_cells"]) * factor, target_head))
			var collider := token.get_node("CollisionShape3D").shape as BoxShape3D
			assert(is_equal_approx(collider.size.x, 1.0) and is_equal_approx(collider.size.z, 1.0), "Tactical footprint changed: " + id)
			token.free()
		else:
			var stage := output_dir.path_join(id)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(stage))
			source_resource.take_over_path(raw_visual)
			var wrapper := '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="PackedScene" path="%s" id="1_visual"]\n\n[node name="%s" instance=ExtResource("1_visual")]\ntransform = %s\n' % [raw_visual, String(source.name), var_to_str(scaled_transform)]
			var wrapper_path := stage.path_join(id + "_calibrated_visual.tscn")
			write_text(wrapper_path, wrapper)
			var wrapper_resource := load(wrapper_path) as PackedScene
			assert(wrapper_resource != null)
			var saved_wrapper := stage.path_join(id + "_visual.res")
			assert(ResourceSaver.save(wrapper_resource, saved_wrapper, ResourceSaver.FLAG_COMPRESS) == OK)
			var scene := FileAccess.get_file_as_string(scene_path)
			var height_pattern := RegEx.create_from_string("(?m)^token_height_cells = [^\\r\\n]+")
			assert(height_pattern.search(scene) != null, "Missing token height: " + id)
			scene = height_pattern.sub(scene, "token_height_cells = %.9f" % total_height)
			var staged_scene := stage.path_join(id + "_token.tscn")
			write_text(staged_scene, scene)
			var packer := PCKPacker.new()
			assert(packer.pck_start(ProjectSettings.globalize_path(output_dir.path_join(id + ".pck"))) == OK)
			assert(packer.add_file(raw_visual, original_visual) == OK)
			assert(packer.add_file(original_visual, ProjectSettings.globalize_path(saved_wrapper)) == OK)
			assert(packer.add_file(scene_path, ProjectSettings.globalize_path(staged_scene)) == OK)
			assert(packer.flush(true) == OK)
			profile["source_visual_sha256"] = FileAccess.get_sha256(original_visual)
		print("CHARACTER_SCALE %s head=%.3fm total=%.6f cells factor=%.6f" % [id, float(profile["height_m"]), total_height, factor])
		source.free()
	if not verifying:
		write_text(output_dir.path_join("verified_source_landmarks.json"), JSON.stringify(spec, "  ") + "\n")
	print("PASS: character pack %s" % ("verification" if verifying else "calibration"))
	quit()
