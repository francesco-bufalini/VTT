extends SceneTree

const MeasurementTool = preload("res://measurement_tool.gd")
const SpellSystem = preload("res://vtt/spells/spell_system.gd")


class FakeBoard:
	extends Node3D

	var cell_size: float = 1.0
	var _ui_owns_mouse: bool = false
	var affected_tokens: Array = []

	func set_affected_token_highlight(tokens: Array) -> void:
		affected_tokens = tokens.duplicate()


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


func _transient_aoe_count(measure: Node) -> int:
	var count: int = 0
	for child: Node in measure.get_children():
		if child is Node3D and String(child.name).begins_with("TransientAoE"):
			count += 1
	return count


func run() -> void:
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
	measure.call("set_spell_affected_token_highlight", [token], true)
	if board.affected_tokens.size() != 1:
		_fail("red affected cells were not established before cancel")
		return

	spell.set("_pending_spell_id", "fireball")
	spell.set("_pending_spell_data", {"id": "fireball"})
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_fail("Esc did not return control to the captured camera")
		return

	# A confirmed point AoE is intentionally non-expiring: its final area and
	# affected cells stay together until dismiss_post_cast_visuals().
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
	spell.call("_cast_spell_at_point", caster, Vector3.ZERO, fireball)
	measure.call("set_spell_affected_token_highlight", [token], true)

	spell.set("_pending_spell_id", "fireball")
	spell.set("_pending_spell_data", fireball)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	spell.call("_finish_cast")

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_fail("completed cast did not return control to the camera")
		return
	if not bool(spell.call("has_post_cast_cleanup")):
		_fail("completed cast did not arm post-cast cleanup")
		return

	await create_timer(0.12).timeout
	if _transient_aoe_count(measure) != 1:
		_fail("confirmed point AoE expired before the next click")
		return
	if board.affected_tokens.size() != 1:
		_fail("red affected cells did not persist with the confirmed AoE")
		return

	if not bool(spell.call("dismiss_post_cast_visuals")):
		_fail("post-cast cleanup was not dismissed")
		return
	await process_frame

	if _transient_aoe_count(measure) != 0:
		_fail("confirmed AoE remained after post-cast cleanup")
		return
	if not board.affected_tokens.is_empty():
		_fail("red affected cells remained after post-cast cleanup")
		return

	board.queue_free()
	await process_frame
	print("PASS: spell targeting visual lifecycle")
	quit()
