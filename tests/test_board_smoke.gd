extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Node = load("res://dnd_base.tscn").instantiate()
	root.add_child(scene)
	await process_frame

	var measure: Node = scene.measurement_tool
	var sync: Node = scene.board_sync
	assert(measure != null)
	assert(sync != null)

	measure.add_aoe(
		Vector3(1, 0, 1),
		Vector3(2, 0, 1),
		"sphere"
	)

	var token: Node3D = load("res://token.tscn").instantiate()
	scene.tokens_root.add_child(token)
	token.position = Vector3(2.0, 1.0, 2.0)
	token.set_flying(true)

	var snapshot: Dictionary = JSON.parse_string(
		JSON.stringify(sync.create_snapshot())
	)
	assert(sync.valid_snapshot(snapshot))
	assert(snapshot.objects.size() == 1)
	assert(snapshot.aoes.size() == 1)
	assert(sync.apply_snapshot(snapshot))

	scene.queue_free()
	await process_frame
	print("PASS: lightweight board scene + token + AoE snapshot smoke test")
	quit()
