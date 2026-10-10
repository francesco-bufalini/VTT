extends SceneTree

const MeasurementTool = preload("res://measurement_tool.gd")


class PickCamera extends Camera3D:
	var top_down: bool = false

	func is_top_down_2d() -> bool:
		return top_down


class PickToken extends CharacterBody3D:
	var token_height_cells: float = 2.0
	var cell_size: float = 1.0
	var footprint_cells: float = 1.0
	func get_footprint_cells() -> float:
		return footprint_cells


class PickBoard extends Node3D:
	var candidate: CharacterBody3D

	func _raycast_token_from_screen(
		_screen: Vector2,
		_allow_areas: bool = true
	) -> Dictionary:
		if candidate == null:
			return {}
		return {
			"collider": candidate,
			"position": candidate.global_position,
			"normal": Vector3.UP
		}


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> bool:
	if not value:
		push_error("Ruler token anchor: " + message)
		quit(1)
	return value


func _run() -> void:
	var board: PickBoard = PickBoard.new()
	root.add_child(board)
	var camera: PickCamera = PickCamera.new()
	board.add_child(camera)
	var ruler: Node3D = MeasurementTool.new()
	ruler.cell_size = 1.0
	board.add_child(ruler)
	ruler.call("set_camera", camera)

	var token: PickToken = PickToken.new()
	token.add_to_group("dnd_token")
	board.add_child(token)
	token.global_position = Vector3(2.5, 7.0, 4.5)
	board.candidate = token
	var expected := Vector3(2.5, 5.5, 4.5)
	if not _check(
		Vector3(ruler.call("_ruler_token_anchor", token)).is_equal_approx(expected),
		"a flying token must be measured from the supporting free air square, not its lowest occupied cell or ground"
	):
		return

	# A taller creature has a different body center but its support is
	# always the free voxel directly below its footprint.
	token.token_height_cells = 4.0
	var tall_expected := Vector3(2.5, 4.5, 4.5)
	if not _check(
		Vector3(ruler.call("_ruler_token_anchor", token)).is_equal_approx(tall_expected),
		"large vertical token extent must not shift support into an occupied square"
	):
		return
	token.token_height_cells = 2.0

	# In 3D, a token in front of the floor should win over the terrain ray.
	var ray_origin := Vector3(2.5, 20.0, 4.5)
	var floor_hit := {"position": Vector3(2.5, 0.0, 4.5)}
	var target: Dictionary = ruler.call(
		"_ruler_token_under_mouse", Vector2.ZERO, floor_hit, ray_origin
	)
	if not _check(
		bool(target.get("valid", false))
		and Vector3(target.get("center", Vector3.ZERO)).is_equal_approx(expected),
		"3D ruler must use the frontmost token, rather than the space behind"
	):
		return

	# Still respect genuine occlusion in 3D.
	var wall_hit := {"position": Vector3(2.5, 12.0, 4.5)}
	target = ruler.call(
		"_ruler_token_under_mouse", Vector2.ZERO, wall_hit, ray_origin
	)
	if not _check(
		target.is_empty(),
		"a token behind a nearer physical wall must not be picked in 3D"
	):
		return

	# 2D token badges represent even flying creatures, regardless of the
	# terrain ray, which would otherwise incorrectly pick the ground below.
	camera.top_down = true
	target = ruler.call(
		"_ruler_token_under_mouse", Vector2.ZERO, floor_hit, ray_origin
	)
	if not _check(
		bool(target.get("valid", false))
		and Vector3(target.get("center", Vector3.ZERO)).is_equal_approx(expected),
		"2D ruler must preserve floating token altitude instead of floor altitude"
	):
		return


	# Measure to the nearest occupied grid-square centre (not the middle
	# of a 2x2 or 3x3 miniature). Height still uses the free support square.
	token.footprint_cells = 2.0
	var nearest: Vector3 = ruler.call(
		"_ruler_closest_footprint_cell", token, Vector3(5.5, 5.5, 4.0)
	)
	if not _check(nearest.is_equal_approx(Vector3(3.0, 5.5, 4.0)),
		"Large footprint measures from its nearest occupied square"):
		return
	var small_nearest: Vector3
	token.footprint_cells = 0.5
	small_nearest = ruler.call(
		"_ruler_closest_footprint_cell", token, Vector3(5.5, 5.5, 4.0)
	)
	if not _check(small_nearest.is_equal_approx(expected),
		"Tiny creatures still occupy one tactical square"):
		return
	token.footprint_cells = 3.0
	nearest = ruler.call(
		"_ruler_closest_footprint_cell", token, Vector3(5.5, 5.5, 4.5)
	)
	if not _check(nearest.is_equal_approx(Vector3(3.5, 5.5, 4.5)),
		"Huge footprint picks its outermost occupied square"):
		return

	board.queue_free()
	await process_frame
	print("PASS: ruler picks 3D tokens and flying 2D tokens at their actual altitude")
	quit(0)
