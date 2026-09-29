extends SceneTree

var failures: int = 0
var scene: Node
var progress: Node

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func advance() -> void:
	progress.advance_encounter()
	while progress.is_advancing:
		await process_frame

func _run() -> void:
	scene = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	progress = scene.get_node("EncounterProgressController")
	progress.config.advance_duration = 0.01
	check(scene.get_node("KaosPositions").get_child_count() == 11, "11 markers")
	var distance_tool: Node = scene.get_node("MeasurementTool")
	check(is_equal_approx(distance_tool.world_to_meters(distance_tool.meters_to_world(150)), 150), "scale roundtrip")
	check(distance_tool._dnd_grid_distance_cells(Vector3(2, 2, 2)) == 3, "existing 5-10-5 distance")
	check(scene.get_node("VolumetricGrid").cube_size_world == 30, "local 3D grid unchanged")
	var klothis_transform: Transform3D = scene.get_node("KlothisRoot").transform
	var final_signals: Array[int] = [0]
	root.get_node("EncounterEvents").kaos_reached_klothis.connect(func(): final_signals[0] += 1)
	progress.reset_encounter(12345)
	check(progress.get_remaining_meters() == 150, "initial 150m")
	for i in range(5):
		await advance()
		check(progress.kaos_step == 8 - i * 2, "normal advance")
	check(progress.encounter_finished and progress.round_number == 5, "case 1: five rounds")
	check(final_signals[0] == 1, "one global finish signal")
	print("PASS case 1: normal movement")
	progress.reset_encounter(12345)
	for i in range(10):
		progress.register_kaos_damage(progress.config.slow_damage_threshold * 3)
		check(progress.kaos_slowed and progress.get_next_movement_meters() == 15, "slow feedback, non stacking")
		await advance()
		check(progress.kaos_step == 9 - i and progress.damage_since_last_advance == 0, "one step and reset damage")
	check(progress.round_number == 10 and progress.encounter_finished, "case 2: ten rounds")
	print("PASS case 2: always slowed")
	progress.reset_encounter(12345)
	while not progress.encounter_finished:
		if progress.round_number % 2 == 0:
			progress.register_kaos_damage(progress.config.slow_damage_threshold)
		await advance()
		check(progress.kaos_step >= 0, "no overshoot")
	check(progress.round_number == 7, "case 3: alternating, seven rounds")
	print("PASS case 3: alternating")
	progress.reset_encounter(12345)
	progress.config.advance_duration = 0.05
	progress.advance_encounter()
	for i in range(20):
		progress.advance_encounter()
	check(progress.get_save_state().is_empty(), "refuse incomplete snapshot")
	while progress.is_advancing:
		await process_frame
	check(progress.round_number == 1 and progress.kaos_step == 8, "case 4: spam locked")
	print("PASS case 4: spam")
	progress.reset_encounter(12345)
	var first: Array = progress.hazards.threatened_cells.duplicate()
	check(not first.is_empty(), "initial threats")
	progress.advance_encounter()
	check(progress.hazards.threatened_cells.is_empty(), "no new threats during animation")
	check(progress.hazards.collapsed_cells == first, "immediate deterministic collapse")
	while progress.is_advancing:
		await process_frame
	for cell: Vector2i in progress.hazards.threatened_cells:
		check(not first.has(cell) and scene.get_node("HazardAllowedArea").contains_cell(cell), "only authorized fresh cells")
	var token: Node3D = scene.get_node("Tokens").get_child(0)
	var blocked_point: Vector3 = Vector3(first[0].x + 0.5, 1, first[0].y + 0.5) * scene.cell_size
	check(not progress.hazards.can_move_token(token, blocked_point), "collapsed movement blocked")
	check(token.movement_validator.is_valid(), "token integration")
	print("PASS case 5: hazards and movement")
	var second: Array = progress.hazards.threatened_cells.duplicate()
	progress.reset_encounter(12345)
	check(progress.hazards.threatened_cells == first, "case 6: initial seed")
	await advance()
	check(progress.hazards.threatened_cells == second, "case 6: advanced seed")
	print("PASS case 6: reproducible RNG")
	await advance()
	progress.register_kaos_damage(23)
	var saved: Dictionary = progress.get_save_state()
	var kaos_position: Vector3 = scene.get_node("KaosRoot").position
	await advance()
	var next_state: Dictionary = progress.get_save_state()
	# A fresh scene verifies reconstruction, not just mutation of the old one.
	scene.free()
	scene = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	progress = scene.get_node("EncounterProgressController")
	progress.config.advance_duration = 0.01
	var json_copy: Dictionary = JSON.parse_string(JSON.stringify(saved))
	check(progress.load_state(json_copy), "load JSON snapshot")
	check(JSON.stringify(progress.get_save_state()) == JSON.stringify(saved), "case 7: complete restored state")
	check(scene.get_node("KaosRoot").position.is_equal_approx(kaos_position), "restored marker position")
	check(scene.get_node("EnvironmentCollapseController/CollapsedCells").multimesh.instance_count == saved.collapsed_cells.size(), "rebuilt collapsed visuals")
	await advance()
	check(JSON.stringify(progress.get_save_state()) == JSON.stringify(next_state), "restored future RNG sequence")
	print("PASS case 7: reload and future RNG")
	while not progress.encounter_finished:
		await advance()
	var final_state: Dictionary = progress.get_save_state()
	await advance()
	check(progress.get_save_state() == final_state and progress.hazards.threatened_cells.is_empty(), "case 8: terminal state")
	check(scene.get_node("KlothisRoot").transform == klothis_transform, "Klothis immobile")
	check(scene.get_node("KaosRoot").position.is_equal_approx(scene.get_node("KaosPositions/KaosPosition_00").position), "exact end marker")
	scene._show_context_menu(Vector2(200, 200))
	check(scene.context_menu.is_item_disabled(scene.context_menu.get_item_index(100)), "finished menu disabled")
	print("PASS case 8: end and disabled menu")
	scene.free()
	var base: Node = load("res://dnd_base.tscn").instantiate()
	root.add_child(base)
	base._show_context_menu(Vector2(200, 200))
	check(base.context_menu.get_item_index(100) == -1, "base has no encounter menu")
	base.free()
	print("Encounter checks finished: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
