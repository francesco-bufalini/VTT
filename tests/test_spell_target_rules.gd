extends SceneTree

const TargetRules = preload("res://vtt/spells/spell_target_rules.gd")
const TargetInput = preload("res://vtt/spells/spell_target_input.gd")
const SpellSystem = preload("res://vtt/spells/spell_system.gd")
const MeasurementTool = preload("res://measurement_tool.gd")
const TargetOverlay = preload("res://vtt/spells/spell_target_overlay_2d.gd")


class TestBoard extends Node3D:
	var cell_size: float = 1.0
	func is_2d_view_enabled() -> bool:
		return true


class TestToken extends Node3D:
	var token_height_cells: float = 2.0
	var label: String = ""
	func get_footprint_cells() -> int:
		return 1
	func get_display_name() -> String:
		return label


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var board := TestBoard.new()
	root.add_child(board)
	var measure := MeasurementTool.new()
	measure.name = "MeasurementTool"
	board.add_child(measure)
	var spell := SpellSystem.new()
	board.add_child(spell)
	spell.board_root = board
	var caster := TestToken.new()
	caster.label = "Mage"
	caster.add_to_group("dnd_token")
	board.add_child(caster)
	var nearby := TestToken.new()
	nearby.label = "Goblin"
	nearby.position = Vector3(1, 0, 0)
	nearby.add_to_group("dnd_token")
	board.add_child(nearby)
	var distant := TestToken.new()
	distant.label = "Dragon"
	distant.position = Vector3(10, 0, 0)
	distant.add_to_group("dnd_token")
	board.add_child(distant)
	await process_frame

	var line_spell := {
		"id": "probe", "target_mode": "token_then_direction",
		"aoe_shape": "line", "range_feet": 30.0,
		"line_width_feet": 5.0
	}
	spell._pending_spell_id = "probe"
	spell._pending_spell_data = line_spell
	spell._pending_caster = caster
	spell._targeting_phase = "target_token"
	assert(TargetRules.token_in_range(caster, nearby, 5.0, 1.0).get("valid", false))
	assert(not TargetRules.token_in_range(caster, distant, 5.0, 1.0).get("valid", false))
	assert(not TargetRules.token_in_range(caster, caster, 5.0, 1.0).get("valid", false))
	assert(TargetRules.token_in_range(caster, caster, 5.0, 1.0, false).get("valid", false))
	assert(TargetRules.point_in_range(Vector3.ZERO, Vector3.RIGHT * 2.0, 10.0, 1.0).get("valid", false))
	assert(TargetRules.point_in_range(Vector3.ZERO, Vector3.RIGHT * 3.0, 10.0, 1.0).get("out_of_range", false))

	# All UI adapters resolve to the same functional candidate validator.
	assert(spell._target_token_candidate(nearby, line_spell).get("valid", false))
	assert(not spell._target_token_candidate(distant, line_spell).get("valid", false))
	assert(not spell._target_token_candidate(caster, line_spell).get("valid", false))
	var invalid_target: Dictionary = spell._target_or_point_candidate(
		distant, {"valid": true, "point": nearby.position},
		line_spell.merged({"allow_point_target": true})
	)
	assert(not invalid_target.get("valid", false) and invalid_target.get("kind") == "token",
		"Out-of-reach token must not silently become a point")

	# Phone tokens/points bypass both screen raycasting and the 2D camera.
	spell._remote_input_active = true
	spell._remote_pick_token = nearby
	spell._remote_pick_point = {
		"valid": true, "point": Vector3.RIGHT, "normal": Vector3.UP,
		"in_air": false
	}
	assert(spell._target_token_data(Vector2(1000, 1000), line_spell).get("target") == nearby)
	assert(spell._point_target_data(Vector2(1000, 1000), line_spell).get("point") == Vector3.RIGHT)
	spell._remote_input_active = false

	# Chain secondary originates at its primary, not the caster.
	spell._pending_chain_primary = nearby
	spell._targeting_phase = "chain_secondary"
	assert(spell._chain_secondary_candidate(caster, {"secondary_range_feet": 5.0}).get("valid", false))
	assert(not spell._chain_secondary_candidate(nearby, {"secondary_range_feet": 5.0}).get("valid", false))
	var chain_info: Dictionary = spell.targeting_range_info({"secondary_range_feet": 30.0, "range_feet": 120.0})
	assert(chain_info.get("source") == nearby and is_equal_approx(float(chain_info.get("feet")), 30.0))

	# Both the measurement query and caster-filtered spell query use identical
	# intersection geometry. Only a spell's functional targets omit the caster.
	var start := Vector3.ZERO
	var end := Vector3.RIGHT * 2.0
	var touched: Array[Node3D] = measure.spell_geometry_affected_tokens(
		start, end, "line", "", 1.0
	)
	assert(caster in touched and nearby in touched)
	var selected: Array[Node3D] = TargetRules.filter_affected(touched, caster, line_spell)
	assert(caster not in selected and nearby in selected)
	assert(caster in TargetRules.filter_affected(touched, caster, {"target_mode": "token_then_point"}))

	var overlay := TargetOverlay.new()
	overlay.board = board
	overlay.measure = measure
	overlay.spell = spell
	board.add_child(overlay)
	var measured_names: Array[String] = overlay._target_names(start, end, "line", 1.0)
	assert("Mage" in measured_names and "Goblin" in measured_names)
	var cast_names: Array[String] = overlay._target_names(start, end, "line", 1.0, "", true)
	assert("Mage" not in cast_names and "Goblin" in cast_names)
	var range_names: Array[String] = overlay._range_target_names()
	assert("Mage" in range_names or "Goblin" in range_names)
	assert(not ("Dragon" in range_names))

	assert(not TargetInput.top_down_point(board, Vector2.ZERO).get("valid", false),
		"Missing desktop camera is invalid, while mobile resolved targets still work")
	board.queue_free()
	await process_frame
	print("PASS: view-independent spell candidates, range policies, mobile input and inclusive measurement")
	quit()
