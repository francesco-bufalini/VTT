extends SceneTree

const SCENE_PATH := "res://encounter/scontro_contro_kaos.tscn"
const HEAD_CENTER_METERS := Vector3(0.0, 136.0, 0.0)
const HEAD_RADIUS_METERS := 17.5
const UPPER_NECK_BOTTOM_METERS := 121.5
const UPPER_NECK_TOP_METERS := 130.0
const UPPER_NECK_RADIUS_X_METERS := 12.5
const UPPER_NECK_RADIUS_Z_METERS := 11.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		_fail("Cannot load Scontro contro Kaos.")
		return
	var scene := packed.instantiate() as Node3D
	if scene == null:
		_fail("Cannot instantiate Scontro contro Kaos.")
		return

	root.add_child(scene)
	await process_frame
	await physics_frame
	await process_frame
	await physics_frame

	var progress := scene.get_node_or_null("EncounterProgressController")
	if progress == null:
		_fail("EncounterProgressController is missing.")
		return
	if int(progress.get("encounter_phase")) != 2:
		_fail("Scontro did not start directly in phase 2.")
		return
	if int(progress.get("kaos_step")) != 0:
		_fail("Scontro did not start with Kaos already at the sphere.")
		return

	var visual := scene.get_node_or_null(
		"KaosRoot/ClimbingVisual"
	) as Node3D
	if visual == null or not visual.visible:
		_fail("Phase-2 climbing Kaos visual is missing.")
		return

	var units: float = float(
		scene.get_node("MeasurementTool").call("meters_to_world", 1.0)
	)
	var head_triangles := _count_head_and_upper_neck_triangles(
		visual,
		units
	)
	if head_triangles != 0:
		_fail(
			"Kaos still has %d head/upper-neck anatomy triangles."
			% head_triangles
		)
		return

	var shoulders := visual.get_node_or_null(
		"PetrifiedShoulderCap"
	) as MeshInstance3D
	var neck_base := visual.get_node_or_null(
		"PetrifiedNeckBase"
	) as MeshInstance3D
	if shoulders == null or not shoulders.visible:
		_fail("Opaque Kaos shoulder fill is missing.")
		return
	if neck_base == null or not neck_base.visible:
		_fail("Solid base-of-neck stump is missing.")
		return
	if not shoulders.material_override is ShaderMaterial:
		_fail("Kaos shoulder fill is not opaque stone material.")
		return
	if not neck_base.material_override is ShaderMaterial:
		_fail("Kaos neck base is not opaque stone material.")
		return

	var neck_mesh := neck_base.mesh as CylinderMesh
	if (
		neck_mesh == null
		or neck_mesh.height / units < 7.5
		or neck_mesh.bottom_radius / units < 10.5
	):
		_fail("Kaos base-of-neck solid terrain is undersized.")
		return

	var legacy := scene.get_node_or_null(
		"KaosRoot/ShoulderPlatform"
	) as CollisionObject3D
	if legacy == null:
		_fail("Controller-compatible ShoulderPlatform node is missing.")
		return
	if legacy.collision_layer != 0 or legacy.collision_mask != 0:
		_fail("Legacy invisible ShoulderPlatform is still physical terrain.")
		return
	for child in legacy.find_children("*", "CollisionShape3D", true, false):
		var shape := child as CollisionShape3D
		if shape != null and not shape.disabled:
			_fail("A legacy shoulder platform collider is still enabled.")
			return

	var surfaces := _surface_counts(scene)
	for label in [
		"kaos",
		"kaos_shoulders",
		"kaos_neck_base",
		"kaos_right_arm_grid",
		"klothys",
		"sphere",
	]:
		if int(surfaces.get(label, 0)) < 1:
			_fail("Missing imported Post-Kaos solid surface: %s" % label)
			return

	var grid := scene.get_node_or_null("VolumetricGrid")
	if grid == null or int(grid.get("collision_mask")) != 8:
		_fail("Scontro grid is not restricted to Kaos' right-arm proxy.")
		return

	if scene.get_node_or_null("HandPlatforms") != null:
		_fail("Legacy Klothys hand platforms are still present.")
		return

	if scene.get_node_or_null(
		"KlothisRoot/SphereVisual/CarvedTitanFaces"
	) == null:
		_fail("Titan faces disappeared from the Scontro sphere.")
		return
	if scene.get_node_or_null("Board/MapGeometry/FlutedColumns") == null:
		_fail("Background columns disappeared from Scontro.")
		return

	var cosmic_backdrop := scene.get_node_or_null(
		"CosmicBackdrop/StarfieldRing"
	) as MeshInstance3D
	if cosmic_backdrop == null or not cosmic_backdrop.visible:
		_fail("The seamless 360-degree cosmic backdrop is missing.")
		return

	var old_apse := scene.get_node_or_null(
		"Board/MapGeometry/ContinuousApseWall"
	) as VisualInstance3D
	if old_apse != null and old_apse.visible:
		_fail("The old partial black apse wall is still visible.")
		return

	var world_environment := scene.get_node_or_null(
		"WorldEnvironment"
	) as WorldEnvironment
	if (
		world_environment == null
		or world_environment.environment == null
		or world_environment.environment.background_mode
			!= Environment.BG_SKY
		or world_environment.environment.sky == null
	):
		_fail("Scontro does not use the starry sky environment.")
		return

	# Regression: terrain processing freezes/removes some ClimbingVisual
	# meshes. Restoring phase two again must not address stale MeshInstance3D
	# references or blend-shape tracks that no longer exist.
	var kaos_controller := scene.get_node_or_null("KaosRoot")
	if kaos_controller == null:
		_fail("KaosRoot is missing.")
		return
	var climb: Variant = kaos_controller.get("climb")
	if climb == null:
		_fail("Kaos climb controller is missing.")
		return
	climb.call("restore_phase_two")
	climb.call("restore_phase_two")
	await process_frame

	# Regression: VolumetricGrid must tolerate a CollisionShape3D that is
	# created and destroyed before its deferred registration runs.
	var temporary_body := StaticBody3D.new()
	temporary_body.name = "DeferredCollisionRegressionBody"
	temporary_body.collision_layer = 1
	scene.add_child(temporary_body)
	var temporary_collision := CollisionShape3D.new()
	temporary_collision.name = "DeferredCollisionRegressionShape"
	var temporary_shape := BoxShape3D.new()
	temporary_shape.size = Vector3.ONE * scene.get("cell_size")
	temporary_collision.shape = temporary_shape
	temporary_body.add_child(temporary_collision)
	temporary_body.queue_free()
	await process_frame
	await process_frame

	var chariots := 0
	var farthest_chariot_meters := 0.0
	var kaos_root := scene.get_node("KaosRoot") as Node3D
	for child in scene.get_node("Tokens").get_children():
		if not bool(child.get_meta("compound_chariot", false)):
			continue
		chariots += 1
		var body := child as CharacterBody3D
		if body != null:
			farthest_chariot_meters = maxf(
				farthest_chariot_meters,
				body.global_position.distance_to(kaos_root.global_position)
					/ units
			)
	if chariots != 4:
		_fail("Expected 4 chariots near Kaos, found %d." % chariots)
		return
	if farthest_chariot_meters > 90.0:
		_fail(
			"A Scontro chariot is still too far from Kaos: %.1f m."
			% farthest_chariot_meters
		)
		return

	print(
		(
			"PASS: Scontro contro Kaos phase2 terrain; "
			+ "head=%d, surfaces=%s, chariots=%d, farthest=%.1fm"
		)
		% [head_triangles, surfaces, chariots, farthest_chariot_meters]
	)

	scene.queue_free()
	packed = null
	await process_frame
	await process_frame
	quit(0)


func _surface_counts(scene: Node) -> Dictionary:
	var counts: Dictionary = {}
	for node in scene.find_children("*", "StaticBody3D", true, false):
		if not bool(node.get_meta("post_kaos_collision", false)):
			continue
		var label := String(node.get_meta("post_kaos_surface", ""))
		counts[label] = int(counts.get(label, 0)) + 1
	return counts


func _count_head_and_upper_neck_triangles(
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
					var point := (
						mesh_instance.transform
						* vertices[indices[index + corner]]
					) / units
					if _is_removed_region(point):
						count += 1
						break
	return count


func _is_removed_region(point: Vector3) -> bool:
	if point.distance_to(HEAD_CENTER_METERS) <= HEAD_RADIUS_METERS:
		return true
	if (
		point.y >= UPPER_NECK_BOTTOM_METERS
		and point.y <= UPPER_NECK_TOP_METERS
	):
		var nx := point.x / UPPER_NECK_RADIUS_X_METERS
		var nz := point.z / UPPER_NECK_RADIUS_Z_METERS
		return nx * nx + nz * nz <= 1.0
	return false


func _fail(message: String) -> void:
	push_error(message)
	print("FAIL: %s" % message)
	quit(1)
