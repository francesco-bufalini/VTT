extends SceneTree

const Measurement = preload("res://measurement_tool.gd")
const BoxGeometry = preload("res://vtt/map_box_geometry.gd")
const Overlay = preload("res://vtt/spells/spell_target_overlay_2d.gd")

class Board extends Node3D:
	var measurement: Node3D
	var undo_states: Array = []
	var affected_tokens: Array = []
	func push_undo_state() -> void:
		undo_states.append(measurement.serialize_persistent_aoes())
	func is_2d_view_enabled() -> bool:
		return false
	func set_affected_token_highlight(tokens: Array) -> void:
		affected_tokens = tokens.duplicate()

class Spell extends Node:
	func is_targeting() -> bool:
		return false

class Token extends Node3D:
	var token_height_cells := 1.0
	func get_footprint_cells() -> int:
		return 1
	func get_display_name() -> String:
		return "Target"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var board := Board.new()
	root.add_child(board)
	var measure := Measurement.new()
	board.measurement = measure
	board.add_child(measure)
	var camera := Camera3D.new()
	board.add_child(camera)
	camera.position = Vector3(10, 12, 14)
	camera.look_at(Vector3.ZERO)
	measure.set_camera(camera)
	root.size = Vector2i(1280, 800)
	var canvas := CanvasLayer.new()
	board.add_child(canvas)
	var spell := Spell.new()
	board.add_child(spell)
	var overlay := Overlay.new()
	canvas.add_child(overlay)
	overlay.setup(board, spell, measure, camera)
	await process_frame

	measure.set_measurement_mode(true)
	measure.set_aoe_mode("parallelepiped")
	assert(measure.is_box_drawing_mode())
	# Free positions and a diagonal base must retain their exact dimensions.
	var origin := Vector3(0.25, 0.3, 0.75)
	var length := Vector3(3, 0, 4)
	var width := Vector3(-1.6, 0, 1.2)
	assert(measure.accept_box_drawing_point(origin))
	assert(not measure.accept_box_drawing_point(origin))
	assert(not measure.accept_box_drawing_point(Vector3.INF))
	assert(measure.accept_box_drawing_point(origin + length))
	assert(not measure.accept_box_drawing_point(origin + length * 0.5))
	assert(measure.accept_box_drawing_point(origin + width + length * 0.5))
	assert(measure.persistent_aoes.is_empty() and board.undo_states.is_empty(), "The first three clicks cannot commit or create undo entries")
	assert(not measure.accept_box_drawing_point(origin), "Zero height cannot create a volume")
	assert(measure.accept_box_drawing_point(origin + Vector3(7, 3, 9)))
	assert(measure.persistent_aoes.size() == 1 and board.undo_states == [[]])
	assert(not measure.is_dragging() and measure._drawing_points.is_empty())
	var saved: Array = JSON.parse_string(JSON.stringify(measure.serialize_persistent_aoes()))
	assert(measure.valid_aoes(saved))
	var points: Array = saved[0].box_points
	var geometry: Dictionary = BoxGeometry.geometry(points)
	assert(Vector3(geometry.size).is_equal_approx(Vector3(5, 3, 2)))
	assert(Vector3(geometry.position).is_equal_approx(origin + (length + width + Vector3.UP * 3) * 0.5))
	var visual: MeshInstance3D = measure._aoe_nodes[0].get_node("Visual")
	var pick: Area3D = measure._aoe_nodes[0].get_node("PickArea")
	assert(visual.mesh is BoxMesh and (visual.mesh as BoxMesh).size.is_equal_approx(geometry.size))
	assert(pick.global_transform.is_equal_approx(visual.global_transform), "Picking must use the same oriented volume as the visual")
	var outline: MeshInstance3D = visual.get_node("BoxOutline")
	assert((outline.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 24)
	var inside: Vector3 = geometry.position
	assert(measure._cell_intersects_aoe(inside, origin, origin + length, "parallelepiped", "", -1, points))
	var diagonal_edge_cell: Vector3 = inside + Vector3(geometry.basis.z) * 1.65
	assert(measure._cell_intersects_aoe(diagonal_edge_cell, origin, origin + length, "parallelepiped", "", -1, points), "An occupied grid-cell corner can intersect a rotated face")
	var outside: Vector3 = inside + Vector3(geometry.basis.z) * 4
	assert(not measure._cell_intersects_aoe(outside, origin, origin + length, "parallelepiped", "", -1, points))
	assert(not measure._cell_intersects_aoe(inside + Vector3.UP * 5, origin, origin + length, "parallelepiped", "", -1, points))
	var token := Token.new()
	board.add_child(token)
	token.add_to_group("dnd_token")
	token.position = inside
	assert(measure.area_affected_tokens(origin, origin + length, "parallelepiped", "", -1, points) == [token])
	assert(measure._token_touched_by_current_geometry(token))
	token.position = outside
	assert(not measure._token_touched_by_current_geometry(token))
	var dimensions: String = measure.aoe_dimensions_description(origin, origin + length, "parallelepiped", "", -1, points)
	assert("Lunghezza 25 ft" in dimensions and "Larghezza 10 ft" in dimensions and "Altezza 15 ft" in dimensions)
	overlay._collect_post_cast_areas()
	assert(overlay._areas.size() == 1)
	var polygon: PackedVector2Array = overlay._shape_polygon(origin, origin + length, "parallelepiped", -1, "", points)
	assert(polygon.size() == 4 and polygon[2].is_equal_approx(overlay._world_point(origin + length + width)))
	assert(overlay.mobile_map_areas({}).size() == 1, "Native drawings must project into shared map images")

	# A JSON transfer restores all four vertices and colour without additional undo.
	var undo_count: int = board.undo_states.size()
	measure.apply_persistent_aoes(saved)
	assert(board.undo_states.size() == undo_count)
	assert(JSON.stringify(measure.serialize_persistent_aoes()) == JSON.stringify(saved))
	for malformed: Variant in [[], [[0,0,0]], [[0,0,0],[1,0,0],[2,0,0],[0,1,0]],
		[[0,0,0],[1,0,0],[0,0,1],[0,0,0]], [[0,0,0],[1,0,0],[0,0,1],[1,2,0]],
		[[0,0,0],[1,0,0],[0,0,1],[0,INF,0]], [[0,0,0],[1,0,0],[0,0,1],[0,"bad",0]]]:
		var invalid: Array = saved.duplicate(true)
		invalid[0].box_points = malformed
		assert(not measure.valid_aoes(invalid))
		measure.apply_persistent_aoes(invalid)
		assert(JSON.stringify(measure.serialize_persistent_aoes()) == JSON.stringify(saved))
	# Moving the area updates all vertices, and cancelling a move preserves them.
	assert(measure.begin_movable_aoe_drag(0, true))
	measure._movable_aoe_drag_delta = Vector3(2, 1, -3)
	measure._aoe_nodes[0].position += measure._movable_aoe_drag_delta
	assert(measure.finish_movable_aoe_drag(true))
	assert(measure.persistent_aoes[0].box_points == BoxGeometry.translated(points, Vector3(2, 1, -3)))
	var moved: Array = measure.serialize_persistent_aoes()
	assert(measure.begin_movable_aoe_drag(0, true))
	measure._movable_aoe_drag_delta = Vector3.ONE
	measure._aoe_nodes[0].position += Vector3.ONE
	assert(not measure.finish_movable_aoe_drag(false))
	assert(measure.serialize_persistent_aoes() == moved)
	measure.apply_persistent_aoes(saved)

	# Height picking must work even for a vertical top-down camera.
	camera.position = Vector3(0, 20, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	assert(measure.accept_box_drawing_point(Vector3.ZERO))
	assert(measure.accept_box_drawing_point(Vector3(4, 0, 0)))
	assert(measure.accept_box_drawing_point(Vector3(0, 0, 2)))
	measure._drawing_height_anchor = 400
	measure._update_box_drawing_target(Vector2(640, 280))
	assert(is_equal_approx(measure._drawing_candidate.y, 3.0))
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(640, 280)
	assert(measure.handle_box_drawing_input(wheel))
	assert(is_equal_approx(measure._drawing_candidate.y, 4.0))
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	assert(measure.handle_box_drawing_input(release))
	assert(measure.persistent_aoes.size() == 1, "Release cannot commit the four-click tool")
	assert(measure._aoe_preview.visible)
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	assert(measure.handle_box_drawing_input(cancel))
	assert(not measure._aoe_preview.visible and measure._drawing_points.is_empty())
	assert(measure.persistent_aoes.size() == 1)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	assert(measure.handle_box_drawing_input(escape))
	assert(not measure.is_measurement_mode())
	# Exercise all four actual mouse presses against a ground surface. A release
	# between presses must neither finish nor restart the drawing.
	var ground := StaticBody3D.new()
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(30, 0.2, 30)
	ground_collision.shape = ground_shape
	ground.add_child(ground_collision)
	board.add_child(ground)
	ground.position.y = -0.1
	await physics_frame
	measure.set_measurement_mode(true)
	measure.set_aoe_mode("parallelepiped")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	for world: Vector3 in [Vector3(1,0,1), Vector3(5,0,1), Vector3(1,0,3)]:
		click.position = camera.unproject_position(world)
		assert(measure.handle_box_drawing_input(click))
		assert(measure.handle_box_drawing_input(release))
	assert(measure._drawing_points.size() == 3 and measure.persistent_aoes.size() == 1)
	var drawn_origin: Vector3 = measure._drawing_points[0]
	assert(Vector2(drawn_origin.x, drawn_origin.z).is_equal_approx(Vector2(1,1)), "Input ray must use the click position")
	token.position = Vector3(3, 2.2, 2)
	measure._update_box_drawing_target(click.position)
	measure._refresh_affected_token_highlight()
	assert(board.affected_tokens.is_empty())
	var motion := InputEventMouseMotion.new()
	motion.position = click.position - Vector2(0,120)
	assert(measure.handle_box_drawing_input(motion))
	measure._refresh_affected_token_highlight()
	assert(board.affected_tokens == [token], "Height changes must invalidate the affected-creature cache")
	overlay._collect_post_cast_areas()
	assert(overlay._sidebar_entries().size() == 2)
	assert(overlay._area_target_names(overlay._sidebar_entries()[0]) == ["Target"])
	click.position = motion.position
	assert(measure.handle_box_drawing_input(click))
	assert(measure.persistent_aoes.size() == 2 and measure._drawing_points.is_empty())
	assert(not measure._aoe_preview.visible)
	var input_snapshot: Array = measure.serialize_persistent_aoes()
	measure.apply_persistent_aoes(board.undo_states[-1])
	assert(measure.persistent_aoes.size() == 1, "Undo restores the snapshot before the fourth click")
	measure.apply_persistent_aoes(input_snapshot)
	assert(measure.persistent_aoes.size() == 2, "Redo restores the committed drawing")
	assert(measure.dissolve_aoe(1))
	measure.set_measurement_mode(false)
	# Legacy area snapshots continue to round-trip alongside drawings.
	measure.add_aoe(Vector3.ZERO, Vector3(2,0,0), "sphere")
	var mixed: Array = JSON.parse_string(JSON.stringify(measure.serialize_persistent_aoes()))
	assert(measure.valid_aoes(mixed))
	measure.apply_persistent_aoes(mixed)
	assert(JSON.stringify(measure.serialize_persistent_aoes()) == JSON.stringify(mixed))
	assert(measure.dissolve_aoe(0) and measure.persistent_aoes.size() == 1)
	var arena: Node3D = load("res://tests/scenes/agent_test_arena.tscn").instantiate()
	root.add_child(arena)
	var sync_measure := Measurement.new()
	arena.add_child(sync_measure)
	sync_measure.apply_persistent_aoes(mixed)
	var initiative: Node = load("res://vtt/initiative_tracker.gd").new()
	initiative.name = "InitiativeTracker"
	arena.add_child(initiative)
	var sync: Node = load("res://network/board_sync.gd").new()
	arena.add_child(sync)
	sync.setup(arena, load("res://token.tscn"), arena.get_node("Tokens"), sync_measure)
	sync.set_auto_sync_enabled(false)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sync.create_snapshot()))
	assert(sync.valid_snapshot(snapshot), "The board transport schema must accept drawings")
	assert(sync.apply_snapshot(snapshot))
	assert(JSON.stringify(sync_measure.serialize_persistent_aoes()) == JSON.stringify(mixed))
	arena.queue_free()
	board.queue_free()
	await process_frame
	print("PASS: map box four-point drawing, oriented geometry, picking, height, cancel, move and persistence")
	quit()
