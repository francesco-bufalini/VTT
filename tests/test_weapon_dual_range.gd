extends SceneTree

const AttackSystem = preload("res://vtt/attack_system.gd")
const RangeGeometry = preload("res://vtt/attack_range_geometry.gd")
const RangeOverlay2D = preload("res://vtt/attack_range_overlay_2d.gd")
const AttackData = preload("res://vtt/creature_attack_data.gd")


class Board:
	extends Node3D

	var cell_size: float = 1.0
	var use_2d: bool = false

	func is_2d_view_enabled() -> bool:
		return use_2d


func _fail(reason: String) -> void:
	push_error("Dual weapon ranges: " + reason)
	quit(1)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var limits: Vector2 = AttackSystem.ranged_limits({
		"melee": false, "range_feet": 80, "long_range_feet": 320
	})
	if limits != Vector2(80.0, 320.0):
		_fail("structured ranged weapon did not preserve 80/320 ft")
		return
	if AttackSystem.ranged_limits({"range_feet": 30, "long_range_feet": 30}).y != 0.0:
		_fail("equal ranges should draw only one circle")
		return
	if AttackSystem.ranged_limits({"melee": true, "range_feet": 10, "long_range_feet": 100}).y != 0.0:
		_fail("melee attack showed an invalid long-range circle")
		return

	var small: PackedVector2Array = RangeGeometry.rounded_footprint_perimeter(0.5, 6.0)
	var large: PackedVector2Array = RangeGeometry.rounded_footprint_perimeter(0.5, 24.0)
	if small.size() != large.size() or small.size() < 60:
		_fail("concentric contours have inconsistent resolution")
		return
	if not is_equal_approx(small[0].x, 6.5) or not is_equal_approx(large[0].x, 24.5):
		_fail("weapon reach does not start from footprint edge")
		return
	for index: int in range(small.size()):
		if large[index].length_squared() < small[index].length_squared():
			_fail("long-range contour crossed inside the normal contour")
			return

	var board := Board.new()
	root.add_child(board)
	var attacker := CharacterBody3D.new()
	attacker.name = "Archer"
	board.add_child(attacker)

	var attack := AttackSystem.new()
	board.add_child(attack)
	attack.set("board_root", board)
	attack.set("_attacker", attacker)
	attack.set("_range_normal_feet", 80.0)
	attack.set("_range_long_feet", 320.0)
	attack.set("_targeting", true)
	attack.call("_show_range", 80.0, 320.0)
	var normal_mesh: MeshInstance3D = attack.get("_range_preview") as MeshInstance3D
	var long_mesh: MeshInstance3D = attack.get("_long_range_preview") as MeshInstance3D
	var normal_ring: MeshInstance3D = attack.get("_range_outline") as MeshInstance3D
	var long_ring: MeshInstance3D = attack.get("_long_range_outline") as MeshInstance3D
	if normal_mesh == null or long_mesh == null or normal_ring == null or long_ring == null:
		_fail("3D normal/long mesh and outlines were not created")
		return
	if not normal_mesh.visible or not long_mesh.visible:
		_fail("3D circles were hidden in 3D view")
		return
	if normal_mesh.material_override == long_mesh.material_override:
		_fail("normal and long range did not have distinct materials")
		return
	# Both attack ranges must be actual hollow spherical surfaces, not
	# horizontal circles or tinted solid volumes.
	var normal_radius_world: float = 80.0 / 5.0 + 0.5
	var long_radius_world: float = 320.0 / 5.0 + 0.5
	for candidate: MeshInstance3D in [normal_mesh, normal_ring, long_mesh, long_ring]:
		if not candidate.mesh is ArrayMesh:
			_fail("3D reach is not a surface-line mesh")
			return
		var geometry: ArrayMesh = candidate.mesh as ArrayMesh
		if geometry.get_surface_count() != 1 or geometry.surface_get_primitive_type(0) != Mesh.PRIMITIVE_LINES:
			_fail("3D range uses filled triangles instead of a wireframe surface")
			return
		var expected_radius: float = long_radius_world if candidate == long_mesh or candidate == long_ring else normal_radius_world
		var vertices: PackedVector3Array = geometry.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			_fail("3D range wireframe contains no vertices")
			return
		for vertex: Vector3 in vertices:
			if absf(vertex.length() - expected_radius) > 0.002:
				_fail("3D wireframe vertex does not lie on the sphere surface")
				return
		var render_material: StandardMaterial3D = candidate.material_override as StandardMaterial3D
		if render_material == null or render_material.no_depth_test:
			_fail("range wireframe should be depth-tested in 3D")
			return
	var normal_vertices: PackedVector3Array = (normal_mesh.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var has_upper: bool = false
	var has_lower: bool = false
	for vertex: Vector3 in normal_vertices:
		has_upper = has_upper or vertex.y > normal_radius_world * 0.8
		has_lower = has_lower or vertex.y < -normal_radius_world * 0.8
	if not has_upper or not has_lower:
		_fail("3D range is a flat ring rather than a complete sphere")
		return
	if not is_equal_approx(float(attack.call("_max_attack_range_feet")), 320.0):
		_fail("long range was not accepted as outer limit")
		return

	# The all-creatures toggle must use the same two spherical shells.
	attacker.add_to_group("dnd_token")
	attacker.set_meta("active_weapon_long_range_feet", 320.0)
	var all_reach_root := Node3D.new()
	attack.add_child(all_reach_root)
	attack.set("_all_reach_root", all_reach_root)
	attack.set("_all_reaches_visible", true)
	attack.call("_refresh_all_reach_spheres", true)
	if all_reach_root.get_child_count() != 4:
		_fail("all-creature ranged reach should have normal/long spheres and equators")
		return
	var all_spheres: int = 0
	for mesh_node: Node in all_reach_root.get_children():
		if not mesh_node is MeshInstance3D:
			_fail("all-creature reach contains a non-mesh node")
			return
		var mesh_instance: MeshInstance3D = mesh_node as MeshInstance3D
		var reach_mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
		if reach_mesh == null or reach_mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_LINES:
			_fail("all-creature range is a filled or planar primitive")
			return
		var vertices: PackedVector3Array = reach_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			if absf(vertex.length() - normal_radius_world) < 0.002 and mesh_node.name.begins_with("ReachNormal_"):
				all_spheres += 1
				break
			if absf(vertex.length() - long_radius_world) < 0.002 and mesh_node.name.begins_with("ReachLong_"):
				all_spheres += 1
				break
	if all_spheres != 2:
		_fail("global reach did not create concentric normal and long 3D wire spheres")
		return
	attack.call("_hide_range")
	if normal_mesh.visible or long_mesh.visible or normal_ring.visible or long_ring.visible:
		_fail("cancelling targeting left range visuals on the map")
		return

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	board.add_child(camera)
	camera.position = Vector3(0, 20, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 40.0
	camera.current = true
	var ui := CanvasLayer.new()
	board.add_child(ui)
	var overlay: Control = RangeOverlay2D.new()
	ui.add_child(overlay)
	overlay.call("setup", board, attack)
	board.use_2d = true
	var projected_short: PackedVector2Array = overlay.call(
		"_screen_polygon", Vector3.ZERO, 0.5, 16.0
	)
	var projected_long: PackedVector2Array = overlay.call(
		"_screen_polygon", Vector3.ZERO, 0.5, 64.0
	)
	if projected_short.size() != projected_long.size():
		_fail("2D dual circles do not use the same contour representation")
		return
	var centroid: Vector2 = camera.unproject_position(Vector3.ZERO)
	if not Geometry2D.is_point_in_polygon(centroid, projected_short):
		_fail("normal 2D circle is not centered on token")
		return
	if not Geometry2D.is_point_in_polygon(centroid, projected_long):
		_fail("long 2D circle is not centered on token")
		return
	attack.call("_show_range", 80.0, 320.0)
	attack.call("_process", 0.0)
	if normal_mesh.visible or long_mesh.visible or normal_ring.visible or long_ring.visible:
		_fail("3D shells obstruct the top-down 2D overlay")
		return
	if all_reach_root.visible:
		_fail("all-creature 3D shells must hide in top-down view")
		return

	var monster: Dictionary = {
		"kind": "monster",
		"stat_block": {
			"action": [
				{"name": "Longbow", "entries": [
					"{@atk rw} Ranged Weapon Attack: {@hit +5} to hit, range 80/320 ft., one target. {@damage 1d8+3} piercing damage."
				]}
			]
		}
	}
	var definitions: Array[Dictionary] = AttackData.definitions(monster)
	if definitions.is_empty():
		_fail("bestiary range fixture produced no attack")
		return
	if int(definitions[0].get("range_feet", 0)) != 80 or int(definitions[0].get("long_range_feet", 0)) != 320:
		_fail("bestiary ranged attack lost its 80/320 ft values")
		return

	board.queue_free()
	await process_frame
	print("PASS: 2D contours and hollow concentric 3D reach spheres")
	quit()
