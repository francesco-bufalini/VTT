extends SceneTree

const CameraController = preload("res://camera_controller.gd")
const ElevationLevels = preload("res://vtt/top_down_elevation_levels.gd")
const ElevationOverlay = preload("res://vtt/top_down_elevation_overlay.gd")


class Board extends Node3D:
	var cell_size: float = 1.0


class OverlayToken extends CharacterBody3D:
	var token_height_cells: float = 1.0
	var cell_size: float = 1.0
	var show_conditions: bool = true

	func get_display_name() -> String:
		return "Guardia"

	func get_footprint_cells() -> float:
		return 1.0

	func get_active_condition_display_parts() -> PackedStringArray:
		return PackedStringArray(["☠ Poisoned", "✦ Blinded"])

	func are_condition_visuals_visible() -> bool:
		return show_conditions


func _initialize() -> void:
	call_deferred("run")


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("Camera 2D floors: " + message)
		quit(1)
	return condition


func _hold_fixture_levels() -> Array[float]:
	return [0.0, 6.0, 12.0, 18.0]


func _add_floor(board: Node3D, y: float, side: float = 15.0) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.position.y = y - 0.1
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(side, 0.2, side)
	shape.shape = box
	body.add_child(shape)
	board.add_child(body)


func run() -> void:
	var board: Board = Board.new()
	root.add_child(board)
	_add_floor(board, 0.0)
	# Upper deck covers only the central squares, leaving exposed ground
	# around it for hover tests in the same view.
	_add_floor(board, 6.0, 5.0)

	var camera: Camera3D = CameraController.new()
	camera.name = "Camera3D"
	board.add_child(camera)
	camera.set_process(false)
	var original_transform := Transform3D(
		Basis.from_euler(Vector3(-0.3, 0.25, 0.0)),
		Vector3(4.0, 8.0, 12.0)
	)
	camera.global_transform = original_transform
	var initial_near: float = camera.near

	var probe: Node3D = ElevationLevels.new()
	board.add_child(probe)
	probe.call("setup", board)
	camera.call(
		"set_top_down_floor_levels_provider",
		Callable(probe, "get_solid_levels")
	)
	# Allow Godot's physics server to register the collision boxes.
	await physics_frame
	await physics_frame

	camera.call("enter_top_down_2d", Vector3.ZERO, 30.0, 0.0)
	var solid_levels: Array = probe.call("get_solid_levels")
	if not _check(
		solid_levels.size() == 2
		and absf(float(solid_levels[0])) < 0.01
		and absf(float(solid_levels[1]) - 6.0) < 0.01,
		"two stacked collidable floors must yield two discrete levels"
	):
		return

	# Before ascending, the upper deck must not displace the visible
	# ground floor in the tooltip's height calculation.
	var ground_before: Dictionary = probe.call(
		"get_visible_square_surface", Vector3(0.1, 0.0, 0.1), 0.0
	) as Dictionary
	if not _check(
		not ground_before.is_empty()
		and absf(float(ground_before.get("level", -100.0))) < 0.01,
		"lower camera floor must pick visible ground, not a clipped upper deck"
	):
		return

	var initial_position: Vector3 = camera.global_position
	var initial_size: float = camera.size
	var slice_near: float = camera.near
	camera.call("step_top_down_level", 1)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 6.0),
		"Space must step to the next higher solid surface"
	):
		return
	if not _check(
		camera.global_position.is_equal_approx(initial_position + Vector3.UP * 6.0),
		"moving up a floor must preserve camera clearance"
	):
		return
	if not _check(
		is_equal_approx(camera.size, initial_size)
		and is_equal_approx(camera.near, slice_near),
		"floor navigation must not alter orthographic zoom or slice distance"
	):
		return
	camera.call("step_top_down_level", 1)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 6.0),
		"no solid above must prevent further climbing"
	):
		return

	# Regression: the upper deck becomes visible when ascending. The
	# tooltip must follow that deck, not the floor it used before the step.
	var visible_upper: Dictionary = probe.call(
		"get_visible_square_surface", Vector3(0.1, 6.0, 0.1), 6.0
	) as Dictionary
	if not _check(
		not visible_upper.is_empty()
		and absf(float(visible_upper.get("level", -100.0)) - 6.0) < 0.01,
		"after ascending, hovering the same square must pick the new upper deck"
	):
		return
	var uncovered_lower: Dictionary = probe.call(
		"get_visible_square_surface", Vector3(4.1, 6.0, 0.1), 6.0
	) as Dictionary
	if not _check(
		not uncovered_lower.is_empty()
		and absf(float(uncovered_lower.get("level", -100.0))) < 0.01,
		"when no upper surface exists, hovering an uncovered square picks the lower deck"
	):
		return
	var overlay_probe: Control = ElevationOverlay.new()
	if not _check(
		int(overlay_probe.call(
			"_difference_cells",
			float(visible_upper.get("level", -100.0)) - 6.0
		)) == 0,
		"same-level square must not display a stale lower-floor height tooltip"
	):
		return
	overlay_probe.free()

	camera.call("step_top_down_level", -1)
	if not _check(
		camera.global_position.is_equal_approx(initial_position),
		"Shift+Space must return to the lower level"
	):
		return

	camera.call("enter_top_down_2d", Vector3.ZERO, 30.0, 12.0)
	initial_position = camera.global_position
	camera.call("step_top_down_level", 1)
	if not _check(
		camera.global_position.is_equal_approx(initial_position + Vector3.UP * 6.0),
		"tilted forest view must preserve the target when changing floors"
	):
		return

	var overlay: Control = ElevationOverlay.new()
	board.add_child(overlay)
	# 1 square = 5 ft = 1.5 m by the VTT's tactical convention.
	# No centimeter conversions or fractional physical offsets should leak
	# into the on-screen height labels.
	if not _check(
		String(overlay.call("_format_difference", 1.0)) == "+1 □",
		"height overlay must display only tactical squares"
	):
		return
	if not _check(
		String(overlay.call("_format_difference", 2.0)) == "+2 □",
		"two squares must not show metres or feet"
	):
		return
	if not _check(
		String(overlay.call("_format_difference", -1.0)) == "-1 □",
		"negative elevations must preserve their square sign"
	):
		return
	if not _check(
		String(overlay.call("_format_difference", 1.02)) == "+1 □",
		"minor physics offsets must snap to whole tactical squares"
	):
		return
	if not _check(
		int(overlay.call("_difference_cells", 0.02)) == 0,
		"sub-cell physics offsets must not generate zero-height badges"
	):
		return
	# Map collision faces can sit half a grid square below the tactical
	# slice without constituting a lower floor. They must not show -1.
	if not _check(
		int(overlay.call("_difference_cells", -0.5)) == 0,
		"half-cell floor-face offsets must not produce false -1 square hover"
	):
		return
	if not _check(
		int(overlay.call("_difference_cells", -1.0)) == -1,
		"a genuinely lower floor must still display -1 square"
	):
		return

	# The 3D rings can be clipped by the selected camera floor, but the
	# screen-space conditions and their legible labels must remain visible.
	var tokens_root: Node3D = Node3D.new()
	tokens_root.name = "Tokens"
	board.add_child(tokens_root)
	var condition_token: OverlayToken = OverlayToken.new()
	condition_token.position = Vector3(0.0, 6.5, 0.0)
	tokens_root.add_child(condition_token)
	overlay.call("setup", board, probe)
	overlay.call("set_2d_active", true)
	overlay.call("_render_token_badge", condition_token, 6.0)
	var badges_value: Variant = overlay.get("_badges")
	var condition_badge: Control = (badges_value as Dictionary).get(
		condition_token.get_instance_id()
	) as Control
	if not _check(
		condition_badge != null and condition_badge.visible,
		"2D conditions must have a visible screen-space badge"
	):
		return
	var condition_label: Label = condition_badge.get_node("Conditions") as Label
	var token_name_label: Label = condition_badge.get_node("Name") as Label
	var token_height_label: Label = condition_badge.get_node("Height") as Label
	if not _check(
		condition_label.visible
		and "☠" in condition_label.text
		and "✦" in condition_label.text,
		"all active conditions must appear above the 2D token"
	):
		return
	if not _check(
		token_name_label.get_theme_font_size("font_size") >= 18
		and condition_label.get_theme_font_size("font_size") >= 13
		and token_height_label.get_theme_font_size("font_size") >= 13
		and condition_label.size.y <= 20.0
		and condition_label.size.x <= 176.0
		and condition_label.position.y > token_name_label.position.y,
		"compact conditions must stay directly below the name"
	):
		return
	camera.call("step_top_down_level", -1)
	overlay.call("_render_token_badge", condition_token, 0.0)
	if not _check(
		condition_badge.visible
		and condition_label.visible
		and "☠" in condition_label.text,
		"changing the camera floor must not hide active conditions"
	):
		return
	condition_token.show_conditions = false
	overlay.call("_render_token_badge", condition_token, 0.0)
	if not _check(
		not condition_label.visible,
		"the existing show/hide conditions setting must be respected"
	):
		return
	condition_token.set_meta("flanked", true)
	overlay.call("_render_token_badge", condition_token, 0.0)
	if not _check(
		condition_label.visible and "⚔" in condition_label.text,
		"the 2D strip must show computed flanking even with manual conditions hidden"
	):
		return

	# Floating creatures contribute the free AIR square directly below
	# their feet, not the lowest voxel occupied by the creature.
	var floating_token: OverlayToken = OverlayToken.new()
	floating_token.position = Vector3(2.0, 10.5, 2.0)
	floating_token.add_to_group("dnd_token")
	tokens_root.add_child(floating_token)
	# A creature actually resting on a collidable floor must not add an
	# artificial level half a square BELOW the floor.
	var grounded_token: OverlayToken = OverlayToken.new()
	grounded_token.position = Vector3(4.0, 0.5, 4.0)
	grounded_token.add_to_group("dnd_token")
	tokens_root.add_child(grounded_token)
	camera.call("set_top_down_level", 6.0)
	var navigation_levels: Array = probe.call("get_solid_levels")
	if not _check(
		navigation_levels.size() == 3
		and is_equal_approx(float(navigation_levels[2]), 9.5),
		"only the airborne support square, not an occupied token cell or a solid floor underside, must become a camera stop"
	):
		return
	camera.call("step_top_down_level", 1)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 9.5),
		"Space must ascend from the collision floor to the supporting air cell"
	):
		return
	camera.call("step_top_down_level", -1)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 6.0),
		"Shift+Space must descend from a flying token's air base to the collision floor"
	):
		return
	# A two-cell-tall creature's air base must not depend on its center or
	# the height of its lowest occupied voxel.
	var tall_token: OverlayToken = OverlayToken.new()
	tall_token.token_height_cells = 2.0
	tall_token.position = Vector3(4.0, 13.0, 4.0)
	tall_token.add_to_group("dnd_token")
	tokens_root.add_child(tall_token)
	navigation_levels = probe.call("get_solid_levels")
	if not _check(
		navigation_levels.size() == 4
		and is_equal_approx(float(navigation_levels[3]), 11.5),
		"a two-cell-tall flying token must contribute its support AIR cell"
	):
		return
	camera.call("step_top_down_level", 1)
	camera.call("step_top_down_level", 1)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 11.5),
		"Space must visit intermediate air supports in increasing order"
	):
		return
	camera.call("set_top_down_level", 0.0)
	floating_token.queue_free()
	grounded_token.queue_free()
	tall_token.queue_free()

	camera.call("exit_top_down_2d")
	if not _check(
		camera.global_transform.is_equal_approx(original_transform)
		and camera.projection == Camera3D.PROJECTION_PERSPECTIVE
		and is_equal_approx(camera.near, initial_near),
		"leaving 2D must restore 3D transform, projection and near clipping"
	):
		return

	# Continuous 2D floor navigation: one initial step, a short delay,
	# then repeat while Space is held, without skipping solid surfaces.
	camera.call("set_top_down_floor_levels_provider", Callable(self, "_hold_fixture_levels"))
	camera.call("enter_top_down_2d", Vector3.ZERO, 30.0, 0.0)
	var repeat_size: float = camera.size
	camera.call("_advance_top_down_level_hold", 1, 0.016)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 6.0),
		"holding Space must start with an immediate step"
	):
		return
	camera.call("_advance_top_down_level_hold", 1, 0.20)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 6.0),
		"the initial repeat delay must prevent accidental double steps"
	):
		return
	camera.call("_advance_top_down_level_hold", 1, 0.10)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 12.0),
		"holding Space beyond the delay must reach the next floor"
	):
		return
	camera.call("_advance_top_down_level_hold", 1, 0.12)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 18.0),
		"holding Space must keep repeating through all solid floors"
	):
		return
	camera.call("_advance_top_down_level_hold", 1, 0.5)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 18.0),
		"holding Space at the highest floor must not create phantom levels"
	):
		return

	camera.call("_advance_top_down_level_hold", 0, 0.016)
	camera.call("_advance_top_down_level_hold", -1, 0.016)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 12.0),
		"Shift+Space must start descending immediately"
	):
		return
	camera.call("_advance_top_down_level_hold", -1, 0.29)
	camera.call("_advance_top_down_level_hold", -1, 0.12)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 0.0),
		"holding Shift+Space must keep descending to the lowest floor"
	):
		return

	camera.call("_advance_top_down_level_hold", 1, 0.016)
	camera.call("_advance_top_down_level_hold", -1, 0.016)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 0.0),
		"toggling Shift while holding Space must reverse direction immediately"
	):
		return
	camera.call("_advance_top_down_level_hold", 0, 0.016)
	camera.call("_advance_top_down_level_hold", 1, 0.016)
	if not _check(
		is_equal_approx(float(camera.call("get_top_down_level")), 6.0)
		and is_equal_approx(camera.size, repeat_size),
		"releasing and pressing Space must rearm one step without changing zoom"
	):
		return
	camera.call("exit_top_down_2d")
	if not _check(
		camera.global_transform.is_equal_approx(original_transform),
		"held 2D movement must still restore the original 3D camera pose"
	):
		return

	board.queue_free()
	await process_frame
	print("PASS: 2D floors, persistent readable token conditions, held floor stepping and 3D restoration")
	quit()
