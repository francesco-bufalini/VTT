extends SceneTree

const GridHighlightRenderer = preload("res://vtt/grid_highlight_renderer.gd")
const MeasurementTool = preload("res://measurement_tool.gd")
const SpellSystem = preload("res://vtt/spells/spell_system.gd")


class FakeBoard:
	extends Node3D

	var cell_size: float = 1.0
	var _ui_owns_mouse: bool = false
	var affected_tokens: Array = []
	var camera_control_requests: int = 0

	func set_affected_token_highlight(tokens: Array) -> void:
		affected_tokens = tokens.duplicate()

	func capture_camera_control() -> void:
		_ui_owns_mouse = false
		camera_control_requests += 1


class FakeToken:
	extends Node3D

	var token_height_cells: float = 2.0

	func get_footprint_cells() -> int:
		return 1


func _initialize() -> void:
	call_deferred("run")


func _fail(message: String) -> void:
	push_error("Spell targeting lifecycle: " + message)
	quit(1)


func _held_aoe_count(measure: Node) -> int:
	var count: int = 0
	# Godot renames siblings with duplicate names; use the tracked area roots.
	for child: Node3D in measure.get("_held_spell_aoes"):
		if is_instance_valid(child) and child.get_parent() == measure:
			count += 1
	return count


func run() -> void:
	# Regression at the actual grid renderer layer: invalidating the previous
	# signature and then rendering zero tokens must clear stale MultiMesh
	# instances. This is the exact 1-token -> 0-token transition used when a
	# Fireball preview moves completely off the last affected token.
	var renderer_owner := Node3D.new()
	var red_multimesh := MultiMesh.new()
	red_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	red_multimesh.instance_count = 2
	red_multimesh.visible_instance_count = 2
	var no_tokens: Array[CharacterBody3D] = []
	var empty_signature: String = GridHighlightRenderer.refresh(
		renderer_owner,
		no_tokens,
		red_multimesh,
		"",
		1.0
	)
	if red_multimesh.instance_count != 0:
		_fail("grid renderer kept stale red instances after 1-token -> 0-token")
		return
	if empty_signature.is_empty():
		_fail("empty grid highlight still collides with invalidated signature")
		return
	renderer_owner.free()

	var board := FakeBoard.new()
	root.add_child(board)

	var measure: Node3D = MeasurementTool.new()
	measure.name = "MeasurementTool"
	board.add_child(measure)

	var token := FakeToken.new()
	token.name = "LifecycleTarget"
	token.add_to_group("dnd_token")
	board.add_child(token)

	var spell: Node = SpellSystem.new()
	board.add_child(spell)
	spell.set("board_root", board)

	await process_frame

	# Esc while aiming must synchronously remove both preview geometry and red
	# affected cells, then return mouse control to the captured camera.
	measure.call(
		"show_spell_preview",
		Vector3.ZERO,
		Vector3.RIGHT * 4.0,
		"sphere",
		"fire"
	)
	spell.call(
		"_set_spell_geometry_highlight",
		Vector3.ZERO,
		Vector3.RIGHT * 4.0,
		{
			"aoe_shape": "sphere",
			"aoe_radius_feet": 20.0,
			"visual_style": "fireball"
		},
		null
	)
	if board.affected_tokens.size() != 1:
		_fail("red affected cells were not established before cancel")
		return

	# Regression: moving the sphere away must immediately un-highlight the
	# last token it touched; moving it back must highlight it again.
	spell.call(
		"_set_spell_geometry_highlight",
		Vector3.RIGHT * 20.0,
		Vector3.RIGHT * 24.0,
		{
			"aoe_shape": "sphere",
			"aoe_radius_feet": 20.0,
			"visual_style": "fireball"
		},
		null
	)
	if not board.affected_tokens.is_empty():
		_fail("token stayed red after the preview sphere moved away")
		return
	spell.call(
		"_set_spell_geometry_highlight",
		Vector3.ZERO,
		Vector3.RIGHT * 4.0,
		{
			"aoe_shape": "sphere",
			"aoe_radius_feet": 20.0,
			"visual_style": "fireball"
		},
		null
	)
	if board.affected_tokens.size() != 1:
		_fail("token did not become red again when the sphere returned")
		return

	spell.set("_pending_spell_id", "fireball")
	spell.set("_pending_spell_data", {"id": "fireball"})

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	if not bool(spell.call("handle_input", esc)):
		_fail("Esc was not consumed by spell targeting")
		return

	var preview := measure.get_node_or_null("SpellAoEPreview") as MeshInstance3D
	if preview != null and preview.visible:
		_fail("spell preview remained visible after Esc")
		return
	if not board.affected_tokens.is_empty():
		_fail("red affected cells remained after Esc")
		return
	if board.camera_control_requests != 1:
		_fail("Esc did not request camera control restoration")
		return

	# A confirmed point AoE is intentionally non-expiring: its final area and
	# affected cells stay together until that specific area is clicked.
	var caster := Node3D.new()
	board.add_child(caster)
	var fireball := {
		"id": "fireball",
		"aoe_shape": "sphere",
		"aoe_radius_feet": 20.0,
		"persistent": false,
		"transient_seconds": 0.05,
		"style": "fire"
	}
	spell.set("_pending_spell_id", "fireball")
	spell.set("_pending_spell_data", fireball)
	spell.call("_commit_point_spell_cast", caster, Vector3.ZERO, fireball)

	if board.camera_control_requests != 2:
		_fail("completed cast did not request camera control restoration")
		return
	if not bool(spell.call("has_post_cast_cleanup")):
		_fail("completed cast did not arm post-cast cleanup")
		return

	await create_timer(0.12).timeout
	if _held_aoe_count(measure) != 1:
		_fail("confirmed point AoE disappeared without clicking its area")
		return
	if board.affected_tokens.size() != 1:
		_fail("red affected cells did not persist with the confirmed AoE")
		return

	# Area cleanup must be targeted: removing one spell area cannot erase a
	# different spell area that is still on the map.
	measure.call(
		"show_held_spell_aoe",
		Vector3.RIGHT * 10.0,
		Vector3.RIGHT * 12.0,
		"sphere",
		"cold"
	)
	var held_roots: Array[Node3D] = []
	for child: Node3D in measure.get("_held_spell_aoes"):
		if is_instance_valid(child) and child.get_parent() == measure:
			held_roots.append(child)
	if held_roots.size() != 2:
		_fail("second held spell AoE was not created for targeted cleanup")
		return
	if not bool(
		measure.call("_remove_post_cast_spell_root", held_roots[0])
	):
		_fail("clicked spell AoE could not be removed individually")
		return
	await process_frame
	if _held_aoe_count(measure) != 1:
		_fail("removing one spell AoE also removed another area")
		return

	if not bool(spell.call("dismiss_post_cast_visuals")):
		_fail("post-cast cleanup was not dismissed")
		return
	await process_frame

	if _held_aoe_count(measure) != 0:
		_fail("remaining AoE survived explicit post-cast cleanup")
		return
	if not board.affected_tokens.is_empty():
		_fail("red affected cells remained after post-cast cleanup")
		return

	board.queue_free()
	await process_frame
	print("PASS: spell targeting visual lifecycle")
	quit()
