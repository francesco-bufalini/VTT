extends SceneTree

const MANIFEST_PATH := "res://assets/tokens/token_library.json"
const BUILD_ROOT := "res://.token_pack_build"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var token_id := _arg_value(args, "--token-id", "ape").strip_edges()
	var output_path := _arg_value(
		args,
		"--output",
		"res://dist/token_packs/%s.pck" % token_id
	).strip_edges()

	var result := _build_pack(token_id, output_path)
	if result != OK:
		push_error("Token pack build failed: %s" % error_string(result))
		quit(1)
		return
	quit(0)


func _arg_value(args: PackedStringArray, key: String, fallback: String) -> String:
	var index := args.find(key)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return fallback


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing JSON file: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open JSON file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed as Dictionary
	push_error("Invalid JSON object: %s" % path)
	return {}


func _find_profile(token_id: String) -> Dictionary:
	var manifest := _read_json(MANIFEST_PATH)
	var tokens: Variant = manifest.get("tokens", [])
	if not tokens is Array:
		return {}
	for value: Variant in tokens:
		if value is Dictionary:
			var profile := value as Dictionary
			if String(profile.get("id", "")) == token_id:
				return profile.duplicate(true)
	return {}


func _profile_visual_path(profile: Dictionary) -> String:
	var path := String(profile.get("visual_asset", "")).strip_edges()
	if path.is_empty():
		path = String(profile.get("obj", "")).strip_edges()
	return path

func _resolve_imported_resource_path(source_path: String) -> String:
	# Editor-imported source formats such as OBJ/GLB are represented at runtime
	# by a generated resource referenced from <source>.import.
	var import_file := source_path + ".import"
	var import_absolute := ProjectSettings.globalize_path(import_file)
	if not FileAccess.file_exists(import_absolute):
		return ""

	var config := ConfigFile.new()
	var load_error := config.load(import_file)
	if load_error != OK:
		push_error(
			"Could not read Godot import metadata: %s (%s)"
			% [import_file, error_string(load_error)]
		)
		return ""

	var remap_path := String(config.get_value("remap", "path", "")).strip_edges()
	if remap_path.is_empty():
		return ""
	return remap_path



func _resolve_obj_index(raw_index: int, count: int) -> int:
	if raw_index > 0:
		return raw_index - 1
	if raw_index < 0:
		return count + raw_index
	return -1


func _load_obj_runtime(source_path: String) -> ArrayMesh:
	var absolute := ProjectSettings.globalize_path(source_path)
	var file := FileAccess.open(absolute, FileAccess.READ)
	if file == null:
		push_error("Cannot open OBJ file: %s" % absolute)
		return null

	var positions := PackedVector3Array()
	var texcoords := PackedVector2Array()
	var normals := PackedVector3Array()
	var triangles: Array[PackedStringArray] = []

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts := line.split(" ", false)
		if parts.is_empty():
			continue
		match parts[0]:
			"v":
				if parts.size() >= 4:
					positions.append(Vector3(
						float(parts[1]),
						float(parts[2]),
						float(parts[3])
					))
			"vt":
				if parts.size() >= 3:
					texcoords.append(Vector2(
						float(parts[1]),
						1.0 - float(parts[2])
					))
			"vn":
				if parts.size() >= 4:
					normals.append(Vector3(
						float(parts[1]),
						float(parts[2]),
						float(parts[3])
					).normalized())
			"f":
				if parts.size() >= 4:
					var face := PackedStringArray()
					for i in range(1, parts.size()):
						face.append(parts[i])
					# OBJ polygons are fan-triangulated. Reverse the triangle order
					# for Godot's clockwise front-face convention.
					for i in range(2, face.size()):
						triangles.append(PackedStringArray([
							face[0],
							face[i],
							face[i - 1],
						]))
	file.close()

	if positions.is_empty() or triangles.is_empty():
		push_error(
			"OBJ has no usable geometry: %s (vertices=%d triangles=%d)"
			% [source_path, positions.size(), triangles.size()]
		)
		return null

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var supplied_normals := not normals.is_empty()

	for triangle: PackedStringArray in triangles:
		for vertex_ref: String in triangle:
			var refs := vertex_ref.split("/", true)
			if refs.is_empty() or refs[0].is_empty():
				push_error("Invalid OBJ face vertex: %s" % vertex_ref)
				return null

			var position_index := _resolve_obj_index(int(refs[0]), positions.size())
			if position_index < 0 or position_index >= positions.size():
				push_error("OBJ position index out of range: %s" % vertex_ref)
				return null

			if refs.size() >= 2 and not refs[1].is_empty():
				var uv_index := _resolve_obj_index(int(refs[1]), texcoords.size())
				if uv_index >= 0 and uv_index < texcoords.size():
					surface.set_uv(texcoords[uv_index])

			if refs.size() >= 3 and not refs[2].is_empty():
				var normal_index := _resolve_obj_index(int(refs[2]), normals.size())
				if normal_index >= 0 and normal_index < normals.size():
					surface.set_normal(normals[normal_index])

			surface.add_vertex(positions[position_index])

	if not supplied_normals:
		surface.generate_normals()

	var mesh := surface.commit()
	if mesh == null:
		push_error("SurfaceTool could not commit OBJ mesh: %s" % source_path)
		return null

	print(
		"TOKEN_PACK_STAGE obj_runtime vertices=%d triangles=%d surfaces=%d"
		% [positions.size(), triangles.size(), mesh.get_surface_count()]
	)
	return mesh


