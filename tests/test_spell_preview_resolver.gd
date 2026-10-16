extends SceneTree

const SpellSystem = preload("res://vtt/spells/spell_system.gd")

class MockBoard extends Node3D:
	var cell_size: float = 2.0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var board := MockBoard.new()
	root.add_child(board)
	var spell := SpellSystem.new()
	board.add_child(spell)
	spell.board_root = board
	var token := Node3D.new()
	token.position = Vector3(4, 0, 3)
	board.add_child(token)

	# Only the view layer is normalized: domain resolvers retain the original
	# point/token distinction and the correct tactical range calculations.
	var endpoint: Dictionary = spell._preview_target_endpoint({
		"valid": true, "kind": "token", "target": token
	})
	assert(bool(endpoint.get("valid", false)) and endpoint["point"] == token.global_position)
	var point: Dictionary = spell._preview_target_endpoint({
		"valid": true, "kind": "point", "point": Vector3(5, 6, 7)
	})
	assert(point.get("point") == Vector3(5, 6, 7))
	assert(spell._preview_target_endpoint({"valid": false}).is_empty())

	var line: Dictionary = spell._line_preview(Vector3.ZERO, Vector3.RIGHT, "projectile")
	assert(line.get("shape") == "line" and line.get("style") == "projectile")
	assert(not line.has("width") and not line.has("highlight_geometry"))
	var summon: Dictionary = spell._line_preview(Vector3.ZERO, Vector3.RIGHT, "summon", "sphere")
	assert(summon.get("shape") == "sphere" and not summon.has("width"))

	var spec: Dictionary = {"aoe_shape": "sphere", "aoe_radius_feet": 10.0,
		"visual_style": "fireball"}
	var area: Dictionary = spell._area_preview(Vector3.ZERO, spec, token)
	assert(bool(area.get("valid", false)) and bool(area.get("highlight_geometry", false)))
	assert(area.get("start") == Vector3.ZERO)
	assert((area.get("end", Vector3.ZERO) as Vector3).distance_to(Vector3.RIGHT * 4.0) < 0.001)
	assert(area.has("width"))
	var aimed: Dictionary = spell._direction_preview(
		{"start": Vector3.ZERO, "end": Vector3.FORWARD * 2}, spec, token, "line"
	)
	assert(aimed.get("shape") == "sphere" and aimed.get("end") == Vector3.FORWARD * 2)
	assert(spell._direction_preview({}, spec, token, "line").is_empty())

	# Range feedback uses the same cell conversion as range validation.
	assert(is_equal_approx(spell._spell_range_world(25.0), 10.0))
	assert(spell._effective_spell_range_feet({"range": "Touch", "range_feet": 60}) == 5.0)
	board.queue_free()
	await process_frame
	print("PASS: spell preview descriptors, point/token endpoints and tactical range conversion")
	quit()
