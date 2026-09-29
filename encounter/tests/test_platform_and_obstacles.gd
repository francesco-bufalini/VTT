extends SceneTree

const Coverage = preload("res://encounter/obstacle_coverage.gd")
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
	await process_frame

func run() -> void:
	var scene: Node = load("res://encounter/kaos_klothis.tscn").instantiate()
	root.add_child(scene)
	var controller: Node = scene.get_node("EncounterProgressController")
	var kaos: Node3D = scene.get_node("KaosRoot")
	var deck: Node3D = kaos.get_node("ShoulderPlatform")
	var token: CharacterBody3D = scene.get_node("Tokens").get_child(0)
	var effects: Node3D = scene.get_node("EnvironmentCollapseController")
	check(effects.get_node("PersistentRubble").multimesh.instance_count == 0, "clear initial terrain")
	check(not effects.has_node("RuinRemnants"), "no initial decorative obstacles")
	check(controller.hazards.threatened_cells.size() >= 350, "dense threats")
	token.set_flying(true)
	token.position = deck.global_position + Vector3(4.5, 4, 2.5)
	var initial_height := token.position.y
	await frames(20)
	check(is_equal_approx(token.position.y, initial_height), "flight holds altitude")
	token.nudge_vertical(1)
	check(is_equal_approx(token.position.y, initial_height + 1), "one square up")
	token.nudge_vertical(-1)
	check(is_equal_approx(token.position.y, initial_height), "one square down")
	token.set_flying(false)
	await frames(75)
	check(token.is_on_floor(), "lands on shoulders")
	check(is_instance_valid(token.grid_support) and token.grid_support == deck, "deck support acquired")
	check(absf(token.position.y - deck.global_position.y - 1.0) < 0.08, "feet at shoulder height")
	var local_before: Vector3 = deck.to_local(token.position)
	await kaos.animate_to_step(8, 0.3)
	await frames(3)
	check(deck.to_local(token.position).distance_to(local_before) < 0.1, "rider carried without grid drift")
	# Ground cell collapse cannot block a token on the deck.
	controller.hazards._collapsed[Vector2i(floori(token.position.x + 1), floori(token.position.z))] = true
	check(controller.hazards.can_move_token(token, token.position + Vector3.RIGHT), "altitude-aware hazard validation")
	token.set_flying(true)
	var flying_position := token.position
	await kaos.animate_to_step(6, 0.2)
	await frames(3)
	check(token.position.distance_to(flying_position) < 0.1, "flying token not carried")
	token.position = deck.global_position + Vector3(30, 4, 0)
	token.set_flying(false)
	var before_fall := token.position.y
	await frames(20)
	check(token.position.y < before_fall - 0.2, "removing flying resumes gravity outside deck")
	print("PASS flight, vertical steps, landing and transport")
	var sweep := AABB(Vector3.ZERO, Vector3(20, 100, 20))
	var boxes: Array[AABB] = [AABB(Vector3.ZERO, Vector3(10, 4, 20))]
	check(is_equal_approx(Coverage.fraction(sweep, boxes, 4), 0.5), "exact 50 percent")
	boxes.append(boxes[0])
	check(is_equal_approx(Coverage.fraction(sweep, boxes, 4), 0.5), "overlap counted once")
	boxes = [AABB(Vector3.ZERO, Vector3(20, 3.99, 20))]
	check(Coverage.fraction(sweep, boxes, 4) == 0, "below four squares ignored")
	boxes = [AABB(Vector3(10, 101, 0), Vector3(10, 4, 20))]
	check(Coverage.fraction(sweep, boxes, 4) == 0, "objects above Kaos ignored")
	controller.reset_encounter(42)
	var obstacle: Node3D = load("res://encounter/collapse_object.tscn").instantiate()
	var path: AABB = kaos.get_swept_bounds(10, 8)
	obstacle.size_cells = Vector3(path.size.x * 0.51, 4, path.size.z)
	obstacle.collapsible = false
	scene.add_child(obstacle)
	obstacle.position = path.position + Vector3(obstacle.size_cells.x * 0.5, 0, path.size.z * 0.5)
	controller.refresh_obstacle_slowing()
	check(controller.kaos_slowed and controller.obstacle_slowed, "3D obstacles set slow status")
	controller.config.advance_duration = 0.05
	controller.advance_encounter()
	while controller.is_advancing:
		await process_frame
	check(controller.kaos_step == 9, "obstacles reduce advance to one step")
	check(effects.get_node("PersistentRubble").multimesh.instance_count > 350, "3D debris appears after collapse")
	check(effects.get_obstacle_boxes().any(func(box: AABB): return box.size.y >= 4), "tall debris bounds")
	obstacle.free()
	controller.reset_encounter(42)
	var collapsing: Node3D = load("res://encounter/collapse_object.tscn").instantiate()
	scene.add_child(collapsing)
	var target_cell: Vector2i = controller.hazards.threatened_cells[0]
	collapsing.position = Vector3(target_cell.x + 0.5, 0, target_cell.y + 0.5)
	controller.advance_encounter()
	while controller.is_advancing:
		await process_frame
	check(collapsing.collapsed, "existing 3D object collapses with its cells")
	check(collapsing._shape.disabled, "collapsed object collider disabled")
	print("PASS obstacle union, thresholds, slowdown and 3D collapse")
	scene.free()
	print("Platform/obstacle checks: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)