func _load_glb_runtime(source_path: String) -> PackedScene:
	var absolute := ProjectSettings.globalize_path(source_path)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED

	var import_error := document.append_from_file(
		absolute,
		state,
		GLTFDocument.IMPORT_FLAG_GENERATE_TANGENT_ARRAYS
	)
	if import_error != OK:
		push_error(
			"GLB runtime import failed: %s (%s)"
			% [source_path, error_string(import_error)]
		)
		return null

	var scene_root := document.generate_scene(state)
	if scene_root == null:
		push_error("GLB runtime import generated no scene: %s" % source_path)
		return null

	var packed := PackedScene.new()
	var pack_error := packed.pack(scene_root)
	if pack_error != OK:
		push_error(
			"Could not pack GLB runtime scene: %s (%s)"
			% [source_path, error_string(pack_error)]
		)
		scene_root.free()
		return null

	var skeleton_count := scene_root.find_children("*", "Skeleton3D", true, false).size()
	var animation_player_count := scene_root.find_children(
		"*",
		"AnimationPlayer",
		true,
		false
	).size()
	print(
		"TOKEN_PACK_STAGE glb_runtime skeletons=%d animation_players=%d"
		% [skeleton_count, animation_player_count]
	)
	scene_root.free()
	return packed


func _write_text(path: String, content: String) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	var parent := absolute.get_base_dir()
	var mkdir_error := DirAccess.make_dir_recursive_absolute(parent)
	if mkdir_error != OK:
		return mkdir_error
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content)
	var error := file.get_error()
	file.close()
	return error


