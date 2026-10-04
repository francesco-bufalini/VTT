extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func centroid(points: PackedVector3Array) -> Vector3:
	var result := Vector3.ZERO
	for point in points:result += point
	return result / float(points.size())
func ray(scene: Node3D, point: Vector3, mask: int = 1) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*3.0, point-Vector3.UP*5.0, mask)
	query.hit_back_faces = true
	return scene.get_world_3d().direct_space_state.intersect_ray(query)
func finish_attack(prison: Node3D) -> void:
	prison.player.advance(0.4)
	prison._process(0.0)
	prison.player.advance(1.1)
func run() -> void:
	var scene: Node3D = load("res://encounter/scontro_contro_kaos.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	var prison: Node3D = scene.klotis_prison
	check(prison != null, "Imported prison missing")
	check(prison._clips.size()==3, "Three animation commands required")
	var units: float = scene.measurement_tool.meters_to_world(1.0)
	for side: String in ["left", "right"]:
		var metrics: Dictionary = prison._sealed_hand_metrics(side)
		check(float(metrics.min_radius) / units >= 220.0, "Sealed hand or fingers penetrate rock: " + side)
	var hair: MeshInstance3D = prison.model.find_child("Klotis_Golden_Hair_Cap_V5", true, false)
	var hair_center: Vector3 = centroid(prison._posed_vertices(hair))
	var head_bone: int = prison.skeleton.find_bone("head")
	var head_initial: Transform3D = prison.skeleton.global_transform * prison.skeleton.get_bone_global_pose(head_bone)
	var hair_local: Vector3 = head_initial.affine_inverse() * hair_center
	for clip in prison._clips.values():
		check(absf(prison.player.get_animation(clip).length-1.4)<0.001, "Animation must end at frame 42")
	var plates: MeshInstance3D = prison.model.find_child("Earth_Hexagonal_Stone_Plates",true,false)
	var orb: AABB = plates.global_transform * plates.get_aabb()
	check(absf(orb.size.y-prison.baseline_dimensions.sphere_diameter)<0.01, "Sphere diameter changed")
	var goddess: MeshInstance3D = prison.model.find_child("Klotis_Body_V5",true,false)
	var goddess_bounds: AABB = prison._bounds(prison._posed_vertices(goddess))
	check(absf(goddess_bounds.size.y-prison.baseline_dimensions.goddess_height)<0.01, "Goddess height changed")
	var statue: MeshInstance3D = prison.model.find_child("Empyrean_Headless_Petrified",true,false)
	var statue_bounds: AABB = statue.global_transform*statue.get_aabb()
	check(absf(statue_bounds.size.y-prison.baseline_dimensions.statue_height)<0.01, "Statue height changed")
	check(prison.find_children("*", "StaticBody3D", true, false).size()>=15, "Solid map surfaces missing")
	check(not scene.get_node("KlothisRoot/KlothisVisual").visible, "Legacy goddess visible")
	check(not scene.get_node("KaosRoot/ClimbingVisual").visible, "Legacy Kaos visible")
	check(not ray(scene,prison.statue_top).is_empty(), "Neck is not solid")
	check(not ray(scene,prison.statue_top,8).is_empty(), "Neck missing on grid layer")
	scene.camera.global_position = prison.statue_top + Vector3(12,19,27)
	scene.camera.look_at(prison.statue_top)
	scene.set_grid_visible(true)
	await physics_frame
	scene.volumetric_grid._capture_volume_transform()
	var top: float = scene.volumetric_grid.get_support_top_y(prison.statue_top,prison.statue_top.y+2,prison.statue_top.y-2)
	check(top < INF and top >= prison.statue_top.y, "Grid has no support voxel above the neck")
	print("NECK_SUPPORT:",top," SOLID_NECK:",prison.statue_top.y)
	check(scene.avvia_animazione_sigillo("sinistro"), "Left command failed")
	prison.player.pause()
	prison.skeleton.force_update_all_bone_transforms()
	var starting_hand: Dictionary = prison._sealed_hand_metrics("left")
	check(float(starting_hand.min_radius) / units >= 220.0, "Left animation snaps hand back into rock at start")
	finish_attack(prison)
	await physics_frame
	var left_palm: Vector3 = prison._palm_center("left")
	check(prison._completed.has("left"), "Left animation did not finish")
	check(not prison._seals.left.visible, "Left seal did not shatter")
	check(not ray(scene,left_palm).is_empty(), "Left hand is not solid")
	check(not ray(scene,left_palm,8).is_empty(), "Left hand missing on grid layer")
	var left_pose: Transform3D = prison.skeleton.get_bone_global_pose(prison.skeleton.find_bone("hand.l"))
	check(scene.avvia_animazione_sigillo("destro"), "Right command failed")
	finish_attack(prison)
	await physics_frame
	check(prison._completed.has("right"), "Right animation did not finish")
	check(prison.skeleton.get_bone_global_pose(prison.skeleton.find_bone("hand.l")).is_equal_approx(left_pose), "Second attack reset the freed left hand")
	var right_palm: Vector3 = prison._palm_center("right")
	check(not ray(scene,right_palm).is_empty(), "Right hand is not solid")
	var left_bottom: float = prison._sealed_hand_metrics("left").min_y
	var right_bottom: float = prison._sealed_hand_metrics("right").min_y
	check(left_bottom >= prison.statue_top.y - 0.02 and right_bottom >= prison.statue_top.y - 0.02, "Freed hand or fingers intersect the neck rock")
	check(minf(left_bottom, right_bottom) - prison.statue_top.y < 0.5, "Hands no longer contact the platform")
	check(scene.avvia_animazione_sigillo("fronte"), "Forehead command failed")
	finish_attack(prison)
	await physics_frame
	check(prison._completed.has("forehead"), "Forehead animation did not finish")
	check(not prison._seals.forehead.visible, "Forehead seal did not shatter")
	var head_final: Transform3D = prison.skeleton.global_transform * prison.skeleton.get_bone_global_pose(head_bone)
	var hair_final: Vector3 = centroid(prison._posed_vertices(hair))
	check(hair_final.distance_to(head_final * hair_local) < 0.02, "Scalp hair did not follow the head bow")
	check(scene.encounter.encounter_finished, "Three seals did not end combat")
	var chariot: CharacterBody3D = scene.tokens_root.get_child(0)
	scene.camera.enter_first_person(chariot)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	scene._unhandled_input(esc)
	check(not scene.camera.is_first_person(), "Escape blocked after third seal")
	check(not scene.avvia_animazione_sigillo("sinistro"), "Broken seal can fire twice")
	scene.encounter.reset_encounter(7)
	await process_frame
	check(prison._completed.is_empty() and prison._active_side.is_empty(), "Reset did not restore animations")
	check(prison.broken.values().all(func(v: bool):return not v), "Reset did not restore seals")
	check(not scene.get_node("KaosRoot/ClimbingVisual").visible, "Reset showed replaced Kaos")
	for order: Array in [["forehead", "right", "left"], ["right", "left", "forehead"]]:
		scene.encounter.reset_encounter(7)
		for side: String in order:
			check(scene.avvia_animazione_sigillo(side), "Queued seal command failed: " + side)
		for attack in range(3):
			prison.player.pause()
			finish_attack(prison)
		check(prison._completed.size() == 3 and prison._pending.is_empty(), "Queued animations did not complete in order")
		check(prison._completed == order, "Queue reordered seal animations")
	print("IMPORT_METRICS:",JSON.stringify({"sphere_diameter":orb.size.y,"goddess_height":goddess_bounds.size.y,"statue_height":statue_bounds.size.y,"neck":prison.statue_top,"left_palm":left_palm,"right_palm":right_palm,"solid_surfaces":prison.find_children("*","StaticBody3D",true,false).size()}))
	scene.free()
	if failures.is_empty():
		print("PASS: Klotis prison import, dimensions, three animations, persistent freed hands and solid grid surfaces")
	quit(0 if failures.is_empty() else 1)
