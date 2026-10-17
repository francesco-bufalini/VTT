extends SceneTree
const Measurement = preload("res://measurement_tool.gd")
const Geometry = preload("res://vtt/attack_range_geometry.gd")
const Overlay = preload("res://vtt/spells/spell_target_overlay_2d.gd")

class Board extends Node3D:
	var cell_size := 1.0
	func is_2d_view_enabled() -> bool:
		return false
	func set_affected_token_highlight(_tokens: Array) -> void:
		pass

class Spell extends Node:
	func is_targeting() -> bool:
		return false

class Token extends Node3D:
	var token_height_cells := 1.0
	var label := "Goblin"
	func get_footprint_cells() -> int:
		return 1
	func get_display_name() -> String:
		return label

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var board := Board.new()
	root.add_child(board)
	var measure := Measurement.new()
	board.add_child(measure)
	var camera := Camera3D.new()
	board.add_child(camera)
	camera.position = Vector3(17, 16, 22)
	camera.look_at(Vector3(3, 1, 0))
	var canvas := CanvasLayer.new()
	board.add_child(canvas)
	var spell := Spell.new()
	board.add_child(spell)
	var overlay := Overlay.new()
	canvas.add_child(overlay)
	overlay.setup(board, spell, measure, camera)
	root.size = Vector2i(1360, 850)
	await process_frame
	for shape: String in ["sphere", "cube", "cone", "cylinder", "line", "flat_square"]:
		var visual := MeshInstance3D.new()
		board.add_child(visual)
		measure._draw_aoe(visual, Vector3.ZERO, Vector3(4, 4, 0), shape)
		var rays := visual.get_node("DimensionRadii") as MeshInstance3D
		assert(rays != null and rays.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_LINES)
		var vertices: PackedVector3Array = rays.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert(vertices.size() == (4 if shape == "flat_square" else 6))
		for index: int in range(0, vertices.size(), 2):
			assert(vertices[index] == Vector3.ZERO)
			assert(vertices[index + 1].length() > 0.0)
		var parent_material := visual.material_override as StandardMaterial3D
		var ray_material := rays.material_override as StandardMaterial3D
		assert(parent_material.emission.is_equal_approx(ray_material.emission))
		if shape == "sphere":
			var radius: float = (visual.mesh as SphereMesh).radius
			for index: int in [1, 3, 5]:
				assert(is_equal_approx(vertices[index].length(), radius))
		if shape == "cone":
			assert(is_equal_approx(vertices[1].x, (visual.mesh as CylinderMesh).top_radius * 0.5))
		visual.queue_free()
	var wire: ArrayMesh = Geometry.sphere_wire_mesh(3)
	var wire_points: PackedVector3Array = wire.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert(wire_points.slice(wire_points.size() - 6) == PackedVector3Array([
		Vector3.ZERO, Vector3(3, 0, 0), Vector3.ZERO, Vector3(0, 3, 0), Vector3.ZERO, Vector3(0, 0, 3)]))
	var diagonal_end := Vector3(4, 0, 4)
	var diagonal_geometry: Dictionary = measure._aoe_geometry(Vector3.ZERO, diagonal_end, "sphere")
	var diagonal_polygon: PackedVector2Array = overlay._shape_polygon(Vector3.ZERO, diagonal_end, "sphere")
	assert(diagonal_polygon[0].is_equal_approx(overlay._world_point(Vector3.RIGHT * float(diagonal_geometry.radius))),
		"2D contour and radii must use the same snapped D&D dimensions as the 3D figure")
	for index: int in range(13):
		measure.add_aoe(Vector3(index * 2, 1, 0), Vector3(index * 2 + 2, 1, 0), "sphere")
	var colors: Dictionary = {}
	for data: Dictionary in measure.persistent_aoes:
		var key: String = JSON.stringify(data.color)
		assert(not colors.has(key), "Repeated same-shape areas need different colours beyond the initial palette")
		colors[key] = true
	var sphere_dimensions: String = measure.aoe_dimensions_description(
		Vector3.ZERO, Vector3(3, 0, 0), "sphere"
	)
	assert("15 ft · 4,5 m · 3 quadretti" in sphere_dimensions,
		"Area sidebar measurements must include feet, metres and squares")
	var cube_dimensions: String = measure.aoe_dimensions_description(
		Vector3.ZERO, Vector3(3, 0, 0), "cube"
	)
	assert("Lato 30 ft · 9 m · 6 quadretti" in cube_dimensions,
		"A cube must report its full side length in every unit")
	var cone_dimensions: String = measure.aoe_dimensions_description(
		Vector3.ZERO, Vector3(3, 0, 0), "cone"
	)
	assert("Raggio base 7,5 ft · 2,25 m · 1,5 quadretti" in cone_dimensions,
		"Fractional base radii must keep their precision")
	var saved: Array = measure.serialize_persistent_aoes()
	measure.apply_persistent_aoes(saved)
	assert(JSON.stringify(saved) == JSON.stringify(measure.serialize_persistent_aoes()))
	measure.clear_persistent_aoes()
	measure.add_aoe(Vector3(0, 1, 0), Vector3(3, 1, 0), "sphere", "fireball")
	measure.add_aoe(Vector3(6, 1, 0), Vector3(9, 1, 0), "sphere", "fireball")
	assert(measure.persistent_aoes[0].color != measure.persistent_aoes[1].color)
	measure.add_aoe(Vector3(0, 1, 4), Vector3(7, 1, 4), "line")
	var target := Token.new()
	board.add_child(target)
	target.add_to_group("dnd_token")
	target.position = Vector3(3, 1, 4)
	var outside := Token.new()
	board.add_child(outside)
	outside.add_to_group("dnd_token")
	outside.label = "Orco"
	outside.position = Vector3(3, 1, 9)
	assert(measure.area_affected_tokens(Vector3(0, 1, 4), Vector3(7, 1, 4), "line") == [target])
	overlay._collect_post_cast_areas()
	overlay._refresh_area_sidebar()
	assert(overlay._areas.size() == 3 and overlay._area_sidebar.visible)
	assert(overlay._area_target_names(overlay._areas[2]) == ["Goblin"])
	assert(overlay._area_color(overlay._areas[0]) != overlay._area_color(overlay._areas[1]))
	target.position.z = 10
	overlay._refresh_area_sidebar()
	assert(overlay._area_target_names(overlay._areas[2]).is_empty(), "Lists must refresh when creatures move")
	measure.aoe_mode = true
	measure.aoe_shape = "line"
	measure._start_center = Vector3(0, 1, 4)
	measure._end_center = Vector3(7, 1, 4)
	measure._update_visuals()
	overlay._refresh_area_sidebar()
	assert(overlay._sidebar_entries().size() == 4, "Manual AoE creation must immediately have its own creature panel")
	measure.cancel_measurement()
	overlay._refresh_area_sidebar()
	assert(overlay._sidebar_entries().size() == 3)
	measure.show_held_spell_aoe(Vector3(0, 1, 0), Vector3(3, 1, 0), "sphere", "fireball")
	overlay._collect_post_cast_areas()
	assert(overlay._areas.size() == 4)
	var snapshot := measure.serialize_persistent_aoes()
	assert(measure.valid_aoes(snapshot))
	measure.clear_held_spell_aoes()
	var fixed_starts: Array[Vector3] = [Vector3(0, 1, 0), Vector3(6, 1, 0)]
	var fixed_ends: Array[Vector3] = [Vector3(3, 1, 0), Vector3(9, 1, 0)]
	measure.show_spell_fixed_previews(fixed_starts, fixed_ends, "sphere", "fireball")
	assert(measure._spell_fixed_previews[0].get_meta("area_dimensions").color
		!= measure._spell_fixed_previews[1].get_meta("area_dimensions").color)
	overlay._collect_post_cast_areas()
	assert(overlay._sidebar_entries().size() == 5, "Fixed multi-point previews also belong in the figure list")
	measure.clear_spell_fixed_previews()
	overlay._collect_post_cast_areas()
	overlay._refresh_area_sidebar()
	assert(overlay._area_rows.find_child("MoveAreaButton", true, false) != null)
	assert(overlay._area_rows.find_child("DeleteAreaButton", true, false) != null)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		target.position.z = 4
		overlay._collect_post_cast_areas()
		overlay._refresh_area_sidebar()
		for index: int in range(6):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://area_dimensions_review.png")
		print("CAPTURE: ", ProjectSettings.globalize_path("user://area_dimensions_review.png"))
	measure.show_held_spell_aoe(Vector3(0, 1, 0), Vector3(3, 1, 0), "sphere", "fireball")
	overlay._collect_post_cast_areas()
	overlay._refresh_area_sidebar()
	# Sidebar actions must address the selected root rather than a stale row
	# index: the held area precedes persistent areas in the sidebar.
	var static_root: Node3D = measure._aoe_nodes[0]
	# The static area was created at the origin.
	assert(measure.persistent_aoes[0].start == [0.0, 1.0, 0.0])
	overlay._move_sidebar_area(static_root)
	assert(measure.is_movable_aoe_dragging())
	assert(measure._movable_aoe_drag_unrestricted)
	measure._movable_aoe_drag_delta = Vector3(2, 0, 1)
	static_root.global_position = measure._movable_aoe_drag_root_origin + Vector3(2, 0, 1)
	assert(measure.finish_movable_aoe_drag(true))
	assert(measure.persistent_aoes[0].start == [2.0, 1.0, 1.0])
	var remaining: int = measure.persistent_aoes.size()
	overlay._delete_sidebar_area(static_root)
	assert(measure.persistent_aoes.size() == remaining - 1)
	assert(not is_instance_valid(static_root) or static_root.is_queued_for_deletion())

	var held_root: Node3D = measure._held_spell_aoes[0]
	var held_start: Vector3 = held_root.get_meta("spell_overlay_2d").start
	overlay._move_sidebar_area(held_root)
	assert(measure.is_movable_aoe_dragging())
	measure._movable_aoe_drag_delta = Vector3(1, 0, 2)
	held_root.global_position = measure._movable_aoe_drag_root_origin + Vector3(1, 0, 2)
	assert(measure.finish_movable_aoe_drag(true))
	assert(held_root.get_meta("spell_overlay_2d").start == held_start + Vector3(1, 0, 2))
	overlay._delete_sidebar_area(held_root)
	assert(measure._held_spell_aoes.is_empty())

	measure.add_aoe(Vector3(2, 0, 2), Vector3(6, 0, 2), "sphere",
		"cloudkill", Color(1, 0, 0), -1.0, 10.0, "away_from_caster", Vector3.ZERO)
	var mobile_root: Node3D = measure._aoe_nodes[-1]
	overlay._move_sidebar_area(mobile_root)
	assert(measure.is_movable_aoe_dragging())
	assert(not measure._movable_aoe_drag_unrestricted,
		"Sidebar movement must retain existing spell-defined movement restrictions")
	assert(not measure.finish_movable_aoe_drag(false))
	board.queue_free()
	await process_frame
	print("PASS: area radii, metric/grid units, per-figure sidebar actions, spell movement limits and round-trip")
	quit()