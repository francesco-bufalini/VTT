extends SceneTree

const SCENE_PATH := "res://encounter/post_kaos_editable.scn"
const HEAD_CUTOFF_METERS := 119.8
const NECK_HALF_WIDTH_METERS := 11.5
const EXPECTED_RUINS: Array[String] = [
	"FlutedColumns",
	"Capitals",
	"RomanArches",
	"Cornices",
	"ColumnPlinths",
	"ContinuousApseWall",
]
const HAIR_TERMS: Array[String] = [
	"AnatomicalHairline",
	"RootedSilverLock",
	"PartedTempleLock",
	"HangingSilverTress",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		_fail("Cannot load %s" % SCENE_PATH)
		return
	var scene := packed.instantiate()
	if scene == null:
		_fail("Cannot instantiate post-Kaos scene.")
		return

	var script: Script = scene.get_script()
	if (
		script == null
		or script.resource_path != "res://encounter/post_kaos_scene.gd"
	):
		_fail("Post-Kaos scene is not using post_kaos_scene.gd.")
		return

	var ui := scene.get_node_or_null("UI")
	if ui == null:
		_fail("UI root is missing.")
		return
	var baked_ui_names: Array[String] = []
	for child in ui.get_children():
		baked_ui_names.append(String(child.name))
	baked_ui_names.sort()
	var expected_ui := [
		"ContextMenu",
		"Crosshair",
		"MeasurementModeLabel",
		"TokenColorDialog",
	]
	expected_ui.sort()
	if baked_ui_names != expected_ui:
		_fail("Baked scene contains runtime UI nodes: %s" % [baked_ui_names])
		return

	if scene.get_node_or_null("KaosRoot/ShoulderPlatform") != null:
		_fail("Legacy Kaos shoulder platform is still baked.")
		return
	if scene.get_node_or_null("HandPlatforms") != null:
		_fail("Legacy Klothis hand platforms are still baked.")
		return

	root.add_child(scene)
	await process_frame
	await physics_frame
	await process_frame

	if _find_kaos_token(scene) != null:
		_fail("KaosPhaseTwo token still exists.")
		return

	var kaos_visual := scene.get_node_or_null(
		"KaosRoot/ClimbingVisual"
	) as Node3D
	if kaos_visual == null or not kaos_visual.visible:
		_fail("The petrified climbing Kaos visual is missing.")
		return

	var cap := kaos_visual.get_node_or_null(
		"PetrifiedShoulderCap"
	) as MeshInstance3D
	if cap == null or not cap.visible:
		_fail("Kaos does not have a solid visible shoulder cap.")
		return

	var units: float = float(
		scene.get_node("MeasurementTool").call("meters_to_world", 1.0)
	)
	var head_triangles := _count_remaining_kaos_head_triangles(
		kaos_visual,
		units
	)
	if head_triangles != 0:
		_fail(
			"Kaos still has %d head/neck anatomy triangles."
			% head_triangles
		)
		return
	if _has_kaos_head_accessory(kaos_visual):
		_fail("Kaos still has visible head/neck accessories.")
		return

	var surfaces := _surface_collision_counts(scene)
	for required in [
		"kaos",
		"kaos_shoulders",
		"kaos_right_arm_grid",
		"klothys",
		"sphere",
	]:
		if int(surfaces.get(required, 0)) < 1:
			_fail("Missing solid post-Kaos surface: %s" % required)
			return

	var right_arm := _find_surface_body(scene, "kaos_right_arm_grid")
	if right_arm == null:
		_fail("Kaos right-arm grid proxy is missing.")
		return
	if right_arm.is_in_group("grid_3d_excluded"):
		_fail("Kaos right-arm grid proxy is incorrectly grid-excluded.")
		return
	if not _right_arm_proxy_is_on_positive_x(right_arm, units):
		_fail("Kaos right-arm grid proxy is not around the right arm.")
		return

	for node in scene.find_children("*", "StaticBody3D", true, false):
		if not bool(node.get_meta("post_kaos_collision", false)):
			continue
		var label := String(node.get_meta("post_kaos_surface", ""))
		if label == "kaos_right_arm_grid":
			continue
		if not node.is_in_group("grid_3d_excluded"):
			_fail(
				"Solid surface %s should not flood the 3D grid."
				% label
			)
			return

	var klothys_visual := scene.get_node_or_null(
		"KlothisRoot/KlothisVisual"
	) as Node3D
	var hair_count := _count_klothys_hair(klothys_visual)
	if hair_count < 100:
		_fail(
			"Klothys hair was not fully restored: %d pieces."
			% hair_count
		)
		return

	var titan_faces := scene.get_node_or_null(
		"KlothisRoot/SphereVisual/CarvedTitanFaces"
	) as MultiMeshInstance3D
	if (
		titan_faces == null
		or titan_faces.multimesh == null
		or titan_faces.multimesh.instance_count != 16
	):
		_fail("The 16 titan faces were not restored on the sphere.")
		return

	var ruins := scene.get_node_or_null("Board/MapGeometry")
	if ruins == null:
		_fail("MapGeometry is missing.")
		return
	for node_name in EXPECTED_RUINS:
		if ruins.get_node_or_null(node_name) == null:
			_fail("Encounter background element is missing: %s" % node_name)
			return

	var chariots := 0
	for child in scene.get_node("Tokens").get_children():
		if bool(child.get_meta("compound_chariot", false)):
			chariots += 1
	if chariots != 4:
		_fail("Expected 4 post-Kaos chariots, found %d." % chariots)
		return

	print(
		(
			"PASS: post-Kaos solid terrain; head triangles=%d, "
			+ "Kaos=%d, Klothys=%d, sphere=%d, hair=%d, chariots=%d"
		)
		% [
			head_triangles,
			int(surfaces.get("kaos", 0)),
			int(surfaces.get("klothys", 0)),
			int(surfaces.get("sphere", 0)),
			hair_count,
			chariots,
		]
	)

	scene.queue_free()
	packed = null
	await process_frame
	await process_frame
	quit(0)


func _find_kaos_token(scene: Node) -> Node:
	for child in scene.get_node("Tokens").get_children():
		if (
			child.name == "KaosPhaseTwo"
			or bool(child.get_meta("kaos_phase_two", false))
		):
			return child
	return null


func _surface_collision_counts(scene: Node) -> Dictionary:
	var counts: Dictionary = {}
	for node in scene.find_children("*", "StaticBody3D", true, false):
		if not bool(node.get_meta("post_kaos_collision", false)):
			continue
		var label := String(node.get_meta("post_kaos_surface", ""))
		counts[label] = int(counts.get(label, 0)) + 1
	return counts


func _find_surface_body(scene: Node, label: String) -> StaticBody3D:
	for node in scene.find_children("*", "StaticBody3D", true, false):
		if String(node.get_meta("post_kaos_surface", "")) == label:
			return node as StaticBody3D
	return null


func _count_remaining_kaos_head_triangles(
	visual: Node3D,
	units: float
) -> int:
	var count := 0
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var role := String(
			mesh_instance.get_meta("visual_role", mesh_instance.name)
		)
		if not role.begins_with("Anatomy"):
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(
				surface_index
			)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices.resize(vertices.size())
				for index in range(vertices.size()):
					indices[index] = index
			for index in range(0, indices.size() - 2, 3):
				for corner in range(3):
					var vertex := (
						mesh_instance.transform
						* vertices[indices[index + corner]]
					) / units
					if (
						vertex.y > HEAD_CUTOFF_METERS
						and absf(vertex.x) < NECK_HALF_WIDTH_METERS
					):
						count += 1
						break
	return count


func _has_kaos_head_accessory(visual: Node3D) -> bool:
	var terms := [
		"Hair",
		"Lock",
		"Crown",
		"Sclera",
		"Iris",
		"Pupil",
		"FittedGoldCollar",
		"GoldCollarRim",
	]
	for child in visual.get_children():
		if not child is MeshInstance3D or not child.visible:
			continue
		var label := String(child.get_meta("visual_role", child.name))
		for term in terms:
			if term in label:
				return true
	return false


func _right_arm_proxy_is_on_positive_x(
	body: StaticBody3D,
	units: float
) -> bool:
	var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not collision.shape is ConcavePolygonShape3D:
		return false
	var shape := collision.shape as ConcavePolygonShape3D
	var faces := shape.get_faces()
	if faces.is_empty():
		return false
	var min_x := INF
	var max_x := -INF
	for point in faces:
		min_x = minf(min_x, point.x / units)
		max_x = maxf(max_x, point.x / units)
	return min_x > 0.0 and max_x > 12.0


func _count_klothys_hair(visual: Node3D) -> int:
	if visual == null:
		return 0
	var count := 0
	for child in visual.get_children():
		if not child is MeshInstance3D:
			continue
		var label := String(child.get_meta("visual_role", child.name))
		for term in HAIR_TERMS:
			if term in label:
				count += 1
				break
	return count


func _fail(message: String) -> void:
	push_error(message)
	print("FAIL: %s" % message)
	quit(1)
