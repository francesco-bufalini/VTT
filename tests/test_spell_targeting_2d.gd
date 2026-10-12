extends SceneTree

const SpellSystem = preload("res://vtt/spells/spell_system.gd")
const SpellTargetOverlay2D = preload("res://vtt/spells/spell_target_overlay_2d.gd")
const MeasurementTool = preload("res://measurement_tool.gd")


class TopDownCamera:
	extends Camera3D

	func get_top_down_level() -> float:
		return 0.0


class TwoDimensionalBoard:
	extends Node3D

	var cell_size: float = 1.0
	var chosen_token: Node3D

	func is_2d_view_enabled() -> bool:
		return true

	func _raycast_token_from_screen(_position: Vector2, _areas: bool = true) -> Dictionary:
		if chosen_token != null:
			return {"collider": chosen_token}
		return {}

	func _raycast_from_screen(_position: Vector2, _mask: int, _areas: bool = false) -> Dictionary:
		# The ordinary 3D ray deliberately misses the token.
		return {}

	func _find_interaction_target(node: Node) -> Node:
		return node


func _fail(message: String) -> void:
	push_error("2D spell targeting: " + message)
	quit(1)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var board := TwoDimensionalBoard.new()
	root.add_child(board)

	var camera := TopDownCamera.new()
	camera.name = "Camera3D"
	board.add_child(camera)
	camera.position = Vector3(0.0, 16.0, 0.0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 30.0
	camera.current = true

	var token := Node3D.new()
	token.name = "Visible2DToken"
	token.add_to_group("dnd_token")
	board.add_child(token)
	board.chosen_token = token

	var measure := MeasurementTool.new()
	measure.name = "MeasurementTool"
	board.add_child(measure)
	measure.set_camera(camera)
	var spell := SpellSystem.new()
	spell.name = "SpellSystem"
	board.add_child(spell)
	spell.set("board_root", board)

	var screen_center: Vector2 = camera.unproject_position(Vector3.ZERO)
	if spell.call("_token_at_screen", screen_center) != token:
		_fail("2D token picker did not override an obstructed/missing 3D raycast")
		return

	var point_value: Variant = spell.call("_screen_2d_point_data", screen_center)
	if not point_value is Dictionary or not bool(point_value.get("valid", false)):
		_fail("2D mouse did not yield a target point on the active floor")
		return
	var point: Vector3 = point_value.get("point", Vector3.INF)
	if point.distance_to(Vector3.ZERO) > 0.01:
		_fail("2D targeting did not project to the floor below the pointer")
		return

	var ui := CanvasLayer.new()
	board.add_child(ui)
	var overlay: Control = SpellTargetOverlay2D.new()
	ui.add_child(overlay)
	overlay.call("setup", board, spell, measure, camera)
	var circle: PackedVector2Array = overlay.call(
		"_shape_polygon", Vector3.ZERO, Vector3.RIGHT * 2.0, "sphere", -1.0
	)
	if circle.size() < 24 or not Geometry2D.is_point_in_polygon(screen_center, circle):
		_fail("screen-space circle omitted its center")
		return

	measure.call(
		"show_held_spell_aoe", Vector3.ZERO, Vector3.RIGHT * 2.0, "sphere", "fire"
	)
	if not bool(overlay.call("remove_area_at_screen", screen_center)):
		_fail("clicking the drawn 2D area did not dismiss it")
		return
	if bool(measure.call("has_post_cast_spell_visuals")):
		_fail("2D dismissed area remained in the measurement tool")
		return

	board.queue_free()
	await process_frame
	print("PASS: 2D spell targeting and overlay")
	quit()
