extends SceneTree

const SCENE_PATH := "res://encounter/post_kaos_editable.scn"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		_fail("Cannot load %s" % SCENE_PATH)
		return
	var scene := packed.instantiate()
	if scene == null:
		_fail("Cannot instantiate post-Kaos scene.")
		return

	var script: Script = scene.get_script()
	if script == null or script.resource_path != "res://encounter/post_kaos_scene.gd":
		_fail("Post-Kaos scene is not using post_kaos_scene.gd.")
		return

	var ui := scene.get_node_or_null("UI")
	if ui == null:
		_fail("UI root is missing.")
		return
	var baked_ui_names: Array[String] = []
	for child in ui.get_children():
		baked_ui_names.append(String(child.name))
	baked_ui_names.sort()
	var expected_ui := [
		"ContextMenu",
		"Crosshair",
		"MeasurementModeLabel",
		"TokenColorDialog",
	]
	expected_ui.sort()
	if baked_ui_names != expected_ui:
		_fail("Baked scene contains runtime UI nodes: %s" % [baked_ui_names])
		return

	if scene.get_node_or_null("KaosRoot/ShoulderPlatform") != null:
		_fail("Legacy Kaos shoulder platform is still baked.")
		return
	if scene.get_node_or_null("HandPlatforms") != null:
		_fail("Legacy Klothis hand platforms are still baked.")
		return

	root.add_child(scene)
	await process_frame
	await physics_frame
	await process_frame

	if _find_kaos_token(scene) != null:
		_fail("KaosPhaseTwo token still exists.")
		return

	var kaos_collisions := _count_body_collisions(
		scene.get_node_or_null("KaosRoot/ClimbingVisual")
	)
	var klothis_collisions := _count_body_collisions(
		scene.get_node_or_null("KlothisRoot/KlothisVisual")
	)
	if kaos_collisions < 1:
		_fail("Kaos has no walkable body collision.")
		return
	if klothis_collisions < 1:
		_fail("Klothis has no walkable body collision.")
		return

	var chariots := 0
	for child in scene.get_node("Tokens").get_children():
		if bool(child.get_meta("compound_chariot", false)):
			chariots += 1
	if chariots != 4:
		_fail("Expected 4 post-Kaos chariots, found %d." % chariots)
		return

	print(
		(
			"PASS: post-Kaos scene clean; Kaos collisions=%d, "
			+ "Klothis collisions=%d, chariots=%d"
		)
		% [kaos_collisions, klothis_collisions, chariots]
	)
	# Let runtime controllers, listeners and scene resources leave the tree
	# cleanly before the headless test process exits.
	scene.queue_free()
	packed = null
	await process_frame
	await process_frame
	quit(0)

func _find_kaos_token(scene: Node) -> Node:
	for child in scene.get_node("Tokens").get_children():
		if (
			child.name == "KaosPhaseTwo"
			or bool(child.get_meta("kaos_phase_two", false))
		):
			return child
	return null

func _count_body_collisions(root_node: Node) -> int:
	if root_node == null:
		return 0
	var count := 0
	for node in root_node.find_children("*", "StaticBody3D", true, false):
		if bool(node.get_meta("post_kaos_body_collision", false)):
			count += 1
	return count

func _fail(message: String) -> void:
	push_error(message)
	print("FAIL: %s" % message)
	quit(1)