func _build_pack(token_id: String, output_path: String) -> Error:
	print("TOKEN_PACK_STAGE profile id=%s" % token_id)
	var profile := _find_profile(token_id)
	if profile.is_empty():
		push_error("Token id not found in manifest: %s" % token_id)
		return ERR_DOES_NOT_EXIST

	var source_path := _profile_visual_path(profile)
	if source_path.is_empty():
		push_error("Token has no visual asset: %s" % token_id)
		return ERR_INVALID_DATA
	var source_absolute := ProjectSettings.globalize_path(source_path)
	if not FileAccess.file_exists(source_absolute):
		push_error(
			("Converted local asset is missing on disk: %s. "
			+ "Run tools/import_tokens.ps1 first.") % source_absolute
		)
		return ERR_FILE_NOT_FOUND

	print("TOKEN_PACK_STAGE load source=%s" % source_path)
	print("TOKEN_PACK_STAGE loader_exists=%s" % str(ResourceLoader.exists(source_path)))

	var source_resource: Resource = null
	var source_extension := source_path.get_extension().to_lower()
	if source_extension == "obj":
		print("TOKEN_PACK_STAGE obj_runtime_loader")
		source_resource = _load_obj_runtime(source_path)
	elif source_extension == "glb" or source_extension == "gltf":
		print("TOKEN_PACK_STAGE glb_runtime_loader")
		source_resource = _load_glb_runtime(source_path)
	else:
		var load_path := source_path
		if not ResourceLoader.exists(load_path):
			var imported_path := _resolve_imported_resource_path(source_path)
			if imported_path.is_empty():
				push_error(
					("Godot import metadata is missing or has no remap path for: %s. "
					+ "Expected metadata: %s.import")
					% [source_path, source_path]
				)
				return ERR_CANT_OPEN
			load_path = imported_path
			print("TOKEN_PACK_STAGE imported_resource=%s" % load_path)

		if not ResourceLoader.exists(load_path):
			push_error(
				"Godot imported resource does not exist/load: %s (from %s)"
				% [load_path, source_path]
			)
			return ERR_CANT_OPEN

		source_resource = ResourceLoader.load(
			load_path,
			"",
			ResourceLoader.CACHE_MODE_IGNORE
		)

	if source_resource == null:
		push_error("Godot could not build/load token resource: %s" % source_path)
		return ERR_CANT_OPEN
	if not (source_resource is Mesh or source_resource is PackedScene):
		push_error(
			"Unsupported converted resource type for %s: %s"
			% [token_id, source_resource.get_class()]
		)
		return ERR_UNAVAILABLE

	var build_dir := "%s/%s" % [BUILD_ROOT, token_id]
	var build_dir_absolute := ProjectSettings.globalize_path(build_dir)
	var build_dir_error := DirAccess.make_dir_recursive_absolute(build_dir_absolute)
	if build_dir_error != OK:
		push_error(
			"Could not create token build directory: %s (%s)"
			% [build_dir_absolute, error_string(build_dir_error)]
		)
		return build_dir_error

	var saved_visual := "%s/%s_visual.res" % [build_dir, token_id]
	print("TOKEN_PACK_STAGE serialize class=%s target=%s" % [source_resource.get_class(), saved_visual])
	var save_error := ResourceSaver.save(source_resource, saved_visual)
	if save_error != OK:
		push_error("Could not serialize token resource: %s" % error_string(save_error))
		return save_error

	var remote_root := "res://remote_tokens/%s" % token_id
	var remote_visual := "%s/%s_visual.res" % [remote_root, token_id]
	var remote_scene := "%s/%s_token.tscn" % [remote_root, token_id]
	var staged_scene := "%s/%s_token.tscn" % [build_dir, token_id]

	var display_name := String(profile.get("name", token_id))
	var size_name := String(profile.get("size_name", "Medium"))
	var footprint := maxf(float(profile.get("footprint", 1.0)), 0.5)
	var height_cells := maxf(float(profile.get("height_cells", 2.0)), 0.1)

	var scene_text := (
		'[gd_scene load_steps=2 format=3]\n\n'
		+ '[ext_resource type="PackedScene" path="res://token.tscn" id="1_base"]\n\n'
		+ '[node name="%s_token" instance=ExtResource("1_base")]\n' % token_id
		+ 'visual_asset_path = "%s"\n' % remote_visual
		+ 'visual_native_footprint_cells = %.6f\n' % footprint
		+ 'token_display_name = "%s"\n' % display_name.replace('"', '\\"')
		+ 'default_size_name = "%s"\n' % size_name.replace('"', '\\"')
		+ 'default_footprint_cells = %.6f\n' % footprint
		+ 'token_height_cells = %.6f\n' % height_cells
	)
	var scene_error := _write_text(staged_scene, scene_text)
	if scene_error != OK:
		return scene_error

	var output_absolute := ProjectSettings.globalize_path(output_path)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(
		output_absolute.get_base_dir()
	)
	if mkdir_error != OK:
		return mkdir_error
	if FileAccess.file_exists(output_absolute):
		DirAccess.remove_absolute(output_absolute)

	print("TOKEN_PACK_STAGE pck_start output=%s" % output_absolute)
	var packer := PCKPacker.new()
	var start_error := packer.pck_start(output_absolute)
	if start_error != OK:
		return start_error

	print("TOKEN_PACK_STAGE add visual=%s" % remote_visual)
	var add_visual_error := packer.add_file(
		remote_visual,
		ProjectSettings.globalize_path(saved_visual)
	)
	if add_visual_error != OK:
		return add_visual_error

	print("TOKEN_PACK_STAGE add scene=%s" % remote_scene)
	var add_scene_error := packer.add_file(
		remote_scene,
		ProjectSettings.globalize_path(staged_scene)
	)
	if add_scene_error != OK:
		return add_scene_error

	print("TOKEN_PACK_STAGE flush")
	var flush_error := packer.flush(true)
	if flush_error != OK:
		return flush_error

	print("TOKEN_PACK_OK id=%s pck=%s scene=%s" % [
		token_id,
		output_path,
		remote_scene
	])
	return OK
