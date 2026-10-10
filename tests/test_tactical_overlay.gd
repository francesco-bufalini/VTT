extends SceneTree

const Flanking = preload("res://vtt/flanking_system.gd")
const Overlay = preload("res://vtt/top_down_elevation_overlay.gd")
const Token = preload("res://token.tscn")

class Board extends Node3D:
	var cell_size := 1.0
	var top_down := false
	func is_2d_view_enabled() -> bool:
		return top_down


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var board := Board.new()
	root.add_child(board)
	var tokens := Node3D.new()
	tokens.name = "Tokens"
	board.add_child(tokens)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	board.add_child(ui)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	board.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	camera.position = Vector3(0, 20, 10)
	camera.look_at(Vector3.ZERO)
	for i: int in range(3):
		var token: CharacterBody3D = Token.instantiate()
		token.visual_asset_path = "res://assets/tokens/test/test_token_visual.tscn"
		tokens.add_child(token)
		token.position = Vector3(i - 1, 0.5, 0)
		token.set_flying(true)
		token.set_party_id("enemies" if i == 1 else "party")
		token.set_conditions(["poisoned"])
		token.set_player_hit_points(7, 12)
		assert(token.get_node_or_null("TokenOverlay/FlankingBadge") == null,
			"Flanking badges belong to the shared tactical renderer")
		assert(token.get_player_hit_points() == {"current": 7, "max": 12})
	var flanking := Flanking.new()
	board.add_child(flanking)
	flanking.setup(board)
	assert(tokens.get_child(1).get_meta("flanked", false), "Opposite enemies must flank the middle token")
	assert(not flanking.get_screen_reach_visuals().mutual_markers.is_empty())
	assert(flanking._arrow_instance.visible and flanking._arrow_mesh.get_surface_count() > 0)
	var overlay := Overlay.new()
	ui.add_child(overlay)
	overlay.setup(board, null)
	var z_test_badge: Control = overlay.call("_new_badge") as Control
	assert(z_test_badge.z_index < 0,
		"2D reach arrows rendered by the parent must be in front of token portraits")
	z_test_badge.queue_free()
	for floor_y: float in [0.0, 8.0, -3.0]:
		var expected := camera.unproject_position(Vector3(1.0, floor_y, 2.0))
		for height: float in [-10.0, 0.0, 12.0]:
			assert(overlay.project_engagement_point(Vector3(1, height, 2), floor_y).is_equal_approx(expected),
				"Reach arrows must share the token badge plane at every camera floor")
	# At every orthographic zoom level a portrait occupies exactly its
	# projected world-grid footprint (no 16/180 pixel cap).
	var portrait_origin := Vector3.ZERO
	camera.size = 20.0
	var normal_extent: Vector2 = Overlay.token_icon_extent_pixels(camera, portrait_origin, 2.0)
	camera.size = 5.0
	var close_extent: Vector2 = Overlay.token_icon_extent_pixels(camera, portrait_origin, 2.0)
	assert(close_extent.is_equal_approx(normal_extent * 4.0),
		"2D portrait footprint must scale linearly with camera zoom")
	camera.size = 20.0
	board.top_down = true
	flanking.refresh_now()
	assert(not flanking._arrow_instance.visible, "2D must not draw duplicate 3D arrows")
	assert(not flanking.get_screen_reach_visuals().mutual_markers.is_empty())
	board.top_down = false
	flanking.refresh_now()
	assert(flanking._arrow_instance.visible and flanking._arrow_mesh.get_surface_count() > 0)
	board.queue_free()
	await process_frame
	print("PASS: tactical badges, token health, 2D reach projection and 3D arrow restoration")
	quit()
